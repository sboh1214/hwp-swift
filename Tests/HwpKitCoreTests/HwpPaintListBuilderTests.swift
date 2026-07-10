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
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 72, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(string: "hello")
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        guard case .drawText = list.commands[0] else {
            fail("Expected .drawText as first command")
            return
        }
    }

    func testTextBlockWithoutTextProducesNoCommands() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 72, width: 400, height: 20), kind: .text)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 0
    }

    func testPlaceholderBlockProducesDrawPlaceholder() {
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 100, width: 200, height: 100),
            kind: .placeholder
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 1
        guard case .drawPlaceholder = list.commands[0] else {
            fail("Expected .drawPlaceholder")
            return
        }
    }

    func testShapeBlockWithoutPayloadProducesDrawPath() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 200, width: 100, height: 100), kind: .shape)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        guard case .drawPath = list.commands[0] else {
            fail("Expected .drawPath")
            return
        }
    }

    func testShapeBlockWithGeometryPayloadProducesDrawPath() {
        let geometry = HwpShapeGeometry(
            path: HwpShapeGeometry.ellipsePath(from: CGRect(x: 0, y: 0, width: 80, height: 40)),
            fillColor: nil,
            strokeColor: .hwpBlack,
            strokeWidth: 2
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 200, width: 80, height: 40),
            kind: .shape,
            payload: .shape(geometry)
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 1
        guard case let .drawPath(path, _, _, strokeWidth) = list.commands[0] else {
            fail("Expected .drawPath")
            return
        }
        expect(strokeWidth) == 2
        // path는 블록 origin만큼 평행이동된다
        expect(path.boundingBox.minX).to(beCloseTo(72, within: 0.01))
        expect(path.boundingBox.minY).to(beCloseTo(200, within: 0.01))
    }

    func testImageBlockWithoutPayloadProducesPlaceholder() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 300, width: 200, height: 150), kind: .image)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) >= 1
        let hasPlaceholder = list.commands.contains {
            if case .drawPlaceholder = $0 {
                return true
            }
            return false
        }
        expect(hasPlaceholder) == true
    }

    func testImagePayloadWithStoredDataProducesDrawImageReference() {
        let store = HwpImageStore(
            dataByBinItemId: [1: Data([0xFF, 0xD8])],
            extensionByBinItemId: [1: "jpg"]
        )
        let storeBuilder = HwpPaintListBuilder(imageStore: store)
        let frame = CGRect(x: 72, y: 300, width: 200, height: 150)
        let block = AnyHwpBlock(
            frame: frame,
            kind: .image,
            payload: .image(HwpImageBlockInfo(binItemId: 1))
        )
        let list = storeBuilder.build(for: makePage(blocks: [block]), index: index)
        guard case let .drawImageReference(binItemId, rect, style) = list.commands.first else {
            fail("Expected .drawImageReference")
            return
        }
        expect(binItemId) == 1
        expect(rect) == frame
        expect(style).to(beNil())
    }

    func testImagePayloadWithMissingDataProducesPlaceholder() {
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 300, width: 200, height: 150),
            kind: .image,
            payload: .image(HwpImageBlockInfo(binItemId: 9))
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        guard case let .drawPlaceholder(_, text) = list.commands.first else {
            fail("Expected .drawPlaceholder for missing image data")
            return
        }
        expect(text) == "[이미지]"
    }

    func testTablePayloadProducesCellBordersAndText() {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cellRect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let cell = HwpTableCellFrame(
            cellFrame: cellRect,
            row: 0,
            column: 0,
            rowSpan: 1,
            columnSpan: 1,
            paragraphs: [laidOutParagraph(text: "cell", rect: cellRect)],
            borders: .uniform(width: 0.5, color: black),
            fillColor: nil
        )
        let table = HwpTableFrame(
            outerFrame: cellRect,
            rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
            borderColor: black,
            borderWidth: 1
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 400, width: 300, height: 200),
            kind: .table,
            payload: .table(table)
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)

        let fillRects = list.commands.filter {
            if case .fillRect = $0 {
                return true
            }
            return false
        }
        let drawTexts = list.commands.filter {
            if case .drawText = $0 {
                return true
            }
            return false
        }
        expect(fillRects.count) == 4 // 4방향 테두리 edge rect
        expect(drawTexts.count) == 1
    }

    func testTableBlockWithoutPayloadOrTextProducesNoCommands() {
        let block = AnyHwpBlock(frame: CGRect(x: 72, y: 400, width: 300, height: 200), kind: .table)
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 0
    }

    func testTextboxPayloadProducesFillAndStroke() {
        let textbox = HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
            paragraphs: [],
            borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
            borderWidth: 1,
            fillColor: nil
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 100, width: 200, height: 80),
            kind: .textbox,
            payload: .textbox(textbox)
        )
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

    func testTextboxPayloadDrawsParagraphText() {
        let textbox = HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
            paragraphs: [laidOutParagraph(
                text: "inside box",
                rect: CGRect(x: 2, y: 2, width: 196, height: 20)
            )],
            borderColor: nil,
            borderWidth: 0,
            fillColor: nil
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 72, y: 100, width: 200, height: 80),
            kind: .textbox,
            payload: .textbox(textbox)
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        // 테두리 정보가 없으면 배경 + 텍스트만 (기본 테두리 없음 — CCL 한글.app 실측)
        expect(list.commands.count) == 2
        guard case let .drawText(attributed, _, _) = list.commands[1] else {
            fail("Expected .drawText as second command")
            return
        }
        expect(attributed.string) == "inside box"
    }

    func testFootnotePayloadProducesSeparatorAndText() {
        let blockFrame = CGRect(x: 72, y: 700, width: 400, height: 60)
        let footnote = HwpFootnoteBlock(
            frame: blockFrame,
            paragraphs: [laidOutParagraph(
                text: "footnote",
                rect: CGRect(x: 0, y: 0, width: 400, height: 20)
            )],
            number: 1,
            separatorLine: CGRect(x: 72, y: 690, width: 150, height: 1)
        )
        let block = AnyHwpBlock(frame: blockFrame, kind: .footnote, payload: .footnote(footnote))
        let list = builder.build(for: makePage(blocks: [block]), index: index)
        expect(list.commands.count) == 2
        guard case .fillRect = list.commands[0] else {
            fail("Expected .fillRect separator as first command")
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

    private func laidOutParagraph(text: String, rect: CGRect) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: text),
            frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
            rect: rect,
            paragraphId: 0
        )
    }
}
