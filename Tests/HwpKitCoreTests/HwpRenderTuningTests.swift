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
        expect(HwpRenderTuning.Text.baselineLiftRatio) == 0.15
        expect(HwpRenderTuning.Text.slightOverflowWidthRatio) == 1.06
        expect(HwpRenderTuning.Text.syntheticBoldStrokeWidth) == -3.5
        expect(HwpRenderTuning.Text.shadowOffsetScale) == 1.5
        expect(HwpRenderTuning.Text.strikethroughCenterRatio) == 0.35
        expect(HwpRenderTuning.Text.underlineAboveCenterRatio) == 0.87
        expect(HwpRenderTuning.Text.underlineBelowCenterRatio) == 0.17
        expect(HwpRenderTuning.Text.decorationLineThicknessRatio) == 0.04
        expect(HwpRenderTuning.Text.msWordLineHeightCellRatio) == 1.3
        expect(HwpRenderTuning.Text.msWordBaselineMarginCellRatio) == 0.15
        expect(HwpRenderTuning.Text.msWordUnderlineThicknessCellRatio) == 0.05
        expect(HwpRenderTuning.Text.msWordUnderlineOffsetCellRatio) == 0.021
        expect(HwpRenderTuning.Text.msWordStrikethroughAscentRatio) == 0.273
        expect(HwpRenderTuning.Text.hwp200XDecorationLineThickness) == 0.36
        expect(HwpRenderTuning.Text.hwp200XUnderlineBelowEdgeRatio) == 0.15
        expect(HwpRenderTuning.Text.hwp200XUnderlineAboveEdgeRatio) == 0.85
    }

    func testLineShapeTuningValues() {
        expect(HwpRenderTuning.LineShape.characterDashUnitEmRatio) == 0.057
        expect(HwpRenderTuning.LineShape.borderDashUnitThicknessRatio)
            .to(beCloseTo(22.0 / 15.0, within: 1e-9))
        expect(HwpRenderTuning.LineShape.characterCirclePitchDiameterRatio) == 2.5
        expect(HwpRenderTuning.LineShape.borderCirclePitchThicknessRatio) == 2
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
