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
