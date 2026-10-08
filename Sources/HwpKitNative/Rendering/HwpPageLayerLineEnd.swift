import CoreGraphics
import CoreText
import Foundation
import HwpKitCore

// MARK: - 줄 끝 글자의 장식 끝 (#260)

extension HwpPageLayer {
    /// 줄 끝 글자의 장식 끝 (#260) — 없으면 nil.
    ///
    /// 한글은 줄의 마지막 글자에 자간을 주지 않는다(`HwpLetterSpacing.lineEnd`). CoreText의 run 경계는
    /// 그 글자의 자간을 품으므로, run 경계로 재는 음영·실선·선 모양 span·메모 괄호가 양수 자간이면 그
    /// 몫만큼 글자 뒤로(오른쪽 정렬 줄은 여백 밖으로) 뻗고 음수 자간이면 그만큼 모자라 오른쪽 정렬·양쪽
    /// 정렬 줄에서 여백 앞에서 끊긴다 — 조판은 그 글자의 자간 없는 전진량을 줄 끝에 맞췄다
    /// (`HwpLineBreaker.lineEndSpacingAligned`·`HwpWordJustification`). 그래서 마지막 글자 run의
    /// 장식 끝을 그 전진량 끝으로 옮긴다(`LineEndEdge`).
    ///
    /// 자간은 속성 값이 아니라 **CoreText가 실제로 준 몫**으로 잰다 — 마지막 글리프의 run 진행 폭에서
    /// 글꼴의 진행 폭을 뺀다(장평 글꼴도 둘 다 행렬 적용 뒤 값이다, 실측). 문단이 CoreText 자간 상한
    /// (`HwpLetterSpacing.coreTextSpacingLengthLimit`)보다 길면 자간이 적용되지 않아 0이다. 줄이 공백
    /// 없이 그 글자로 끝날 때만 옮긴다 — 폭 0 run(문단·줄 끝 표식, 필드 끝·책갈피 같은 컨트롤 표식)
    /// 뒤의 시각상·논리상 마지막 run이 자간 표식(`hwp.letterSpacing`)을 지니고, 줄 끝 공백 폭이 0이거나
    /// (음수, 또는 컨트롤 표식에 막혀 매달리지 않은 양수) 그 자간과 같을(매달린 양수) 때다. 뒤에
    /// 빈칸이 오는 줄은 빈칸 밑 선까지 옮기게 되므로 그대로 둔다.
    func lineEndDecorationEdge(
        of line: CTLine, runs: [CTRun], attributes: [[NSAttributedString.Key: Any]],
        lineOrigin: CGPoint
    ) -> LineEndEdge? {
        // 줄마다 불리므로 run 폭은 끝에서부터 필요한 만큼만 잰다.
        let whole = CFRange(location: 0, length: 0)
        func isVisible(_ run: CTRun) -> Bool {
            CTRunGetTypographicBounds(run, whole, nil, nil, nil) > 0
        }
        guard let lastIndex = runs.lastIndex(where: isVisible) else { return nil }
        let last = runs[lastIndex]
        let count = CTRunGetGlyphCount(last)
        guard count > 0, !CTRunGetStatus(last).contains(.rightToLeft),
              attributes[lastIndex][HwpAttributedStringKey.letterSpacing] != nil,
              let font = runFont(attributes[lastIndex])
        else { return nil }
        var glyph = CGGlyph()
        var advance = CGSize.zero
        var nominal = CGSize.zero
        CTRunGetGlyphs(last, CFRange(location: count - 1, length: 1), &glyph)
        CTRunGetAdvances(last, CFRange(location: count - 1, length: 1), &advance)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &nominal, 1)
        let spacing = advance.width - nominal.width
        let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        guard abs(spacing) > 0.001, trailing < 0.01 || abs(spacing - trailing) < 0.01
        else { return nil }
        // 시각상 마지막 run이 논리상으로도 마지막 보이는 run이어야 한다 (양방향 줄).
        let location = CTRunGetStringRange(last).location
        guard !runs.contains(where: {
            CTRunGetStringRange($0).location > location && isVisible($0)
        }) else { return nil }
        let runMaxX = runBounds(of: last, lineOrigin: lineOrigin).maxX
        return LineEndEdge(runMaxX: runMaxX, edge: runMaxX - spacing)
    }
}

/// 줄 끝 글자의 장식 끝 (#260, `HwpPageLayer.lineEndDecorationEdge`) — 한글은 줄의 마지막 글자에
/// 자간을 주지 않으므로 그 글자의 음영·선은 자간 없는 전진량에서 끝난다. CoreText의 run 경계는
/// 그 글자의 자간을 품고 있어(양수면 그만큼 뒤로, 음수면 그만큼 앞에서 끝난다) 경계가 그 run의
/// 끝(`runMaxX`)과 같은 장식만 `edge`로 옮긴다 — 앞 run의 장식은 그대로다.
struct LineEndEdge: Equatable {
    /// 마지막 글자 run의 경계 끝 (자간이 실린 진행 폭).
    let runMaxX: CGFloat
    /// 장식이 끝나야 할 자리 (마지막 글자의 자간 없는 전진량 끝).
    let edge: CGFloat

    /// `rect`의 오른쪽 끝이 마지막 글자 run의 끝이면 `edge`로 옮긴다 (자르거나 늘린다).
    func adjust(_ rect: inout CGRect) {
        guard abs(rect.maxX - runMaxX) < 0.01 else { return }
        rect.size.width = max(0, edge - rect.minX)
    }
}
