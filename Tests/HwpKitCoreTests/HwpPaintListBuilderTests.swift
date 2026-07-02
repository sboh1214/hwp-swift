import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpPaintListBuilderTests: XCTestCase {
    private let builder = HwpPaintListBuilder()
    private lazy var index = HwpIndex(from: HwpFile())

    func testEmptyPageProducesNoCommands() {
        let list = builder.build(for: makePage(blocks: []), index: index)
        expect(list.commands.count) == 0
    }

    func testTextBlockProducesDrawText() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 72, width: 400, height: 20), kind: .text)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        guard case .drawText = list.commands[0] else {
            fail("Expected .drawText as first command")
            return
        }
    }

    func testPlaceholderBlockProducesDrawPlaceholder() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 100, width: 200, height: 100), kind: .placeholder)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 1
        guard case .drawPlaceholder = list.commands[0] else {
            fail("Expected .drawPlaceholder")
            return
        }
    }

    func testShapeBlockProducesDrawPath() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 200, width: 100, height: 100), kind: .shape)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        guard case .drawPath = list.commands[0] else {
            fail("Expected .drawPath")
            return
        }
    }

    func testImageBlockProducesPlaceholderOrDrawImage() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 300, width: 200, height: 150), kind: .image)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        let hasImageOrPlaceholder = list.commands.contains {
            if case .drawImage = $0 { return true }
            if case .drawPlaceholder = $0 { return true }
            return false
        }
        expect(hasImageOrPlaceholder) == true
    }

    func testTableBlockProducesStrokeRect() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 400, width: 300, height: 200), kind: .table)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        guard case .strokeRect = list.commands[0] else {
            fail("Expected .strokeRect")
            return
        }
    }

    func testTextboxBlockProducesFillAndStroke() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 100, width: 200, height: 80), kind: .textbox)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 2
        guard case .fillRect = list.commands[0] else {
            fail("Expected .fillRect as first command")
            return
        }
        guard case .strokeRect = list.commands[1] else {
            fail("Expected .strokeRect as second command")
            return
        }
    }

    func testFootnoteBlockProducesSeparatorAndText() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 700, width: 400, height: 60), kind: .footnote)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 2
        guard case .strokeRect = list.commands[0] else {
            fail("Expected .strokeRect separator as first command")
            return
        }
        guard case .drawText = list.commands[1] else {
            fail("Expected .drawText as second command")
            return
        }
    }

    private func makePage(blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
            blocks: blocks,
            pageNumber: 1
        )
    }
}
