import CoreGraphics
import CoreText
import Foundation

// 글자 위치(표 33)로 옮겨진 글리프와 **기하 질의** (#197 리뷰).
//
// 조판 문자열은 `kCTBaselineOffset`을 싣지 않으므로(한글처럼 줄 상자를 안 키우려고)
// CT가 대신 rect를 부풀려 주지 않는다 — 옮겨진 잉크를 덮어야 하는 쪽이 직접 걷는다.

public extension HwpDrawnLine {
    /// 잉크가 실제로 닿는 범위 — 줄 상자(`selectionRect`) **∪** 글자 위치로 옮겨진
    /// 글리프 밴드 (top-down 페이지 좌표).
    ///
    /// "이 지점에 글자가 칠해졌는가"(claim)와 "링크를 눌렀는가"(히트)는 **옮겨진
    /// 글리프**를 따라야 한다 — 안 그러면 보이는 글자를 눌러도 링크가 안 열린다
    /// (실측: Helvetica 10pt 링크에 글자 위치 30이면 잉크 하단 3.000pt가 줄 상자 밖이라
    /// 하단 클릭이 `.text`로 떨어지고, 위치 100에서는 겹침이 0%가 된다).
    ///
    /// **평행이동이 아니라 합집합**이다: 한 줄에 오프셋이 다른 run이 섞이므로 밴드를
    /// 통째로 옮기면 오프셋 없는 이웃 run의 잉크가 오히려 밖으로 나간다.
    var paintedRect: CGRect {
        let offsets = HwpDrawnTextLayout.glyphOffsetBounds(of: line)
        guard offsets.above > 0 || offsets.below > 0 else { return selectionRect }
        var rect = selectionRect
        rect.origin.y -= offsets.above
        rect.size.height += offsets.above + offsets.below
        return rect
    }
}

extension HwpDrawnTextLayout {
    /// 글자 위치(`hwp.glyphBaselineOffset`, 양수 = 위)가 그 범위에서 글리프를 밀어낸
    /// 최대 몫 — 위·아래를 따로 낸다. 없으면 둘 다 0이다.
    ///
    /// 줄 상자를 **넓히는** 데만 쓴다 (`paintedRect`·`hyperlinkRegions`). 줄 상자 자체는
    /// 한글이 글자 위치로 키우지 않으므로 그대로 둔다 (`HwpTextRunBuilder`의 실측).
    static func glyphOffsetBounds(
        in attributedString: NSAttributedString, range: NSRange
    ) -> (above: CGFloat, below: CGFloat) {
        var above: CGFloat = 0
        var below: CGFloat = 0
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.glyphBaselineOffset, in: range
        ) { value, _, _ in
            guard let offset = (value as? NSNumber)?.doubleValue, offset != 0 else { return }
            above = max(above, CGFloat(offset))
            below = max(below, CGFloat(-offset))
        }
        return (above, below)
    }

    /// 같은 값을 CTLine의 run 속성에서 직접 걷는다 — 원본 문자열이 없는 자리
    /// (`HwpDrawnLine.paintedRect`)용이고, 재조판된 부분 복사본에서도 그 줄이 실제로
    /// 그리는 run만 본다.
    static func glyphOffsetBounds(of line: CTLine) -> (above: CGFloat, below: CGFloat) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return (0, 0) }
        var above: CGFloat = 0
        var below: CGFloat = 0
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            guard let offset =
                (attributes?[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber)?.doubleValue,
                offset != 0
            else { continue }
            above = max(above, CGFloat(offset))
            below = max(below, CGFloat(-offset))
        }
        return (above, below)
    }
}
