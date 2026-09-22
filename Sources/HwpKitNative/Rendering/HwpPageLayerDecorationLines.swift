import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore

// MARK: - 장식선 기하의 문서 갈래 (한글 문서 · 한글 2007 호환 · MS 워드 호환)

/// 밑줄·취소선의 세로 자리와 두께는 문서의 대상 프로그램(표 55)마다 다르다 —
/// 어느 run이 어느 기하를 받는지를 이 한 곳에서 가른다. 값 자체는
/// `HwpDecorationLineGeometry`(HwpKitCore)에 있고, 그리기는
/// `HwpPageLayerDecorations`가 한다.
///
/// 조판은 한글 문서가 아닌 문서의 **모든** run에
/// `HwpAttributedStringKey.compatibleDocumentTarget`을 싣는다
/// (`HwpTextRunBuilder`) — 표식 run도 허용 목록으로 같은 값을 갖는다.
extension HwpPageLayer {
    /// 이 run이 한글 2007 호환 문서(표 55 대상 프로그램 1, `HWP200X`)의 것인지.
    /// 한글은 이 문서에서 장식선을 **크기와 무관한 고정 0.36pt**로 그리고 밑줄은 한글
    /// 문서와 같은 가장자리(아래 0.15em·위 0.85em)에 얹는다 (#210). 훈민정음 호환·
    /// record 없음은 한글 문서와 같은 기하다.
    func isHwp2007Compatible(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let raw = attributes[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.hwp200X.rawValue
    }

    /// 글자 아래 밑줄(변경 추적 삽입 밑줄 포함) 한 줄의 기하. `msWord`는 MS 워드 호환
    /// 문서에서 줄 전체가 공유하는 줄 상자이고 (한글 문서·한글 2007 호환 문서 줄이면
    /// nil), 한글 2007 호환 문서는 run의 **글자 모양 기본 크기**에 비례한다.
    func underlineBelowLine(
        _ attributes: [NSAttributedString.Key: Any], msWord: HwpMsWordLineBox?
    ) -> HwpDecorationLineGeometry.Line {
        if let msWord {
            return HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: msWord)
        }
        if isHwp2007Compatible(attributes) {
            return HwpDecorationLineGeometry.hwp200XUnderlineBelow(
                fontSize: decorationBaseFontSize(attributes)
            )
        }
        return HwpDecorationLineGeometry.underlineBelow(fontSize: preScriptFontSize(attributes))
    }

    /// 글자 위 밑줄 한 줄의 기하 — 아래 밑줄과 같은 갈래 판정이다.
    func underlineAboveLine(
        _ attributes: [NSAttributedString.Key: Any], msWord: HwpMsWordLineBox?
    ) -> HwpDecorationLineGeometry.Line {
        if let msWord {
            return HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: msWord)
        }
        if isHwp2007Compatible(attributes) {
            return HwpDecorationLineGeometry.hwp200XUnderlineAbove(
                fontSize: decorationBaseFontSize(attributes)
            )
        }
        return HwpDecorationLineGeometry.underlineAbove(fontSize: preScriptFontSize(attributes))
    }

    /// 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함) 한 줄의 기하 — 밑줄과 달리 세
    /// 갈래 모두 **run 단위**다. `fontSize`는 run 글꼴 크기(첨자면 줄어든 크기)이고,
    /// 호환 문서 두 갈래는 글자 모양 기본 크기에 첨자 축소 비율만 곱한 값을 쓴다
    /// (슬롯 상대 크기는 곱하지 않는다 — #187·#210 실측).
    func strikethroughLine(
        _ attributes: [NSAttributedString.Key: Any], msWordFont: CTFont?, fontSize size: CGFloat
    ) -> HwpDecorationLineGeometry.Line {
        let preScriptSize = preScriptFontSize(attributes)
        let baseSize = decorationBaseFontSize(attributes)
        let scriptSize = baseSize * size / max(preScriptSize, 0.01)
        if let msWordFont {
            // 첨자 축소 비율(run 글꼴 크기 ÷ 축소 전 크기)은 유지한다 — 한글 문서처럼
            // 첨자 취소선은 줄어든 글리프 가운데를 지난다 (#179; 호환 문서 첨자 표본은
            // MS 워드 갈래엔 없고 한글 2007 갈래는 실측했다).
            return HwpDecorationLineGeometry.msWordStrikethrough(
                runBox: HwpMsWordLineBox.metrics(of: msWordFont).scaled(by: scriptSize),
                thicknessFontSize: baseSize
            )
        }
        if isHwp2007Compatible(attributes) {
            // 실측(2026-09-22): 기본 40pt 위 첨자 run(글리프 25.56pt)의 취소선이 첨자로
            // 옮겨진 베이스라인 위 8.88pt = 0.35 × 25.56이다.
            return HwpDecorationLineGeometry.hwp200XStrikethrough(fontSize: scriptSize)
        }
        return HwpDecorationLineGeometry.strikethrough(
            fontSize: size, thicknessFontSize: preScriptSize
        )
    }
}
