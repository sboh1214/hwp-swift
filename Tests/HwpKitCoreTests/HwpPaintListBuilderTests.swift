import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpPaintListBuilderTests: XCTestCase {
    private let builder = HwpPaintListBuilder()
    private lazy var index = HwpIndex(from: HwpFile())

    /// 절단면 클립이 있는 셀 그림은 저작 rect를 유지한 채 페이지 좌표로
    /// 오프셋된 clipRect로 방출된다 (R32 #2).
    func testClippedCellImageEmitsOffsetClipRect() {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cell = HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 100, height: 40),
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: [],
            borders: HwpBorderSet.uniform(width: 0.5, color: black),
            fillColor: nil,
            images: [HwpCellImage(
                rect: CGRect(x: 0, y: -40, width: 50, height: 80),
                binItemId: 3,
                style: nil,
                clipRect: CGRect(x: 0, y: 0, width: 50, height: 40),
                controlInstanceId: 3
            )]
        )
        let table = HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 100, height: 40),
            rows: [HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 100, height: 40),
                cells: [cell]
            )],
            borderColor: black, borderWidth: 1
        )
        let block = AnyHwpBlock(
            frame: CGRect(x: 10, y: 100, width: 100, height: 40),
            kind: .table,
            payload: .table(table)
        )
        let list = builder.build(for: makePage(blocks: [block]), index: index)

        let clips: [(CGRect, CGRect?)] = list.commands.compactMap {
            if case let .drawImageReference(_, rect, _, clip) = $0 {
                return (rect, clip)
            }
            return nil
        }
        expect(clips.count) == 1
        expect(clips.first?.0) == CGRect(x: 10, y: 60, width: 50, height: 80)
        expect(clips.first?.1) == CGRect(x: 10, y: 100, width: 50, height: 40)
    }

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
        guard case let .drawImageReference(binItemId, rect, style, _) = list.commands.first else {
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

    /// attributed span 없이 문단-레벨 URL만 가진 컨테이너 문단(표/글상자/각주)의
    /// 링크가 paint list에 폴백 .hyperlink로 담긴다 — hit tester만 처리하던 것을
    /// 공개 paint list도 담는다 (R53 #4).
    func testContainerParagraphLevelHyperlinkEmitsFallbackCommand() {
        let paragraphRect = CGRect(x: 2, y: 3, width: 196, height: 20)
        let textbox = HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
            paragraphs: [laidOutParagraph(
                text: "link", rect: paragraphRect, hyperlinkURL: "http://example.com"
            )],
            borderColor: nil,
            borderWidth: 0,
            fillColor: nil
        )
        let blockFrame = CGRect(x: 72, y: 100, width: 200, height: 80)
        let block = AnyHwpBlock(frame: blockFrame, kind: .textbox, payload: .textbox(textbox))
        let list = builder.build(for: makePage(blocks: [block]), index: index)

        let hyperlinks = list.commands.compactMap { command -> (rect: CGRect, url: String)? in
            if case let .hyperlink(rect, url) = command {
                return (rect, url)
            }
            return nil
        }
        expect(hyperlinks.count) == 1
        expect(hyperlinks.first?.url) == "http://example.com"
        expect(hyperlinks.first?.rect)
            == paragraphRect.offsetBy(dx: blockFrame.minX, dy: blockFrame.minY)
    }

    /// 필드 스팬이 있는 컨테이너 문단은 전체-rect 폴백을 방출하지 않는다 —
    /// 모델 hyperlinkURL은 스팬 존재와 무관하게 설정되고 스팬 글리프 rect는
    /// walkText가 이미 방출하므로, 폴백이 겹치면 앞뒤 평문까지 링크로
    /// 표시된다 (R55 #2). hit tester의 spanAwareHyperlinkURL과 같은 게이트.
    func testContainerParagraphWithFieldSpanSkipsFallbackHyperlink() {
        let paragraphRect = CGRect(x: 2, y: 3, width: 196, height: 20)
        let attributed = NSMutableAttributedString(string: "plain link plain")
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink,
            value: "http://example.com",
            range: NSRange(location: 6, length: 4)
        )
        let paragraph = HwpLaidOutParagraph(
            attributedString: attributed,
            frame: HwpParagraphFrame(totalHeight: paragraphRect.height, lines: []),
            rect: paragraphRect,
            paragraphId: 0,
            hyperlinkURL: "http://example.com"
        )
        let textbox = HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
            paragraphs: [paragraph],
            borderColor: nil,
            borderWidth: 0,
            fillColor: nil
        )
        let blockFrame = CGRect(x: 72, y: 100, width: 200, height: 80)
        let block = AnyHwpBlock(frame: blockFrame, kind: .textbox, payload: .textbox(textbox))
        let list = builder.build(for: makePage(blocks: [block]), index: index)

        let fallbackRect = paragraphRect.offsetBy(dx: blockFrame.minX, dy: blockFrame.minY)
        let hyperlinkRects = list.commands.compactMap { command -> CGRect? in
            if case let .hyperlink(rect, _) = command {
                return rect
            }
            return nil
        }
        expect(hyperlinkRects).toNot(beEmpty())
        expect(hyperlinkRects).toNot(contain(fallbackRect))
    }

    private func makePage(blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
            blocks: blocks,
            pageNumber: 1
        )
    }

    private func laidOutParagraph(
        text: String, rect: CGRect, hyperlinkURL: String? = nil
    ) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: text),
            frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
            rect: rect,
            paragraphId: 0,
            hyperlinkURL: hyperlinkURL
        )
    }
}

extension HwpPaintListBuilderTests {
    /// 이중 하단·우측 테두리의 둘째 선도 셀 안(maxY/maxX 이내)에 그려진다 —
    /// 셀 밖으로 나가면 인접 셀·표 밖을 침범한다 (R42 #2).
    func testDoubleBottomRightBordersStayInsideCell() {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cellRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let cell = HwpTableCellFrame(
            cellFrame: cellRect,
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: [],
            borders: HwpBorderSet(
                top: 2, bottom: 2, left: 2, right: 2,
                topColor: black, bottomColor: black, leftColor: black, rightColor: black,
                topDouble: true, bottomDouble: true, leftDouble: true, rightDouble: true
            ),
            fillColor: nil
        )
        let table = HwpTableFrame(
            outerFrame: cellRect,
            rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
            borderColor: black, borderWidth: 1
        )
        let block = AnyHwpBlock(frame: cellRect, kind: .table, payload: .table(table))
        let list = builder.build(for: makePage(blocks: [block]), index: index)

        let fills: [CGRect] = list.commands.compactMap {
            if case let .fillRect(rect, _) = $0 {
                return rect
            }
            return nil
        }
        expect(fills).toNot(beEmpty())
        for rect in fills {
            expect(rect.maxY).to(beLessThanOrEqualTo(cellRect.maxY + 0.01))
            expect(rect.maxX).to(beLessThanOrEqualTo(cellRect.maxX + 0.01))
            expect(rect.minY).to(beGreaterThanOrEqualTo(cellRect.minY - 0.01))
            expect(rect.minX).to(beGreaterThanOrEqualTo(cellRect.minX - 0.01))
        }
    }
}
