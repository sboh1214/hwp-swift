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
    ///
    /// MS 워드 호환 문서는 **줄 글자 상자의 높이**(`HwpMsWordLineBox.cellHeight` × 1.3 — 줄의 글자
    /// run 상자들을 합친 줄 상자)다 (#244). 한글은 그 문서의 밑줄 무늬를 글자 크기가 아니라 그 줄의
    /// 글꼴 줄 상자로 잰다 — 한글 12.30 PDF 실측(2026-09-30): 글꼴 10종 × 8~100pt 원형 점선 아래·위
    /// 밑줄 732표본(문단 끝 글자·개체가 쌓이지 않은 줄)의 간격·경로 지름이 전부 한글 줄 캐시
    /// `vertsize`를 크기로 넣은 #239 장치 단위 규칙과 같다 (함초롬바탕 10pt 1692 → 간격 20u,
    /// HY울릉도M 10pt 1301 → 15u, Times New Roman
    /// 10pt 1152 → 15u, 함초롬바탕 80pt 13531 → 163u). 크기가 섞인 줄은 가장 큰 글자 run의 상자이고
    /// (함초롬바탕 10pt 밑줄 + 40pt 무장식 글자 → 40pt 상자 몫 80u, HY울릉도M 40pt 무장식 → 63u),
    /// **문단 끝 글자·글자처럼 취급 개체는 줄 상자를 키워도 이 크기에 들지 않는다** (40pt 문단 끝
    /// 글자·30pt 표와 한 줄인 10pt 밑줄은 20u) — 그래서 쌓인 줄 상자(`lineHeight`)가 아니라 글자
    /// 상자의 `cellHeight`에서 푼다. 크기는 글자 모양 기본 크기로 잰 상자다 (상대 크기 50%·200%,
    /// 위·아래 첨자 run 모두 기본 크기 상자 몫). 대시·여러 줄·물결도 같은 크기다 (40pt 함초롬바탕
    /// 긴 점선 161/96u — 상자 67.66pt의 무늬 두께 264HWPUNIT, #245). 우리 상자는 한글 줄 캐시의 반올림
    /// (글꼴마다 ±0.1%)을 재현하지 않아 732표본 중 10개가 점 단위 1u 작아 원 간격이 2~3u 좁다
    /// (`Sources/HwpKitCore/AGENTS.md`의 남은 격차). MS 워드 판정이 먼저다 — 두 호환 키는 한
    /// 문서에 함께 오지 않지만, 두께·자리를 고르는 `underlineBelowLine`과 같은 차례로 둔다.
    func underlineShapeScale(
        _ attributes: [NSAttributedString.Key: Any],
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> HwpLineShapeGeometry.Scale {
        if let msWord = reference.msWordLineBox {
            return .characterLine(
                fontSize: msWord.cellHeight * HwpRenderTuning.Text.msWordLineHeightCellRatio
            )
        }
        if isHwp2007Compatible(attributes) {
            return .hwp200XCharacterLine
        }
        return .characterLine(
            fontSize: underlineThicknessFontSize(attributes, reference: reference)
        )
    }

    /// 밑줄 선 모양의 여러 줄 띠·물결 자리 — 한글 문서·한글 2007 호환 문서는 밑줄 종류대로
    /// (글자 아래 밑줄은 단선 위 가장자리에서 아래로, 글자 위 밑줄은 아래 가장자리에서 위로
    /// 자란다), MS 워드 호환 문서는 두 밑줄 모두 **취소선처럼 단선 중심에 가운데 맞춘다** (#244).
    /// 한글 12.30 PDF 실측(2026-09-30, 글꼴 5종 × 10·20·40·80pt): 2중선·가는+굵은·굵은+가는·
    /// 3중선 밑줄의 띠가 실선 밑줄 중심을 가운데로 두고(함초롬바탕 40pt 2중선 −3.84~+3.84pt), 물결의
    /// 위 꼭짓점이 중심에서 계단 둘(2.5 × 0.04 × 축척) 위다(같은 크기 −6.74pt, 취소선 계단). 아래·
    /// 위 밑줄이 같은 무늬다. 원형 점선·대시는 가운데 띠라 자리가 같다.
    func underlineShapePlacement(
        _ placement: HwpLineShapeGeometry.Placement,
        reference: HwpDecorationLineGeometry.UnderlineReference
    ) -> HwpLineShapeGeometry.Placement {
        reference.msWordLineBox != nil ? .strikethrough : placement
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

    /// 취소선 선 모양의 축척 — 한글 문서와 MS 워드 호환 문서는 두께와 같은 run의 글자 모양 기본
    /// 크기다 (#226·#244). 한글 2007 호환 문서는 밑줄(`underlineShapeScale`)과 같은 고정 축척이다
    /// (#227 실측: 위 첨자·상대 크기 50%·200% run의 취소선 무늬도 크기와 무관).
    ///
    /// MS 워드 호환 문서의 취소선은 밑줄과 달리 글꼴 상자가 아니라 글자 크기를 따른다 — #239·#244
    /// 실측: 글꼴 10종 × 8~100pt 원형 점선 취소선 180표본이 전부 글자 크기의 장치 단위 규칙과 같다
    /// (함초롬바탕·HY울릉도M·Times New Roman 10pt 모두 간격 13u). 그 크기는 run 글꼴 크기가 아니라
    /// **글자 모양 기본 크기**다 (2026-09-30 실측: 기본 20pt·상대 크기 50% run의 원형 점선 간격 25u·
    /// 긴 점선 47/28u = 20pt 몫, 기본 10pt·200% run은 13u = 10pt 몫, 기본 20pt 위·아래 첨자 run도 25u
    /// = 축소 전 20pt 몫) — 종전의 첨자 축소 전 run 크기(`preScriptFontSize`)는 슬롯 상대 크기를
    /// 곱해 상대 크기 run에서 갈렸다.
    func strikethroughShapeScale(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> HwpLineShapeGeometry.Scale {
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
