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
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        expect(result.count) == 1
    }

    func testSingleBlockHasNonEmptySeparatorLine() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        expect(block.separatorLine.width) > 0
        expect(block.separatorLine.height) > 0
    }

    func testSeparatorWidthWithoutShapeIsOneThirdOfContentWidth() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        let expected = geometry.contentFrame.width / 3
        expect(block.separatorLine.width).to(beCloseTo(expected, within: 0.01))
    }

    func testBlockNumberComesFromInput() {
        let result = layout.layout(footnotes: [input(number: 7)], onPage: geometry, index: index)
        expect(result.first?.number) == 7
    }

    func testMultipleFootnotesKeepInputNumbers() {
        let footnotes = [input(number: 1), input(number: 2), input(number: 3)]
        let result = layout.layout(footnotes: footnotes, onPage: geometry, index: index)
        expect(result.count) == 3
        for (idx, block) in result.enumerated() {
            expect(block.number) == idx + 1
        }
    }

    func testBlocksStackBelowSeparator() {
        let footnotes = [input(number: 1), input(number: 2)]
        let result = layout.layout(footnotes: footnotes, onPage: geometry, index: index)
        guard result.count == 2 else {
            fail("Expected two blocks")
            return
        }
        expect(result[0].frame.minY) >= result[0].separatorLine.maxY
        expect(result[1].frame.minY) >= result[0].frame.maxY
    }

    func testBlockFrameIsWithinReservedArea() {
        let result = layout.layout(footnotes: [input(number: 1)], onPage: geometry, index: index)
        guard let block = result.first else {
            fail("Expected at least one block")
            return
        }
        // 각주 영역은 최대 콘텐츠 높이의 절반까지만 확보된다.
        let reservedTop = geometry.contentFrame.maxY - geometry.contentFrame.height / 2
        expect(block.frame.minY) >= reservedTop
        expect(block.frame.maxY) <= geometry.contentFrame.maxY + 1
    }

    private func input(number: Int) -> HwpFootnoteLayout.Input {
        HwpFootnoteLayout.Input(paragraph: CoreHwp.HwpParagraph(), number: number)
    }
}
