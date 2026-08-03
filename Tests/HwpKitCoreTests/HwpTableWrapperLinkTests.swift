import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 셀 개체의 감싼 링크 열쇠 (R52) 와 분할 보존 (R58)

    extension HwpTableLayoutTests {
        /// 표가 쪼개지면 마커 문단과 개체가 **다른 조각**으로 갈린다 (R58) — 도형은
        /// midY로 배정되는데 U+FFFC run은 잘린 문단 한쪽에만 남는다. 마커가 없는
        /// 조각에서도 감싼 링크가 살아야 방출·히트가 함께 유지된다.
        func testWrapperLinkSurvivesRowSplit() throws {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cellRect = CGRect(x: 0, y: 0, width: 200, height: 100)
            let shapeRect = CGRect(x: 0, y: 60, width: 50, height: 30)
            let attributed = NSMutableAttributedString(string: "\u{FFFC}")
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: full)
            attributed.addAttribute(
                HwpAttributedStringKey.hyperlink,
                value: "https://example.com/split", range: full
            )
            let cell = HwpTableCellFrame(
                cellFrame: cellRect,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                // 마커 문단은 위 20pt — 컷(40) **위** 조각에 남는다
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: attributed,
                    frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 200, height: 20),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil,
                shapes: [HwpCellShape(
                    // midY 75 > 40 — 마커와 **반대** 조각으로 간다
                    rect: shapeRect,
                    geometry: HwpShapeGeometry(
                        path: CGPath(
                            rect: CGRect(origin: .zero, size: shapeRect.size), transform: nil
                        ),
                        fillColor: black.cgColor, strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 60,
                    controlIndex: 0,
                    paragraphId: 1
                )]
            )

            let result = HwpTableSplitter.fillSegment(
                rows: [HwpTableRowFrame(rowFrame: cellRect, cells: [cell])][...],
                remaining: 40
            )

            let bottom = try XCTUnwrap(result.replacement)
            let bottomCell = try XCTUnwrap(bottom.cells.first)
            let movedShape = try XCTUnwrap(bottomCell.shapes.first)
            expect(bottomCell.paragraphs.isEmpty) == true
            expect(movedShape.wrapperURL) == "https://example.com/split"

            // 마커 없는 조각을 눌러도 링크가 열린다 (히트 폴백)
            let page = HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: CGRect(x: 0, y: 0, width: 200, height: 100),
                    kind: .table,
                    payload: .table(HwpTableFrame(
                        outerFrame: bottom.rowFrame,
                        rows: [bottom],
                        borderColor: black, borderWidth: 1
                    ))
                )],
                pageNumber: 1
            )
            expect(HwpHitTester().hit(page: page, point: CGPoint(
                x: movedShape.rect.midX, y: movedShape.rect.midY
            ))) == .hyperlink(url: "https://example.com/split", blockIndex: 0)
        }

        /// 셀 안 중첩 표도 감싼 링크 열쇠 **(문단 `paraId`, `ctrlHeaderArray` 서수)**
        /// 를 싣는다 (R52). 서수는 표 아닌 컨트롤까지 센 **원본 배열 위치**여야
        /// U+FFFC run의 `controlIndex`와 이어진다 — 결과 배열 위치로 매기면 앞에
        /// 책갈피·그림이 있는 문단에서 어긋나 감싼 링크가 가림으로 죽는다.
        func testNestedTableInCellCarriesWrapperKey() {
            var host = paragraph(text: "outer")
            host.paraHeader.paraId = 77
            host.ctrlHeaderArray = [
                .bookmark(CoreHwp.HwpOtherControl(
                    ctrlId: .bookmark,
                    rawTrailing: Data(),
                    rawPayload: Data(),
                    ctrlDataRecords: [],
                    unknownChildren: []
                )),
                .table(table()),
            ]
            let hostCell = CoreHwp.HwpTableCell(
                header: cellHeader(row: 0, column: 0, rowSpan: 1, columnSpan: 1),
                paragraphArray: [host]
            )

            let result = layout().layout(
                table: table(cells: [hostCell]),
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result,
                  let nested = frame.rows.first?.cells.first?.nestedTables.first
            else {
                fail("expected nested table layout success")
                return
            }
            expect(nested.controlIndex) == 1
            expect(nested.paragraphId) == 77
        }
    }
#endif
