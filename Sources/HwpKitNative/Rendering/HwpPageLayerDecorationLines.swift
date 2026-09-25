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
///
/// **밑줄 세 종(글자 아래·글자 위·변경 추적 삽입)은 줄 단위다** (#187·#226) — 세 갈래 모두
/// 줄마다 한 번 푼 `HwpDecorationLineGeometry.UnderlineReference`에서 자리·두께를 잰다.
/// 취소선만 run 단위다.
extension HwpPageLayer {
    /// 이 run이 한글 2007 호환 문서(표 55 대상 프로그램 1, `HWP200X`)의 것인지.
    /// 한글은 이 문서에서 장식선을 **크기와 무관한 고정 0.36pt**로 그리고 밑줄은 한글
    /// 문서와 같은 가장자리(줄 상자 바닥·상단)에 얹는다 (#210·#226). 훈민정음 호환·
    /// record 없음은 한글 문서와 같은 기하다.
    func isHwp2007Compatible(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let raw = attributes[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.hwp200X.rawValue
    }

    /// 글자 아래 밑줄(변경 추적 삽입 밑줄 포함) 한 줄의 기하. MS 워드 호환 문서는
    /// `reference.msWordLineBox`(줄 상자)에서, 한글 문서·한글 2007 호환 문서는 줄 상자
    /// 높이(`underlineLineBoxHeight`)의 바닥에서 잰다 — 한 줄의 모든 밑줄이 같은 자리다.
    func underlineBelowLine(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> HwpDecorationLineGeometry.Line {
        if let msWord = reference.msWordLineBox {
            return HwpDecorationLineGeometry.msWordUnderlineBelow(lineBox: msWord)
        }
        let lineBoxHeight = underlineLineBoxHeight(attributes, reference: reference)
        if isHwp2007Compatible(attributes) {
            return HwpDecorationLineGeometry.hwp200XUnderlineBelow(lineBoxHeight: lineBoxHeight)
        }
        return HwpDecorationLineGeometry.underlineBelow(
            lineBoxHeight: lineBoxHeight,
            thicknessFontSize: underlineThicknessFontSize(attributes, reference: reference)
        )
    }

    /// 글자 위 밑줄 한 줄의 기하 — 아래 밑줄과 같은 갈래 판정이고, 줄 상자의 상단에서 잰다.
    func underlineAboveLine(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> HwpDecorationLineGeometry.Line {
        if let msWord = reference.msWordLineBox {
            return HwpDecorationLineGeometry.msWordUnderlineAbove(lineBox: msWord)
        }
        let lineBoxHeight = underlineLineBoxHeight(attributes, reference: reference)
        if isHwp2007Compatible(attributes) {
            return HwpDecorationLineGeometry.hwp200XUnderlineAbove(lineBoxHeight: lineBoxHeight)
        }
        return HwpDecorationLineGeometry.underlineAbove(
            lineBoxHeight: lineBoxHeight,
            thicknessFontSize: underlineThicknessFontSize(attributes, reference: reference)
        )
    }

    /// 밑줄 선 모양(점선·여러 줄·물결, #191)의 축척 — 한글 문서는 두께와 같은 줄 글자 기준
    /// 크기다 (#226 실측: 40pt 무장식 글자와 한 줄인 10pt 긴 점선은 한 토막 11.40pt = 40pt
    /// 몫, 여러 줄 띠·물결 진폭도 40pt 몫; 40pt 문단 끝 글자와 한 줄이면 2.88pt = 10pt 몫).
    /// 한글 2007 호환 문서는 크기와 무관한 고정 축척이다 (#227 실측: 5~100pt 전부, 크기가 섞인
    /// 줄·상대 크기 run에서도 긴 점선 2.40/1.44pt — `HwpLineShapeGeometry.Scale.hwp200XCharacterLine`).
    /// MS 워드 호환 문서는 종전대로 첨자 축소 전 run 크기다 (그 갈래의 선 모양 축척은 실측하지
    /// 않았다). MS 워드 판정이 먼저다 — 두 호환 키는 한 문서에 함께 오지 않지만, 두께·자리를
    /// 고르는 `underlineBelowLine`과 같은 차례로 둔다.
    func underlineShapeScale(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> HwpLineShapeGeometry.Scale {
        if reference.msWordLineBox != nil {
            return .characterLine(fontSize: preScriptFontSize(attributes))
        }
        if isHwp2007Compatible(attributes) {
            return .hwp200XCharacterLine
        }
        return .characterLine(
            fontSize: underlineThicknessFontSize(attributes, reference: reference)
        )
    }

    /// 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함) 한 줄의 기하 — 밑줄과 달리 세
    /// 갈래 모두 **run 단위**다. `fontSize`는 run 글꼴 크기(첨자면 줄어든 크기)이고,
    /// 세 갈래 모두 글자 모양 기본 크기에 첨자 축소 비율만 곱한 값을 쓴다 (슬롯 상대
    /// 크기는 곱하지 않는다 — #187·#210·#226 실측: 기본 40pt·상대 크기 50% run의 취소선
    /// +14.04pt, 기본 20pt·상대 크기 50% 위 첨자는 옮겨진 베이스라인 위 0.35 × 12.8pt).
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
            fontSize: scriptSize, thicknessFontSize: baseSize
        )
    }

    /// 취소선 선 모양의 축척 — 한글 문서는 두께와 같은 run의 글자 모양 기본 크기다 (#226).
    /// 한글 2007 호환 문서는 밑줄(`underlineShapeScale`)과 같은 고정 축척이고(#227 실측: 위
    /// 첨자·상대 크기 50%·200% run의 취소선 무늬도 크기와 무관), MS 워드 호환 문서는 종전대로
    /// 첨자 축소 전 run 크기다.
    func strikethroughShapeScale(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> HwpLineShapeGeometry.Scale {
        if isMsWordCompatible(attributes) {
            return .characterLine(fontSize: preScriptFontSize(attributes))
        }
        if isHwp2007Compatible(attributes) {
            return .hwp200XCharacterLine
        }
        return .characterLine(fontSize: decorationBaseFontSize(attributes))
    }

    /// 밑줄 자리의 기준인 줄 상자 높이 — 줄에 글자 크기를 가진 것이 하나도 없으면(0) 그리는
    /// run의 기본 크기로 떨어진다.
    private func underlineLineBoxHeight(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> CGFloat {
        reference.lineBoxHeight > 0 ? reference.lineBoxHeight : decorationBaseFontSize(attributes)
    }

    /// 밑줄 두께의 기준 크기 — 줄 글자의 기본 크기 최댓값. 글자가 없는 줄(표식·마커 run만
    /// 있는 줄)이면 그리는 run의 기본 크기로 떨어진다.
    private func underlineThicknessFontSize(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> CGFloat {
        reference.textFontSize > 0 ? reference.textFontSize : decorationBaseFontSize(attributes)
    }
}
