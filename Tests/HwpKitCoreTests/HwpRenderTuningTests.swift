import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// `HwpRenderTuning` 값 핀 — 실측 상수의 우발적 변경을 diff와 CI 양쪽에서
/// 잡는다. 값을 바꾸려면 fidelity 전수 + 블록 스냅샷 + 실물 대조를 거친 뒤
/// 여기 기대값도 함께 갱신할 것 (HwpRenderTuning doc-comment 규약).
final class HwpRenderTuningTests: XCTestCase {
    func testTextTuningValues() {
        expect(HwpRenderTuning.Text.baselineAnchorRatio) == 0.85
        expect(HwpRenderTuning.Text.slightOverflowWidthRatio) == 1.06
        expect(HwpRenderTuning.Text.syntheticBoldStrokeWidth) == -3.5
        expect(HwpRenderTuning.Text.shadowOffsetScale) == 1.5
        expect(HwpRenderTuning.Text.strikethroughCenterRatio) == 0.35
        expect(HwpRenderTuning.Text.underlineAboveEdgeRatio) == 0.85
        expect(HwpRenderTuning.Text.underlineBelowEdgeRatio) == 0.15
        expect(HwpRenderTuning.Text.decorationLineThicknessRatio) == 0.04
        expect(HwpRenderTuning.Text.msWordLineHeightCellRatio) == 1.3
        expect(HwpRenderTuning.Text.msWordBaselineMarginCellRatio) == 0.15
        expect(HwpRenderTuning.Text.msWordUnderlineThicknessCellRatio) == 0.05
        expect(HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio) == 0.021
        expect(HwpRenderTuning.Text.msWordStrikethroughAscentRatio) == 0.273
        expect(HwpRenderTuning.Text.msWordScriptStrikethroughScale) == 0.696
        expect(HwpRenderTuning.Text.hwp200XDecorationLineThickness) == 0.36
        expect(HwpRenderTuning.Text.fixedSpaceEmRatio) == 0.5
        expect(HwpRenderTuning.Text.fixedWidthSpaceEmRatio) == 0.25
    }

    func testLineShapeTuningValues() {
        expect(HwpRenderTuning.LineShape.deviceUnit) == 0.12
        expect(HwpRenderTuning.LineShape.characterPatternThicknessPerMille) == 39
        expect(HwpRenderTuning.LineShape.patternUnitThicknessNumerator) == 22
        expect(HwpRenderTuning.LineShape.patternUnitThicknessDenominator) == 15
        expect(HwpRenderTuning.LineShape.borderPatternHwpUnits) == [
            28, 33, 42, 56, 70, 84, 113, 141, 169, 198, 283, 424, 567, 850, 1134, 1417,
        ]
        expect(HwpRenderTuning.LineShape.dashMinimumDotDeviceUnits) == 1
        expect(HwpRenderTuning.LineShape.dashMinimumLongDeviceUnits) == 10
        expect(HwpRenderTuning.LineShape.dashMinimumDotGapDeviceUnits) == 4
        expect(HwpRenderTuning.LineShape.dashMinimumLongGapDeviceUnits) == 2
        expect(HwpRenderTuning.LineShape.circleGapDotUnitRatio) == 1.5
        expect(HwpRenderTuning.LineShape.circleMinimumDotDeviceUnits) == 3
        expect(HwpRenderTuning.LineShape.circleMinimumGapDeviceUnits) == 2
        expect(HwpRenderTuning.LineShape.circleMinimumPathDeviceUnits) == 2
        expect(HwpRenderTuning.LineShape.circleOutlineDeviceUnits) == 1
        expect(HwpRenderTuning.LineShape.cellBorderCirclePitchUnitRatio) == 2
        expect(HwpRenderTuning.LineShape.characterDoubleLineBandEmRatio) == 0.12
        expect(HwpRenderTuning.LineShape.characterThickBandEmRatio) == 0.2
        expect(HwpRenderTuning.LineShape.characterWaveAmplitudeEmRatio) == 0.112
        expect(HwpRenderTuning.LineShape.characterWaveStrokeEmRatio) == 0.03
        expect(HwpRenderTuning.LineShape.characterDoubleWaveOffsetAmplitudeRatio) == 0.8
        expect(HwpRenderTuning.LineShape.characterWaveTopShiftThicknessRatio) == 1
        expect(HwpRenderTuning.LineShape.borderWaveStrokeThicknessRatio) == 0.25
        expect(HwpRenderTuning.LineShape.borderWaveShiftThicknessRatio) == 0.375
        expect(HwpRenderTuning.LineShape.borderDoubleWaveOffsetThicknessRatio) == 0.75
        expect(HwpRenderTuning.LineShape.waveVertexFlat) == 0.12
    }

    func testNumberingTuningValues() {
        expect(HwpRenderTuning.Numbering.fixedWidthEmRatio) == 1.5
    }

    func testEquationTuningValues() {
        expect(HwpRenderTuning.Equation.glyphScale) == 0.885
    }

    func testFootnoteTuningValues() {
        expect(HwpRenderTuning.Footnote.dividerDefaultMarginTop) == 8.5
        expect(HwpRenderTuning.Footnote.dividerDefaultMarginBottom) == 5.7
        expect(HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes) == 2.8
    }
}
