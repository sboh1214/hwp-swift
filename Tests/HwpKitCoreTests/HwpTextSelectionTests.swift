import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 텍스트 위치 비교·선택 정규화 테스트.
final class HwpTextSelectionTests: XCTestCase {
    private func position(
        _ page: Int, _ block: Int, _ unit: Int, _ offset: Int
    ) -> HwpTextPosition {
        HwpTextPosition(
            pageIndex: page, blockIndex: block, unitIndex: unit, characterOffset: offset
        )
    }

    func testPositionOrderingIsLexicographic() {
        expect(self.position(0, 0, 0, 5) < self.position(0, 0, 0, 9)) == true
        expect(self.position(0, 0, 1, 0) > self.position(0, 0, 0, 99)) == true
        expect(self.position(0, 3, 0, 0) > self.position(0, 2, 9, 99)) == true
        expect(self.position(2, 0, 0, 0) > self.position(1, 9, 9, 99)) == true
    }

    func testBackwardSelectionNormalizes() {
        let selection = HwpTextSelection(
            anchor: position(1, 2, 0, 7),
            focus: position(0, 1, 0, 3)
        )

        expect(selection.range.start) == position(0, 1, 0, 3)
        expect(selection.range.end) == position(1, 2, 0, 7)
        expect(selection.isCollapsed) == false
    }

    func testCollapsedSelection() {
        let selection = HwpTextSelection(
            anchor: position(0, 0, 0, 4),
            focus: position(0, 0, 0, 4)
        )

        expect(selection.isCollapsed) == true
    }
}
