import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpDocumentTests: XCTestCase {
    func testEmptyDocumentPagesCount() {
        expect(HwpDocument.empty.pages.count) == 0
    }

    func testEmptyDocumentUnsupportedElementsCount() {
        expect(HwpDocument.empty.unsupportedElements.count) == 0
    }

    func testBlockKindRoundTrip() {
        let block = AnyHwpBlock(frame: .zero, kind: .text)
        let margins = HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0)
        let page = HwpPage(size: .zero, margins: margins, blocks: [block], pageNumber: 1)
        expect(page.blocks.first?.kind) == .text
    }
}
