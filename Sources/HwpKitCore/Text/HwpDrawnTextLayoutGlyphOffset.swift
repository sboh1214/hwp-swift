import CoreGraphics
import CoreText
import Foundation

// 글자 위치(표 33)로 옮겨진 글리프와 **기하 질의** (#197 리뷰).
//
// 조판 문자열은 `kCTBaselineOffset`을 싣지 않으므로(한글처럼 줄 상자를 안 키우려고)
// CT가 대신 rect를 부풀려 주지 않는다 — 옮겨진 잉크를 덮어야 하는 쪽이 직접 걷는다.

public extension HwpDrawnLine {
    /// 잉크가 실제로 닿는 범위 — 줄 상자(`selectionRect`) **+ 옮겨진 run마다 그 run의
    /// 가로 범위만** 가진 밴드 (top-down 페이지 좌표).
    ///
    /// "이 지점에 글자가 칠해졌는가"(claim)와 "링크를 눌렀는가"(히트)는 **옮겨진
    /// 글리프**를 따라야 한다 — 안 그러면 보이는 글자를 눌러도 링크가 안 열린다
    /// (실측: Helvetica 10pt 링크에 글자 위치 30이면 잉크 하단 3.000pt가 줄 상자 밖이라
    /// 하단 클릭이 `.text`로 떨어지고, 위치 100에서는 겹침이 0%가 된다).
    ///
    /// **하나의 rect로 합치지 않는다** (#197 리뷰 2차): 줄 전체 폭에 최대 오프셋을 걸면
    /// 안 옮겨진 run 아래의 **빈 공간까지 칠한 것으로 claim**해, 그 자리의 탭이 뒤 층의
    /// 보이는 링크를 막는다 ('ABBBBBBBBBB'에서 A만 10pt 내리면 B 아래 빈 띠가 그렇다).
    /// claim은 정밀 커버리지여야 한다는 규약(R54) 그대로다.
    var paintedRects: [CGRect] {
        paintedRects(bands: HwpDrawnTextLayout.glyphOffsetBands(of: line))
    }
}

extension HwpDrawnLine {
    /// 밴드를 이미 걷어 둔 호출자용 (`HwpDrawnTextLayout.glyphOffsetBands(ofLines:in:)`).
    func paintedRects(bands: [HwpDrawnTextLayout.GlyphOffsetBand]) -> [CGRect] {
        let box = selectionRect
        var rects = [box]
        for band in bands {
            let x = baselineOrigin.x + band.minX
            let width = band.maxX - band.minX
            guard width > 0 else { continue }
            rects.append(CGRect(
                x: x, y: box.minY - band.offset, width: width, height: box.height
            ))
        }
        return rects
    }
}

extension HwpDrawnTextLayout {
    /// 옮겨진 run 하나의 가로 범위(줄 원점 기준)와 그 오프셋.
    struct GlyphOffsetBand {
        let minX: CGFloat
        let maxX: CGFloat
        /// 렌더러 규약 그대로 **양수 = 위**.
        let offset: CGFloat
    }

    /// 줄별 밴드 — 링크 스팬·줄마다 다시 걷지 않게 호출자가 한 번만 받아 나눠 쓴다.
    ///
    /// 글자 위치 run이 **하나도 없는** 문단(대다수)은 CTRun 전수 순회 자체를 건너뛴다:
    /// `CTRunGetAttributes`는 run마다 CFDictionary를 브리징해 오프셋이 없어도 값을
    /// 치른다. 속성 run 한 번 훑기가 훨씬 싸다.
    static func glyphOffsetBands(
        ofLines drawnLines: [HwpDrawnLine], in attributedString: NSAttributedString
    ) -> [[GlyphOffsetBand]] {
        guard carriesGlyphOffset(attributedString) else {
            return Array(repeating: [], count: drawnLines.count)
        }
        return drawnLines.map { glyphOffsetBands(of: $0.line) }
    }

    /// 조판 문자열에 0이 아닌 글자 위치 run이 하나라도 있는가.
    private static func carriesGlyphOffset(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.glyphBaselineOffset,
            in: NSRange(location: 0, length: attributedString.length),
            options: .longestEffectiveRangeNotRequired
        ) { value, _, stop in
            guard let offset = (value as? NSNumber)?.doubleValue, offset != 0 else { return }
            found = true
            stop.pointee = true
        }
        return found
    }

    /// 옮겨진 run마다 (줄 원점 기준 가로 범위, 오프셋) — 정밀 커버리지용.
    ///
    /// 가로 범위는 **글리프 위치에서** 낸다: `CTRunGetStringRange` → 문자열 인덱스로
    /// 되짚으면 재조판된 부분 복사본에서 범위가 어긋나고, RTL 줄은 논리 순서와 x 순서가
    /// 반대라 시작·끝을 뒤집는다. 위치의 최소·최대에 run 폭을 더해 **상위집합**으로 낸다.
    static func glyphOffsetBands(of line: CTLine) -> [GlyphOffsetBand] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var bands: [GlyphOffsetBand] = []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            guard let offset =
                (attributes?[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber)?.doubleValue,
                offset != 0
            else { continue }
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            guard let minX = positions.map(\.x).min(), let maxX = positions.map(\.x).max()
            else { continue }
            // 마지막 글리프의 폭은 위치에 안 들어 있다 — run 폭을 더해 오른쪽 끝을 덮는다.
            let width = CGFloat(CTRunGetTypographicBounds(
                run, CFRange(location: 0, length: 0), nil, nil, nil
            ))
            bands.append(GlyphOffsetBand(
                minX: minX, maxX: max(maxX, minX + width), offset: CGFloat(offset)
            ))
        }
        return bands
    }
}
