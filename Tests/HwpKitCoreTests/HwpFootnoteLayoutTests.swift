import CoreGraphics
@preconcurrency import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpFootnoteLayoutTests: XCTestCase {
    private var geometry: HwpPageGeometry!
    private var index: HwpIndex!
    private var layout: HwpFootnoteLayout!

    override func setUp() {
        super.setUp()
        // A4 page: 595×842 pt, 72 pt margins → contentFrame = (72, 72, 451, 698)
        geometry = HwpPageGeometry(
            pageSize: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
            contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
            headerFrame: nil,
            footerFrame: nil,
            columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
        )
        index = HwpIndex(from: CoreHwp.HwpFile())
        layout = HwpFootnoteLayout(fontResolver: HwpFontResolver.testDeterministic)
    }

    func testEmptyFootnotesReturnsEmptyArray() {
        let result = layout.layout(footnotes: [], onPage: geometry, index: index)
        expect(result) == []
    }

    func testSingleBlankFootnoteReturnsOneBlock() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        expect(result.count) == 1
    }

    func testSingleBlockHasNonEmptySeparatorLine() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        expect(block.separatorLine.width) > 0
        expect(block.separatorLine.height) > 0
    }

    func testSeparatorWidthIsAtLeast30PercentOfContentWidth() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        let expectedMinWidth = geometry.contentFrame.width * 0.3
        expect(block.separatorLine.width) >= expectedMinWidth
    }

    func testSeparatorWidthIsExactly30PercentOfContentWidth() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        let expected = geometry.contentFrame.width * 0.3
        expect(block.separatorLine.width) == expected
    }

    func testBlockNumberStartsAtOne() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        expect(result.first?.number) == 1
    }

    func testMultipleFootnotesAreNumberedSequentially() {
        let paragraphs = [CoreHwp.HwpParagraph(), CoreHwp.HwpParagraph(), CoreHwp.HwpParagraph()]
        let result = layout.layout(footnotes: paragraphs, onPage: geometry, index: index)
        for (idx, block) in result.enumerated() {
            expect(block.number) == idx + 1
        }
    }

    func testBlockFrameIsWithinReservedArea() {
        let paragraph = CoreHwp.HwpParagraph()
        let result = layout.layout(footnotes: [paragraph], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        let reservedTop = geometry.contentFrame.maxY - geometry.contentFrame.height * 0.3
        expect(block.frame.minY) >= reservedTop
        expect(block.frame.maxY) <= geometry.contentFrame.maxY + 1
    }
}
