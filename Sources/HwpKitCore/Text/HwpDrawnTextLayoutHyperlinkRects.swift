import CoreGraphics
import CoreText
import Foundation

// 링크 스팬 하나가 한 줄에서 차지하는 rect — `HwpDrawnTextLayout.hyperlinkRegions`의
// 줄 단위 알맹이 (#197 리뷰).

extension HwpDrawnTextLayout {
    /// 줄의 run 하나가 **진행 폭**으로 차지하는 가로 범위(줄 원점 기준)와 그 run의 문자열
    /// 범위 — **CTLine 인덱스**다 (`GlyphOffsetBand.ranges`와 같은 기준, 재조판된 부분
    /// 복사본이면 0-기준).
    ///
    /// 스팬 양끝의 `CTLineGetOffsetForStringIndex`로는 양방향 줄의 링크 자리를 낼 수 없다
    /// (#201): 논리 순서와 화면 순서가 달라 한 스팬이 화면에서 **떨어진 여러 구간**을
    /// 차지하고, 방향 경계 인덱스의 오프셋은 반대쪽 run의 가장자리를 가리킨다 (실측
    /// `abc אבג`, Helvetica 10pt: 인덱스 4 → 18.901, 7 → 18.901인데 א는 28.804…35.254에
    /// 있다 — 스팬 하나로 전체를 걸어도 히브리 글자 셋이 통째로 빠졌다). run은 화면 순서로
    /// 놓이고 자기 자리를 안다.
    ///
    /// 가로 범위는 `CTRunGetPositions`의 첫 글리프(run 안 글리프는 시각 순서라 가장
    /// 왼쪽)에 run 텍스트 매트릭스를 건 시작점 + `CTRunGetTypographicBounds` 폭이다 —
    /// positions는 매트릭스 **적용 전** 좌표라(장평 50% run이 줄 중간에서 두 배 자리에
    /// 선다, #200 리뷰) 렌더러(`drawRun`)처럼 매트릭스를 걸어야 줄 좌표가 되고, 폭은 적용
    /// 후 값이다. 인접 run의 끝과 다음 run의 시작은 CT가 같은 누적값을 줘 비트 단위로
    /// 같다 (실측 — 양방향·장평·기울임 근사 전부).
    struct RunExtent {
        let range: CFRange
        let minX: CGFloat
        let maxX: CGFloat

        /// 이 run이 `span` 안에 통째로 드는가 — `GlyphOffsetBand.belongs(to:)`와 같은
        /// **포함** 판정이다. CT는 속성 경계마다 run을 끊으므로 링크 스팬과 run은 안에
        /// 들거나 밖에 있지 걸치지 않는다.
        func belongs(to span: CFRange) -> Bool {
            range.location >= span.location
                && range.location + range.length <= span.location + span.length
        }
    }

    /// 줄의 run별 진행 폭 범위 — 화면 순서(`CTLineGetGlyphRuns` 순서). 글리프가 없는 run은
    /// 자리가 없으니 뺀다.
    static func runExtents(of line: CTLine) -> [RunExtent] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var extents: [RunExtent] = []
        extents.reserveCapacity(runs.count)
        for run in runs where CTRunGetGlyphCount(run) > 0 {
            var origin = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &origin)
            let start = origin.applying(CTRunGetTextMatrix(run)).x
            let width = CGFloat(
                CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
            )
            extents.append(RunExtent(
                range: CTRunGetStringRange(run), minX: start, maxX: start + width
            ))
        }
        return extents
    }

    /// `span`에 속한 run들의 가로 범위를 **화면에서 잇닿은 구간별로** 합친다 (줄 원점 기준).
    ///
    /// 단방향 줄에서는 스팬의 run이 늘 잇닿아 구간 하나 = 종전의 스팬 양끝 상자다. 양방향
    /// 줄에서는 사이에 다른 링크의 run이 끼어 구간이 여럿이다 — 그것을 외접 사각형 하나로
    /// 합치면 그 사이 글자를 다른 링크에서 뺏는다 (#201). 폭 0 구간(폭 0 개체 마커·U+200B)은
    /// 차지한 자리가 없으니 버린다 (종전의 `maxX > minX` 가드).
    ///
    /// 한 번 훑는다 — `CTLineGetGlyphRuns`가 run을 화면 순서(왼쪽→오른쪽)로 주므로 (실측
    /// 양방향·아랍 shaping 모두) 정렬·필터 배열을 스팬 × 줄마다 만들지 않는다 (120스팬
    /// ~46줄 실측 median 5.11 → 4.4ms대, 종전 산식 4.17ms). 순서가 어긋난 입력이 오면 그때만
    /// 정렬해 다시 훑는다 — 잇닿음 판정이 순서에 기대므로 순서 없이 합치면 사이 글자를 건너
    /// 다리를 놓는다.
    static func visualSegments(
        of extents: [RunExtent], in span: CFRange
    ) -> [ClosedRange<CGFloat>] {
        var segments: [ClosedRange<CGFloat>] = []
        var previousMinX = -CGFloat.infinity
        for extent in extents where extent.belongs(to: span) {
            guard extent.minX >= previousMinX else {
                return visualSegments(
                    of: extents.filter { $0.belongs(to: span) }.sorted { $0.minX < $1.minX },
                    in: span
                )
            }
            previousMinX = extent.minX
            if let last = segments.last,
               extent.minX <= last.upperBound + segmentJoinTolerance
            {
                segments[segments.count - 1] =
                    last.lowerBound ... max(last.upperBound, extent.maxX)
            } else {
                segments.append(extent.minX ... extent.maxX)
            }
        }
        segments.removeAll { $0.upperBound <= $0.lowerBound }
        return segments
    }

    /// 인접 run의 경계는 CT가 같은 누적값을 줘 정확히 같지만 (실측), 다른 조판 경로가
    /// 부동소수 오차를 내더라도 눈에 안 보이는 틈으로 구간이 갈리지 않게 둔 여유.
    private static let segmentJoinTolerance: CGFloat = 0.001

    /// 줄 하나의 스팬 기하 캐시 — `hyperlinkRegions`가 줄마다 하나씩 두고 그 줄에 닿는
    /// 스팬들이 나눠 쓴다.
    struct SpanLineGeometry {
        /// 글자 위치로 옮겨진 run의 잉크 밴드 — 줄 캐시와 함께 미리 걷는다 (옮겨진 run이
        /// 없는 문단은 CTRun 순회 없이 빈 배열, `glyphOffsetBands(ofLines:in:)`).
        let bands: [GlyphOffsetBand]
        /// run별 진행 폭 범위 (#201) — 그 줄에 처음 닿는 스팬이 걷고, 스팬이 안 닿는 줄은
        /// 걷지 않는다 (링크 하나뿐인 긴 문단에서 모든 줄을 걷지 않는다).
        var runExtents: [RunExtent]?
    }

    /// 한 줄에서 링크 스팬이 차지하는 rect들을 `regions`에 바로 쌓는다 — 스팬의 run이
    /// 화면에서 잇닿은 **구간마다** 줄 상자 rect 하나와, 글자 위치로 옮겨진 run 중 **이
    /// 스팬에 속한 것마다** 밴드 rect.
    /// (배열로 돌려주면 줄마다 임시 할당이 생겨 캐시로 아낀 몫의 절반을 도로 쓴다 —
    /// 실측 median: 120스팬 ~40줄 2.93 → 3.55ms.)
    ///
    /// 스팬 전체 폭에 최대 오프셋을 걸면 안 옮겨진 run 위·아래의 빈 자리까지 이 링크가
    /// 가져가, 뒤에 있는 링크가 진다 (`paintedRects`와 같은 R54 정밀 커버리지 규약,
    /// #197 리뷰 3차).
    static func appendHyperlinkRects(
        of drawn: HwpDrawnLine,
        spanRange: NSRange,
        geometry: inout SpanLineGeometry,
        url: String,
        into regions: inout [(rect: CGRect, url: String)]
    ) {
        let lineRange = drawn.stringRange
        let lower = max(spanRange.location, lineRange.location)
        let upper = min(
            spanRange.location + spanRange.length, lineRange.location + lineRange.length
        )
        guard upper > lower else { return }
        // 재조판된 CTLine은 자체 범위가 0-기준 부분 복사본이라 단위 문자열 인덱스를
        // CTLine 인덱스로 옮긴다 — run 범위·밴드 범위 둘 다 그 기준이다.
        let ctRange = CTLineGetStringRange(drawn.line)
        let spanCTRange = CFRange(
            location: ctRange.location + (lower - lineRange.location), length: upper - lower
        )
        let extents = geometry.runExtents ?? Self.runExtents(of: drawn.line)
        geometry.runExtents = extents
        let top = drawn.baselineOrigin.y - drawn.ascent
        let height = drawn.ascent + drawn.descent
        for segment in visualSegments(of: extents, in: spanCTRange) {
            regions.append((
                rect: CGRect(
                    x: drawn.baselineOrigin.x + segment.lowerBound, y: top,
                    width: segment.upperBound - segment.lowerBound, height: height
                ),
                url: url
            ))
        }
        // **이 스팬에 속한 run의 밴드만** 가져간다 (#197 리뷰 4차). 밴드는 이 스팬 자신의
        // run 잉크라 구간 상자로 **자르지 않는다** — 잉크는 진행 폭 상자 밖으로 삐칠 수 있고
        // (기울임 근사의 오버행), 단방향 줄에서는 run이 늘 스팬 상자 안이라 자르나 마나 같다.
        // 양방향 줄에서 남의 잉크를 안 가져가는 것은 가로 클립이 아니라 `belongs(to:)`의
        // 몫이다 (실측 `abc אבג`에 `abc א`+`בג` 두 링크: 종전 스팬 상자 0…28.313이 뒤 스팬
        // 글자 18.903…28.313을 덮어, 뒤 링크만 10pt 올리면 올라간 잉크 위의 탭이 **앞** URL을
        // 열었다).
        for band in geometry.bands where band.belongs(to: spanCTRange) {
            let bandMinX = drawn.baselineOrigin.x + band.minX
            let bandMaxX = drawn.baselineOrigin.x + band.maxX
            guard bandMaxX > bandMinX else { continue }
            regions.append((
                rect: CGRect(
                    x: bandMinX, y: top - band.offset,
                    width: bandMaxX - bandMinX, height: height
                ),
                url: url
            ))
        }
    }
}
