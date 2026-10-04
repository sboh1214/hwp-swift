import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 장치 단위 무늬 — 대시·획 두께 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// 대시(긴 점선·점선·일점쇄선·이점쇄선·긴 파선)의 선·공백 길이와 표 셀 테두리·단 구분선의 획 두께.
/// 한글은 이 길이를 600dpi 장치 단위(u = 0.12pt)의 정수로 먼저 정한 뒤 되풀이한다 (#245) — 무늬
/// 두께 t(HWPUNIT, `patternHwpUnits(for:)`)에서 단위 b = t × 22/15 ÷ 12(u)를 두고:
///
/// - 점 q = round(b) (최소 1u), 긴 선 L = round(10b) (최소 10u), 공백 G = 2·round(1.5b) (최소 2u).
/// - **점 무늬**(한글 문서·MS 워드 호환 문서의 글자선, 셀 간격이 있는 표의 셀 테두리, 단 구분선):
///   점선 [q, round(1.5q)] (공백 최소 4u), 긴 점선 [⌊L/2⌋, G], 긴 파선 [L, G], 일점쇄선
///   [L, G, q, G], 이점쇄선 [L, G, q, G, q, G].
/// - **격자**(셀 간격이 없는 표의 셀 테두리): 점선 [q, ⌊1.5q⌋], 긴 점선 [⌈L/2⌉, 3q − (L mod 2)],
///   긴 파선 [L, 3q], 일점쇄선 [L, 3q, q, 3q], 이점쇄선 [L, 3q, q, 3q, q, 3q].
///
/// 갈래는 원형 점선과 같다 (`usesCellGrid(_:)`, #239·#243). 반올림은 0.5를 올린다. 실측은 한글 12.30
/// PDF (2026-10-01 `probes/245`): 한글 문서 취소선 대시 5종 × 무늬 두께 4~390 991표본·아래 밑줄 90표본,
/// MS 워드 호환 문서 취소선 580표본, 표 셀 테두리 대시 5종 × 표 26 굵기 16단 × 셀 간격 0·283HWPUNIT
/// 가로·세로 변 317표본, 단 구분선 68표본이 모두 이 식과 요소마다 같다 (종전 비례 무늬는 1mm 점선
/// 주기 86.61u — 한글 87·88u — 라 긴 선에서 대시가 한 주기마다 밀렸다). 표 셀 테두리·단 구분선의
/// 실선·대시 획 두께도 round(t ÷ 12)u다 (16단 모두, `strokeThickness(for:)`). 글자선(한글 문서·MS 워드
/// 호환 문서의 밑줄·취소선)의 실선·대시 획도 같은 식에 글자선의 t를 넣은 값이고 최소 1u다 (#252 —
/// `characterStrokeThickness(fontSize:)`). 한글 2007 호환 문서는 고정 단위 0.48pt(= 4u, 위 식에 b = 4를
/// 넣은 값과 같다)·고정 획 0.36pt라 이 모델 밖이다 (#210·#227).
extension HwpLineShapeGeometry {
    /// 장치 단위로 반올림하는 입력의 상한 (pt) — 무늬 두께(`patternThickness(for:)`)가 이보다 크면
    /// 장치 단위 반올림이 뜻이 없으므로 반올림 전 비율로 셈한다. 이 아래에서는 반올림하는 HWPUNIT·장치
    /// 단위 값이 2^52보다 작아 0.5 올림(`roundHalfUp`)이 정확하고 곱이 넘치지 않는다 (두 갈래의 차는
    /// 경계에서 상대 1e-13 안이다) — 다만 글자선의 무늬 두께는 글자 크기(HWPUNIT) × 39를 거치므로 글자
    /// 크기 약 2.3e12pt부터는 그 곱이 2^53을 넘어 동점 근처에서 1 갈릴 수 있다 (실제 글자 크기와는 먼
    /// 자리다). 원형 점선(`circleDeviceGeometry(for:)`)도 같은 상한이다.
    static let deviceRoundingLimit: CGFloat = 1e12

    /// 대시 무늬 (선, 공백, 선, 공백 … 순, pt) — 무늬가 없는 모양은 빈 배열. 한글 문서·MS 워드 호환
    /// 문서의 글자선과 테두리·단 구분선은 장치 단위 정수(`dashDeviceUnits(for:hwpUnits:grid:)`),
    /// 한글 2007 호환 문서는 고정 단위(`hwp200XDashUnit`)의 배수다. 무늬 두께가 상한
    /// (`deviceRoundingLimit`) 밖이면 반올림 전 단위(두께 × 22/15)의 배수다.
    static func dashPattern(for line: Line) -> [CGFloat] {
        typealias Shape = HwpRenderTuning.LineShape
        let multiples = dashMultiples(for: line.shape)
        guard !multiples.isEmpty else { return [] }
        if line.scale == .hwp200XCharacterLine {
            return multiples.map { $0 * Shape.hwp200XDashUnit }
        }
        let thickness = patternThickness(for: line)
        guard thickness < deviceRoundingLimit else {
            // 나눗셈 먼저 — 곱이 먼저 넘치지 않게. 두께가 유한 최댓값의 15/22를 넘으면 단위가
            // 무한대가 되지만 경로는 첫 대시 하나(길이 전체)로 유한하다
            let unit = thickness / Shape.patternUnitThicknessDenominator
                * Shape.patternUnitThicknessNumerator
            return multiples.map { $0 * unit }
        }
        return dashDeviceUnits(
            for: line.shape, hwpUnits: patternHwpUnits(for: line), grid: usesCellGrid(line)
        ).map { $0 * Shape.deviceUnit }
    }

    /// 대시 무늬의 요소 길이 (장치 단위 정수, 선·공백 차례) — 무늬 두께 `hwpUnits`(HWPUNIT 정수)에서
    /// 타입 설명의 식으로 푼다. `grid`는 셀 간격이 없는 표의 셀 테두리 갈래다. b의 배수 m × b는
    /// 정수 두께 × (22m)를 정수 180(= 15 × 12)으로 한 번 나눠 0.5u 동점을 정확히 가른다 — 22/15를 이진
    /// 소수로 곱하면 무늬 두께 315(b = 38.5u)·330(1.5b = 60.5u)…에서 동점이 아래로 내려간다(한글은
    /// 올린다, #239의 원형 점선과 같은 함정).
    static func dashDeviceUnits(
        for shape: HwpBorderType, hwpUnits: CGFloat, grid: Bool
    ) -> [CGFloat] {
        typealias Shape = HwpRenderTuning.LineShape
        let denominator = Shape.patternUnitThicknessDenominator * hwpUnitsPerDeviceUnit
        func units(_ multiple: CGFloat) -> CGFloat {
            roundHalfUp(hwpUnits * (Shape.patternUnitThicknessNumerator * multiple) / denominator)
        }
        let dot = max(units(1), Shape.dashMinimumDotDeviceUnits)
        let long = max(units(10), Shape.dashMinimumLongDeviceUnits)
        let longIsOdd = long.truncatingRemainder(dividingBy: 2) != 0
        let dotGap: CGFloat
        let gap: CGFloat
        let half: CGFloat
        let halfGap: CGFloat
        if grid {
            dotGap = (dot * 1.5).rounded(.down)
            gap = dot * 3
            half = (long / 2).rounded(.up)
            halfGap = gap - (longIsOdd ? 1 : 0)
        } else {
            dotGap = max(roundHalfUp(dot * 1.5), Shape.dashMinimumDotGapDeviceUnits)
            gap = max(units(1.5) * 2, Shape.dashMinimumLongGapDeviceUnits)
            half = (long / 2).rounded(.down)
            halfGap = gap
        }
        return switch shape {
        case .dotLine: [dot, dotGap]
        case .longDotLine: [half, halfGap]
        case .longDash: [long, gap]
        case .dashDot: [long, gap, dot, gap]
        case .dashDotDot: [long, gap, dot, gap, dot, gap]
        default: []
        }
    }

    /// 대시·원형 점선이 셀 간격이 없는 표 셀 테두리의 **격자** 갈래인가 — 테두리 축척에서 단 구분선이
    /// 아니고 셀 간격이 있는 표(`Line.inSpacedTable`)의 테두리도 아닌 자리. 단 구분선·셀 간격이 있는
    /// 표의 셀 테두리와 글자선은 점 무늬 갈래다 (원: 한글은 같은 두께의 원을 셀 간격이 없는 표의 셀
    /// 테두리보다 크고 성기게 그린다 — 1mm 간격 88u vs 48u, #239·#243; 대시: 1mm 점선 주기 88u vs
    /// 87u, #245).
    static func usesCellGrid(_ line: Line) -> Bool {
        guard line.scale == .border, !line.inSpacedTable else { return false }
        switch line.placement {
        case .divider:
            return false
        case .border, .underlineBelow, .strikethrough, .underlineAbove:
            return true
        }
    }

    /// 무늬 두께 (pt) — 글자선은 글자 크기 × 0.039, 그 밖은 단선 두께. 장치 단위 반올림의 상한
    /// (`deviceRoundingLimit`)과 상한 밖 비례 무늬가 이 값을 본다. 나눗셈 먼저 — 글자 크기가 유한
    /// 최댓값 근처여도 넘치지 않게.
    static func patternThickness(for line: Line) -> CGFloat {
        if case let .characterLine(fontSize) = line.scale {
            return fontSize / 1000 * HwpRenderTuning.LineShape.characterPatternThicknessPerMille
        }
        return line.thickness
    }

    /// 무늬 두께 (HWPUNIT 정수) — 글자선은 글자 크기를 HWPUNIT으로 둔 뒤 × 39/1000을 반올림
    /// (`characterPatternThicknessPerMille`), 테두리·단 구분선은 `borderPatternHwpUnits(thickness:)`.
    /// 대시와 원형 점선이 함께 쓴다. 상한(`deviceRoundingLimit`) 안의 입력에서만 부른다.
    static func patternHwpUnits(for line: Line) -> CGFloat {
        if case let .characterLine(fontSize) = line.scale {
            return characterPatternHwpUnits(fontSize: fontSize)
        }
        return borderPatternHwpUnits(thickness: line.thickness)
    }

    /// 글자선의 무늬 두께 (HWPUNIT 정수) — 기준 크기 `fontSize`(pt)를 HWPUNIT 정수로 둔 X에서
    /// round(X × 39/1000). 대시·원형 점선의 무늬와 실선·대시의 획 두께(`characterStrokeThickness(fontSize:)`)가
    /// 이 값에서 나온다. 상한(`deviceRoundingLimit`) 안의 입력에서만 부른다.
    static func characterPatternHwpUnits(fontSize: CGFloat) -> CGFloat {
        roundHalfUp(
            (fontSize * 100).rounded()
                * HwpRenderTuning.LineShape.characterPatternThicknessPerMille / 1000
        )
    }

    /// 테두리·단 구분선 두께의 무늬 두께 (HWPUNIT) — 표 26 굵기(`HwpBorderFill.borderThicknessPoints`)
    /// 면 한글이 쓰는 값(`HwpRenderTuning.LineShape.borderPatternHwpUnits` — 여덟 굵기에서 반올림보다
    /// 1 작다), 그 밖의 두께(테두리 정보가 없는 표의 0.5pt 등)는 HWPUNIT으로 반올림한 값이다.
    static func borderPatternHwpUnits(thickness: CGFloat) -> CGFloat {
        let table = HwpRenderTuning.LineShape.borderPatternHwpUnits
        let count = min(table.count, CoreHwp.HwpBorderFill.borderThicknessMillimeters.count)
        for index in 0 ..< count {
            let points = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: UInt8(index)))
            if abs(thickness - points) <= points * 1e-9 {
                return table[index]
            }
        }
        return roundHalfUp(thickness * 100)
    }

    /// 실선·대시의 획 두께 (pt) — 테두리 축척(표 셀 테두리·단 구분선)은 한글처럼 무늬 두께를 장치
    /// 단위로 반올림한 값(최소 1u — 표 26 16단: 2·3·4·5·6·7·9·12·14·17·24·35·47·71·95·118u, #245
    /// 실측: 가로·세로 변·단 구분선 모두; 0.4mm 1.134 → 1.08pt, 1mm 2.835 → 2.88pt), 글자선은 단선
    /// 두께 그대로다 — 글자선의 단선 두께는 이미 같은 규칙으로 반올림한 값이다
    /// (`HwpDecorationLineGeometry`가 `characterStrokeThickness(fontSize:)`로 낸다, #252). 그래서 실선을
    /// 채우는 렌더러(`Line.thickness`를 그대로 쓴다)와 대시 띠가 같은 두께다. 테두리·단 구분선의 여러 줄·
    /// 물결은 이 획(장치 단위 수 `borderStrokeUnits(_:)`)을 띠로 삼아 부속선과 물결을 나눈다 (#253 —
    /// `HwpLineShapeGeometry+DeviceBands.swift`). 원형 점선은 제 장치 단위 규칙이 있다
    /// (`circleDeviceGeometry(for:)`). 상한(`deviceRoundingLimit`) 밖 두께는 그대로다.
    static func strokeThickness(for line: Line) -> CGFloat {
        line.scale == .border ? borderStrokeThickness(line.thickness) : line.thickness
    }

    /// 테두리·단 구분선 두께(pt)의 획 두께 — 무늬 두께(`borderPatternHwpUnits(thickness:)`)를 장치
    /// 단위로 반올림한 값(최소 1u). 0 이하·유한하지 않은 두께와 상한(`deviceRoundingLimit`) 밖 두께는
    /// 그대로다. 모서리에서 선이 나가거나 물러나는 길이도 이웃 변의 이 값의 절반이다
    /// (`HwpBorderSet.reachWidth`).
    static func borderStrokeThickness(_ thickness: CGFloat) -> CGFloat {
        guard thickness > 0, thickness < deviceRoundingLimit else { return thickness }
        return borderStrokeUnits(thickness) * HwpRenderTuning.LineShape.deviceUnit
    }

    /// 테두리·단 구분선 두께(pt)의 획 두께를 장치 단위 수로 — B = max(1, round(t ÷ 12)) (t = 무늬 두께
    /// `borderPatternHwpUnits(thickness:)`; 표 26 16단 2·3·4·5·6·7·9·12·14·17·24·35·47·71·95·118).
    /// 여러 줄·물결의 장치 띠도 이 값이다 (#253, `borderBand(for:)`). 양수이고 상한(`deviceRoundingLimit`)
    /// 안인 두께에서만 부른다.
    static func borderStrokeUnits(_ thickness: CGFloat) -> CGFloat {
        max(1, roundHalfUp(borderPatternHwpUnits(thickness: thickness) / hwpUnitsPerDeviceUnit))
    }

    /// 글자선(한글 문서·MS 워드 호환 문서의 밑줄·취소선)의 실선·대시 획 두께 (pt) — 기준 크기
    /// `fontSize`(pt)의 무늬 두께 t = round(X × 39/1000)(`characterPatternHwpUnits(fontSize:)`, X = 기준
    /// 크기 HWPUNIT 정수)를 장치 단위로 반올림한 값, 최소 1u다 (#252). 테두리·단 구분선의 획
    /// (`borderStrokeThickness(_:)`)과 같은 식에 무늬 두께만 글자선의 것을 넣는다. 기준 크기는 무늬와
    /// 같다 — `Scale.characterLine`의 `fontSize`. 0 이하·NaN이면 0(선 없음), 무늬 두께가 상한
    /// (`deviceRoundingLimit`) 밖이면 반올림 전 무늬 두께(글자 크기 × 0.039)다.
    static func characterStrokeThickness(fontSize: CGFloat) -> CGFloat {
        guard fontSize > 0 else { return 0 }
        // 나눗셈 먼저 — 글자 크기가 유한 최댓값 근처여도 넘치지 않게 (`patternThickness(for:)`와 같다)
        let pattern = fontSize / 1000 * HwpRenderTuning.LineShape.characterPatternThicknessPerMille
        guard pattern < deviceRoundingLimit else { return pattern }
        return deviceStrokeThickness(hwpUnits: characterPatternHwpUnits(fontSize: fontSize))
    }

    /// 무늬 두께(HWPUNIT 정수)의 획 두께 (pt) — round(t ÷ 12)u, 최소 1u. 한글은 무늬 두께가 6HWPUNIT
    /// 미만(글자선은 기준 크기 1.41pt 이하, 무늬 두께 0~5)이어도 1u 획을 긋는다 (#252 실측).
    static func deviceStrokeThickness(hwpUnits: CGFloat) -> CGFloat {
        max(1, roundHalfUp(hwpUnits / hwpUnitsPerDeviceUnit)) * HwpRenderTuning.LineShape.deviceUnit
    }

    /// 장치 단위 한 칸의 HWPUNIT (12 = 0.12pt × 100)
    static var hwpUnitsPerDeviceUnit: CGFloat {
        (HwpRenderTuning.LineShape.deviceUnit * 100).rounded()
    }
}
