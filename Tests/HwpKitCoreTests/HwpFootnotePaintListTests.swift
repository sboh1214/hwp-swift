import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 각주 블록의 개체 (그림·도형·글상자·표)가 각주 콘텐츠로 그려지는지 —
/// 이슈 #94의 증상은 "각주 영역이 71.32pt 자리를 예약하는데 그 안에 테두리도
/// 글자도 하나 없다"였다. 방출 순서 규약은 표 셀 경로와 같다:
/// 글 뒤로 개체 → 문단 텍스트 → 나머지 개체 → 각주 안 표.
final class HwpFootnotePaintListTests: XCTestCase {
    /// 글 뒤로 각주 표는 문단 텍스트 **앞에** 그려진다 (R47 #1) — 표가 평면·
    /// 정렬 정보를 잃고 항상 마지막에 그려지면 텍스트를 덮는다.
    func testBehindTextFootnoteTablePaintsBeforeParagraphText() throws {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let cellRect = CGRect(x: 0, y: 0, width: 80, height: 20)
        func footnote(paintsBehindText: Bool) -> HwpFootnoteBlock {
            HwpFootnoteBlock(
                frame: CGRect(x: 50, y: 600, width: 400, height: 40),
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: NSAttributedString(string: "각주 본문"),
                    frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 400, height: 20),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: cellRect,
                    table: HwpTableFrame(
                        outerFrame: cellRect,
                        rows: [HwpTableRowFrame(
                            rowFrame: cellRect,
                            cells: [HwpTableCellFrame(
                                cellFrame: cellRect,
                                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                                paragraphs: [],
                                borders: .uniform(width: 0.5, color: black),
                                fillColor: HwpRGBColor(red: 200, green: 200, blue: 200)
                            )]
                        )],
                        borderColor: black, borderWidth: 1
                    ),
                    controlInstanceId: 9,
                    paintsBehindText: paintsBehindText
                )]
            )
        }
        func firstTextIndex(_ block: HwpFootnoteBlock) -> Int? {
            HwpPaintListBuilder(fontResolver: .testDeterministic)
                .footnoteCommands(block, blockFrame: block.frame, drawSeparator: false)
                .firstIndex {
                    if case .drawText = $0 {
                        true
                    } else {
                        false
                    }
                }
        }
        func firstCellFillIndex(_ block: HwpFootnoteBlock) -> Int? {
            HwpPaintListBuilder(fontResolver: .testDeterministic)
                .footnoteCommands(block, blockFrame: block.frame, drawSeparator: false)
                .firstIndex {
                    if case .fillRect = $0 {
                        true
                    } else {
                        false
                    }
                }
        }

        // 글 뒤로: 셀 채움이 텍스트보다 먼저
        let behind = footnote(paintsBehindText: true)
        expect(try XCTUnwrap(firstCellFillIndex(behind)))
            < (try XCTUnwrap(firstTextIndex(behind)))
        // 기본(글 앞으로): 텍스트가 먼저
        let front = footnote(paintsBehindText: false)
        expect(try XCTUnwrap(firstTextIndex(front)))
            < (try XCTUnwrap(firstCellFillIndex(front)))
    }

    /// `%hlk`가 감싼 **비 treatAsChar** 개체는 마커 폭이 0이라 스팬 방출이 아무
    /// rect도 못 낸다 (`hyperlinkRegions`의 `maxX > minX` 가드). 히트는
    /// `wrapperHyperlinkURL`로 개체에서 링크를 여니, 방출도 **개체 rect**로 내야
    /// 밑줄과 탭이 같은 자리에 있다 (R56 — AGENTS.md "방출 ≡ 히트").
    func testWrappedFootnoteObjectEmitsHyperlinkAtObjectRect() {
        let blockFrame = CGRect(x: 50, y: 600, width: 400, height: 40)
        // 개체는 문단 rect(높이 20) **밖**에 저작 위치로 놓인다 — 문단 폴백
        // 링크로는 덮이지 않는 자리다
        let shapeRect = CGRect(x: 200, y: 25, width: 60, height: 30)
        let attributed = NSMutableAttributedString(string: "\u{FFFC}")
        let full = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
        attributed.addAttribute(
            HwpAttributedStringKey.hyperlink,
            value: "https://example.com/wrapped-object", range: full
        )
        let footnote = HwpFootnoteBlock(
            frame: blockFrame,
            paragraphs: [HwpLaidOutParagraph(
                attributedString: attributed,
                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                rect: CGRect(x: 0, y: 0, width: 400, height: 20),
                paragraphId: 1,
                hyperlinkURL: nil
            )],
            number: 1,
            separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
            shapes: [HwpCellShape(
                rect: shapeRect,
                geometry: HwpShapeGeometry(
                    path: CGPath(rect: shapeRect, transform: nil),
                    fillColor: HwpRGBColor(red: 0, green: 0, blue: 0).cgColor,
                    strokeColor: nil, strokeWidth: 0
                ),
                paintsBehindText: false,
                zOrder: 0, sourceOrder: 0,
                controlInstanceId: 40,
                controlIndex: 0,
                paragraphId: 1
            )]
        )
        let page = HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: [AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )],
            pageNumber: 1
        )

        let commands = HwpPaintListBuilder(fontResolver: .testDeterministic)
            .build(for: page, index: HwpIndex(from: CoreHwp.HwpFile())).commands
        let linkRects = commands.compactMap { command -> CGRect? in
            guard case let .hyperlink(rect, url) = command,
                  url == "https://example.com/wrapped-object"
            else { return nil }
            return rect
        }
        expect(linkRects).to(contain(
            shapeRect.offsetBy(dx: blockFrame.minX, dy: blockFrame.minY)
        ))
    }

    private let builder = HwpPaintListBuilder()
    private lazy var index = HwpIndex(from: HwpFile())

    func testFootnoteImagePayloadEmitsImageReference() {
        let blockFrame = CGRect(x: 72, y: 700, width: 400, height: 60)
        let footnote = footnoteBlock(
            frame: blockFrame,
            images: [HwpCellImage(
                rect: CGRect(x: 30, y: 4, width: 10, height: 11),
                binItemId: 4,
                style: nil,
                controlInstanceId: 1
            )]
        )
        let commands = footnoteCommands(footnote, frame: blockFrame)

        let imageRects: [CGRect] = commands.compactMap {
            if case let .drawImageReference(binItemId, rect, _, _) = $0, binItemId == 4 {
                return rect
            }
            return nil
        }
        // 블록-로컬 rect가 페이지 좌표로 오프셋돼 나온다
        expect(imageRects) == [CGRect(x: 102, y: 704, width: 10, height: 11)]
    }

    /// 각주 안 표는 셀 테두리 + 셀 텍스트를 모두 낸다 (헌법주석 883쪽 각주 29의
    /// 4×8 표가 통째로 사라졌던 자리).
    func testFootnoteNestedTableEmitsCellBordersAndText() {
        let blockFrame = CGRect(x: 72, y: 600, width: 400, height: 80)
        let cellRect = CGRect(x: 0, y: 0, width: 100, height: 20)
        let cell = HwpTableCellFrame(
            cellFrame: cellRect,
            row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            paragraphs: [laidOutParagraph(
                text: "표 안", rect: CGRect(x: 2, y: 2, width: 96, height: 16)
            )],
            borders: .uniform(width: 1, color: HwpRGBColor(red: 0, green: 0, blue: 0)),
            fillColor: nil
        )
        let table = HwpTableFrame(
            outerFrame: cellRect,
            rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])],
            borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
            borderWidth: 1
        )
        let footnote = footnoteBlock(
            frame: blockFrame,
            nestedTables: [HwpNestedTableFrame(
                rect: CGRect(x: 18, y: 14, width: 100, height: 20),
                table: table,
                controlInstanceId: 2
            )]
        )
        let commands = footnoteCommands(footnote, frame: blockFrame)

        // 셀 테두리 4변 (fillRect) — 각주 좌표로 오프셋된다
        let borderRects: [CGRect] = commands.compactMap {
            if case let .fillRect(rect, _) = $0 {
                return rect
            }
            return nil
        }
        // 구분선 1 + 테두리 4
        expect(borderRects.count) == 5
        for rect in borderRects.dropFirst() {
            expect(rect.minX) >= 72 + 18 - 0.01
            expect(rect.maxX) <= 72 + 18 + 100 + 0.01
        }
        let texts: [String] = commands.compactMap {
            if case let .drawText(attributed, _, _) = $0 {
                return attributed.string
            }
            return nil
        }
        expect(texts).to(contain("표 안"))
    }

    /// 평면 순서: 글 뒤로 개체는 각주 텍스트보다 **먼저**, 나머지 개체는 뒤에,
    /// 각주 안 표는 그 뒤에 (표 셀 경로 `walkTable`과 같은 규약).
    func testFootnoteObjectPaintOrderPutsBehindTextObjectsFirst() {
        let blockFrame = CGRect(x: 72, y: 700, width: 400, height: 60)
        let footnote = HwpFootnoteBlock(
            frame: blockFrame,
            paragraphs: [laidOutParagraph(
                text: "각주 본문", rect: CGRect(x: 0, y: 0, width: 400, height: 20)
            )],
            number: 1,
            separatorLine: CGRect(x: 72, y: 690, width: 150, height: 1),
            images: [
                HwpCellImage(
                    rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                    binItemId: 1, style: nil,
                    paintsBehindText: true, zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 1
                ),
                HwpCellImage(
                    rect: CGRect(x: 20, y: 0, width: 8, height: 8),
                    binItemId: 2, style: nil,
                    paintsBehindText: false, zOrder: 0, sourceOrder: 1,
                    controlInstanceId: 2
                ),
            ]
        )
        let commands = footnoteCommands(footnote, frame: blockFrame)

        let kinds: [String] = commands.compactMap {
            switch $0 {
            case let .drawImageReference(binItemId, _, _, _): "image\(binItemId)"
            case .drawText: "text"
            case .fillRect: nil
            default: nil
            }
        }
        expect(kinds) == ["image1", "text", "image2"]
    }

    private func footnoteBlock(
        frame: CGRect,
        images: [HwpCellImage] = [],
        shapes: [HwpCellShape] = [],
        textboxes: [HwpCellTextbox] = [],
        nestedTables: [HwpNestedTableFrame] = []
    ) -> HwpFootnoteBlock {
        HwpFootnoteBlock(
            frame: frame,
            paragraphs: [laidOutParagraph(
                text: "각주 본문",
                rect: CGRect(x: 0, y: 0, width: frame.width, height: 20)
            )],
            number: 1,
            separatorLine: CGRect(x: frame.minX, y: frame.minY - 10, width: 150, height: 1),
            images: images,
            shapes: shapes,
            textboxes: textboxes,
            nestedTables: nestedTables
        )
    }

    private func footnoteCommands(
        _ footnote: HwpFootnoteBlock, frame: CGRect
    ) -> [HwpPaintCommand] {
        let block = AnyHwpBlock(frame: frame, kind: .footnote, payload: .footnote(footnote))
        return builder.build(for: makePage(blocks: [block]), index: index).commands
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
