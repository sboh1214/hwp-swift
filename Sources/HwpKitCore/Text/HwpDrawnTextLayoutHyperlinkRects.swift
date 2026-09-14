import CoreGraphics
import CoreText
import Foundation

// 링크 스팬 하나가 한 줄에서 차지하는 rect — `HwpDrawnTextLayout.hyperlinkRegions`의
// 줄 단위 알맹이 (#197 리뷰).

extension HwpDrawnTextLayout {
    /// 한 줄에서 링크 스팬이 차지하는 rect들을 `regions`에 바로 쌓는다 — 줄 상자 rect
    /// **하나**와, 글자 위치로 옮겨진 run 중 **이 스팬에 속한 것마다** 밴드 rect.
    /// (배열로 돌려주면 줄마다 임시 할당이 생겨 캐시로 아낀 몫의 절반을 도로 쓴다 —
    /// 실측 median: 120스팬 ~40줄 2.93 → 3.55ms.)
    ///
    /// 스팬 전체 폭에 최대 오프셋을 걸면 안 옮겨진 run 위·아래의 빈 자리까지 이 링크가
    /// 가져가, 뒤에 있는 링크가 진다 (`paintedRects`와 같은 R54 정밀 커버리지 규약,
    /// #197 리뷰 3차).
    static func appendHyperlinkRects(
        of drawn: HwpDrawnLine,
        spanRange: NSRange,
        bands: [GlyphOffsetBand],
        url: String,
        into regions: inout [(rect: CGRect, url: String)]
    ) {
        let lineRange = drawn.stringRange
        let lower = max(spanRange.location, lineRange.location)
        let upper = min(
            spanRange.location + spanRange.length, lineRange.location + lineRange.length
        )
        guard upper > lower else { return }
        let ctRange = CTLineGetStringRange(drawn.line)
        func offsetX(atAttributedIndex index: Int) -> CGFloat {
            let ctIndex = ctRange.location + (index - lineRange.location)
            return CTLineGetOffsetForStringIndex(drawn.line, ctIndex, nil)
        }
        // RTL 줄은 CT가 하위 논리 인덱스에 더 큰 x 오프셋을 줘 lower>upper가
        // 된다 — min/max로 정규화해 링크 rect를 낸다 (#1).
        let lowerX = drawn.baselineOrigin.x + offsetX(atAttributedIndex: lower)
        let upperX = drawn.baselineOrigin.x + offsetX(atAttributedIndex: upper)
        let minX = min(lowerX, upperX)
        let maxX = max(lowerX, upperX)
        guard maxX > minX else { return }
        let box = CGRect(
            x: minX, y: drawn.baselineOrigin.y - drawn.ascent,
            width: maxX - minX, height: drawn.ascent + drawn.descent
        )
        regions.append((rect: box, url: url))
        // **이 스팬에 속한 run의 밴드만** 가져간다 (#197 리뷰 4차). 가로 클립만으로는
        // 모자란다 — 양방향 텍스트에서는 스팬의 min/max 상자가 다른 링크의 글자를 덮기
        // 때문이다 (실측 `abc אבג`, `abc א`+`בג` 두 링크: 앞 스팬 상자가 0…28.313인데
        // 뒤 스팬 글자가 18.903…28.313에 있어, 뒤 링크만 10pt 올리면 올라간 잉크 위의
        // 탭이 **앞** URL을 열었다).
        let spanCTRange = CFRange(
            location: ctRange.location + (lower - lineRange.location), length: upper - lower
        )
        //
        // 소유를 가린 뒤에는 스팬 상자로 **자르지 않는다**: 밴드는 이 스팬 자신의 run 잉크고,
        // 양방향 줄에서는 그 잉크가 스팬의 min/max 상자 밖에 있을 수 있다 (같은 실측에서
        // 앞 스팬의 א는 28.313…33.943인데 상자는 0…28.313에서 끝난다 — 자르면 **자기**
        // 올라간 글자가 통째로 히트 불가가 돼 방출 ≡ 히트가 깨진다). 단방향 줄에서는 run이
        // 늘 스팬 상자 안이라 자르나 마나 같다.
        for band in bands where band.belongs(to: spanCTRange) {
            let bandMinX = drawn.baselineOrigin.x + band.minX
            let bandMaxX = drawn.baselineOrigin.x + band.maxX
            guard bandMaxX > bandMinX else { continue }
            regions.append((
                rect: CGRect(
                    x: bandMinX, y: box.minY - band.offset,
                    width: bandMaxX - bandMinX, height: box.height
                ),
                url: url
            ))
        }
    }
}
