import CoreGraphics
import Foundation

// MARK: - 원형 점선의 원 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// 원형 점선(`circle`)의 원 크기·간격·세로 자리. 한글은 원을 600dpi 장치 단위(0.12pt)의 정수로
/// 그린다 (#239) — 한글 문서·MS 워드 호환 문서의 글자선과 단 구분선은 점선(1·1.5)의 점을 원으로
/// 그리는 **점 무늬**, 표 셀 테두리는 두께를 단위로 하는 **격자**다 (`circleDeviceGeometry(for:)`).
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

    /// 원형 점선이 표 셀 테두리의 **격자** 갈래인가 — 테두리 축척에서 단 구분선이 아닌 자리.
    /// 단 구분선과 글자선은 점 무늬 갈래다 (한글은 같은 두께의 단 구분선 원을 표 셀 테두리보다
    /// 크고 성기게 그린다 — 1mm 간격 88u vs 48u).
    static func circleUsesCellGrid(_ line: Line) -> Bool {
        guard line.scale == .border else { return false }
        switch line.placement {
        case .divider:
            return false
        case .border, .underlineBelow, .strikethrough, .underlineAbove:
            return true
        }
    }

    /// 장치 단위로 반올림하는 입력의 상한 (pt) — 두께(글자선은 글자 크기 × 0.039)가 이보다 크면
    /// 장치 단위 반올림이 뜻이 없으므로 반올림 전 비율로 셈한다. HWPUNIT·장치 단위로 옮기는 곱이
    /// 넘치지 않게 하는 경계다 (이 아래 두께의 HWPUNIT 곱은 1e17 안이다).
    static let circleDeviceRoundingLimit: CGFloat = 1e12

    /// 한글 문서의 원 — (칠 지름, 중심 간격) pt. 두께를 HWPUNIT(0.01pt)으로 반올림하고(글자선은 글자
    /// 크기를 HWPUNIT으로 둔 뒤 × 39/1000을 반올림), 격자 갈래는 그것을 장치 단위로 반올림한 r이
    /// 단위(간격 2r, 경로 지름 = r을 짝수로 올림), 점 무늬 갈래는 × 22/15를 장치 단위로 반올림한 점
    /// 단위 q가 단위다(간격 = max(q, 3u) + max(1.5q 반올림, 2u), 경로 지름 = q를 짝수로 올림·최소
    /// 2u). 칠 지름은 경로 지름 + 윤곽 1u. 반올림은 0.5를 올리고, 곱과 나눗셈을 정수 분수의 차례로
    /// 두어 0.5u 경계를 정확히 가른다. 상한(`circleDeviceRoundingLimit`) 밖 두께는 반올림 전 비율
    /// (격자: 지름 = 두께·간격 2배, 점 무늬: 지름 = 점 단위·간격 2.5배)이고 지름은 유한 최댓값에서
    /// 멈춘다 (간격은 무한대로 넘쳐도 첫 원만 남는다 — `circleCount(for:)`).
    static func circleDeviceGeometry(for line: Line) -> (diameter: CGFloat, pitch: CGFloat) {
        typealias Shape = HwpRenderTuning.LineShape
        let grid = circleUsesCellGrid(line)
        // 나눗셈 먼저 — 글자 크기가 유한 최댓값 근처여도 두께가 넘치지 않게
        let thickness: CGFloat = if case let .characterLine(fontSize) = line.scale {
            fontSize / 1000 * Shape.characterCircleThicknessPerMille
        } else {
            line.thickness
        }
        guard thickness < circleDeviceRoundingLimit else {
            if grid {
                return (thickness, thickness * Shape.borderCirclePitchThicknessRatio)
            }
            // 나눗셈 먼저 — 두께가 유한 최댓값 근처여도 점 단위가 넘치지 않게
            let dot = thickness / Shape.circleDotUnitThicknessDenominator
                * Shape.circleDotUnitThicknessNumerator
            return (min(dot, .greatestFiniteMagnitude), dot * (1 + Shape.circleGapDotUnitRatio))
        }
        let hwpUnits: CGFloat = if case let .characterLine(fontSize) = line.scale {
            roundHalfUp((fontSize * 100).rounded() * Shape.characterCircleThicknessPerMille / 1000)
        } else {
            roundHalfUp(line.thickness * 100)
        }
        let hwpUnitsPerDeviceUnit = (Shape.deviceUnit * 100).rounded()
        let pathUnits: CGFloat
        let pitchUnits: CGFloat
        if grid {
            let side = max(1, roundHalfUp(hwpUnits / hwpUnitsPerDeviceUnit))
            pathUnits = evenCeiling(side)
            pitchUnits = side * Shape.borderCirclePitchThicknessRatio
        } else {
            let dot = roundHalfUp(
                hwpUnits * Shape.circleDotUnitThicknessNumerator
                    / Shape.circleDotUnitThicknessDenominator / hwpUnitsPerDeviceUnit
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
