import CoreGraphics
import Foundation

// MARK: - 원형 점선의 원 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// 원형 점선(`circle`)의 원 크기·간격·세로 자리. 한글은 원을 600dpi 장치 단위(0.12pt)의 정수로
/// 그린다 (#239) — 한글 문서·MS 워드 호환 문서의 글자선, 단 구분선, 셀 간격이 있는 표의 셀 테두리
/// (#243)는 점선(1·1.5)의 점을 원으로 그리는 **점 무늬**, 셀 간격이 없는 표의 셀 테두리는 두께를
/// 단위로 하는 **격자**다 (`circleDeviceGeometry(for:)` — 무늬 두께·갈래는 대시와 공용,
/// `HwpLineShapeGeometry+Dashes.swift`).
/// 한글 2007 호환 문서의 글자선은 크기와 무관한 고정 pt다 (#227). 값은
/// `HwpRenderTuning.LineShape`의 원형 점선 절 (한글 12.30.0 PDF 실측).
extension HwpLineShapeGeometry {
    /// 원의 **칠 지름** (pt) — 경로가 채우는 원의 지름이다. 한글은 원 경로를 채우고 한 단위 윤곽을
    /// 둘러 그리므로 장치 단위 갈래는 경로 지름 + 1u이고(`circleOutlineDeviceUnits`), 한글 2007 호환
    /// 문서는 고정 1.32pt(1.20 + 윤곽 0.12)다. `crossExtent`·`alongExtent`·끝 원의 넘침이 모두 이
    /// 값으로 칠한 범위를 잰다.
    static func circleDiameter(for line: Line) -> CGFloat {
        switch line.scale {
        case .hwp200XCharacterLine:
            HwpRenderTuning.LineShape.hwp200XCircleDiameter
        case .characterLine, .border:
            circleDeviceGeometry(for: line).diameter
        }
    }

    /// 원 중심 간격 (pt) — `circleDiameter(for:)`와 같은 갈래
    static func circlePitch(for line: Line) -> CGFloat {
        switch line.scale {
        case .hwp200XCharacterLine:
            HwpRenderTuning.LineShape.hwp200XCirclePitch
        case .characterLine, .border:
            circleDeviceGeometry(for: line).pitch
        }
    }

    /// 원형 점선의 원 중심 y — 한글 2007 호환 문서의 글자선만 단선 중심에서 띠가 자라는 쪽으로
    /// 옮겨진다 (아래 밑줄 아래·위 밑줄 위, `hwp200XCircleCenterShift`). 나머지는 단선 중심.
    static func circleCenterY(for line: Line) -> CGFloat {
        guard line.scale == .hwp200XCharacterLine else { return 0 }
        let shift = HwpRenderTuning.LineShape.hwp200XCircleCenterShift
        switch line.placement {
        case .underlineBelow: return shift
        case .underlineAbove: return -shift
        case .strikethrough, .border, .divider: return 0
        }
    }

    /// 한글 문서의 원 — (칠 지름, 중심 간격) pt. 무늬 두께(HWPUNIT 정수, `patternHwpUnits(for:)` —
    /// 글자선은 글자 크기를 HWPUNIT으로 둔 뒤 × 39/1000을 반올림, 테두리·단 구분선은 표 26 굵기마다의
    /// 값)에서 격자 갈래(`usesCellGrid(_:)`)는 그것을 장치 단위로 반올림한 r이 단위(간격 2r, 경로 지름
    /// = r을 짝수로 올림), 점 무늬 갈래는 × 22/15를 장치 단위로 반올림한 점 단위 q가 단위다(간격 =
    /// max(q, 3u) + max(1.5q 반올림, 2u), 경로 지름 = q를 짝수로 올림·최소 2u). 칠 지름은 경로 지름 +
    /// 윤곽 1u. 반올림은 0.5를 올리고, 곱과 나눗셈을 정수 분수의 차례로 두어 0.5u 경계를 정확히
    /// 가른다. 상한(`deviceRoundingLimit`) 밖 두께는 반올림 전 비율(격자: 지름 = 두께·간격 2배,
    /// 점 무늬: 지름 = 점 단위·간격 2.5배)이고 지름은 유한 최댓값에서 멈춘다 (간격은 무한대로 넘쳐도
    /// 첫 원만 남는다 — `circleCount(for:)`).
    static func circleDeviceGeometry(for line: Line) -> (diameter: CGFloat, pitch: CGFloat) {
        typealias Shape = HwpRenderTuning.LineShape
        let grid = usesCellGrid(line)
        let thickness = patternThickness(for: line)
        guard thickness < deviceRoundingLimit else {
            if grid {
                return (thickness, thickness * Shape.cellBorderCirclePitchUnitRatio)
            }
            // 나눗셈 먼저 — 곱이 먼저 넘치지 않게 (두께가 유한 최댓값 근처면 간격은 무한대로 넘쳐도
            // 지름은 아래에서 유한 최댓값에 멈춘다)
            let dot = thickness / Shape.patternUnitThicknessDenominator
                * Shape.patternUnitThicknessNumerator
            return (min(dot, .greatestFiniteMagnitude), dot * (1 + Shape.circleGapDotUnitRatio))
        }
        let hwpUnits = patternHwpUnits(for: line)
        let pathUnits: CGFloat
        let pitchUnits: CGFloat
        if grid {
            let side = max(1, roundHalfUp(hwpUnits / hwpUnitsPerDeviceUnit))
            pathUnits = evenCeiling(side)
            pitchUnits = side * Shape.cellBorderCirclePitchUnitRatio
        } else {
            let dot = roundHalfUp(
                hwpUnits * Shape.patternUnitThicknessNumerator
                    / Shape.patternUnitThicknessDenominator / hwpUnitsPerDeviceUnit
            )
            pathUnits = max(Shape.circleMinimumPathDeviceUnits, evenCeiling(dot))
            let gap = roundHalfUp(dot * Shape.circleGapDotUnitRatio)
            pitchUnits = max(dot, Shape.circleMinimumDotDeviceUnits)
                + max(gap, Shape.circleMinimumGapDeviceUnits)
        }
        return (
            (pathUnits + Shape.circleOutlineDeviceUnits) * Shape.deviceUnit,
            pitchUnits * Shape.deviceUnit
        )
    }

    /// 0.5를 올리는 반올림 — 한글의 장치 단위 반올림 (양수 입력)
    static func roundHalfUp(_ value: CGFloat) -> CGFloat {
        (value + 0.5).rounded(.down)
    }

    /// 짝수로 올림 — 한글의 원 경로 지름은 짝수 장치 단위다 (실측: 점 단위 3u → 4u, 5u → 6u)
    static func evenCeiling(_ value: CGFloat) -> CGFloat {
        (value / 2).rounded(.up) * 2
    }
}
