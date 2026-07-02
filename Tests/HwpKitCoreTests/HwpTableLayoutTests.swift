@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpTableLayoutTests: XCTestCase {
        func testTwoByTwoUniformTableProducesTwoRowsAndTwoCells() {
            let result = layout().layout(table: table(), availableWidth: 200, availableHeight: 400, index: index())

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.rows.count) == 2
            expect(frame.rows[0].cells.count) == 2
            expect(frame.rows[1].cells.count) == 2
            expect(frame.outerFrame.width) == 200
        }

        func testMergedTwoRowCellSkipsCoveredGridPosition() {
            let cells = [
                cell(text: "merged", row: 0, column: 0, rowSpan: 2, columnSpan: 1),
                cell(text: "top right", row: 0, column: 1),
                cell(text: "bottom right", row: 1, column: 1),
            ]
            let result = layout().layout(
                table: table(cells: cells),
                availableWidth: 200,
                availableHeight: 400,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.rows.count) == 2
            expect(frame.rows[0].cells.count) == 2
            expect(frame.rows[1].cells.count) == 1
            expect(frame.rows[0].cells[0].cellFrame.height) > frame.rows[0].rowFrame.height
        }

        func testOverflowReturnsPlaceholderFailure() {
            let result = layout().layout(table: table(), availableWidth: 200, availableHeight: 1, index: index())

            guard case let .failure(element) = result else {
                fail("expected table layout failure")
                return
            }
            expect(element.kind) == .placeholder
            expect(element.page) == 0
            expect(element.hint) == "표: 다중 페이지"
        }
    }

    private extension HwpTableLayoutTests {
        func layout() -> HwpTableLayout {
            HwpTableLayout(fontResolver: .testDeterministic)
        }

        func table(cells: [CoreHwp.HwpTableCell]? = nil) -> CoreHwp.HwpTable {
            CoreHwp.HwpTable(
                property: CoreHwp.HwpTableProperty(
                    property: 0,
                    rowCount: 2,
                    columnCount: 2,
                    cellSpacing: 0,
                    leftInnerMargin: 0,
                    rightInnerMargin: 0,
                    topInnerMargin: 0,
                    bottomInnerMargin: 0,
                    rowSize: [0, 0, 0, 0],
                    borderFillId: 0,
                    validZoneInfoSize: nil,
                    zonePropertyArray: nil,
                    rawPayload: Data(),
                    rawTrailing: Data()
                ),
                cellArray: cells ?? [
                    cell(text: "a", row: 0, column: 0),
                    cell(text: "b", row: 0, column: 1),
                    cell(text: "c", row: 1, column: 0),
                    cell(text: "d", row: 1, column: 1),
                ]
            )
        }

        func cell(
            text: String,
            row: UInt16,
            column: UInt16,
            rowSpan: UInt16 = 1,
            columnSpan: UInt16 = 1
        ) -> CoreHwp.HwpTableCell {
            CoreHwp.HwpTableCell(
                header: CoreHwp.HwpTableCellHeader(
                    paragraphCount: 1,
                    property: 0,
                    propertyInfo: CoreHwp.HwpListHeaderProperty(),
                    listHeaderWidthRef: 0,
                    cellPropertyInfo: CoreHwp.HwpTableCellHeaderProperty(),
                    isHeader: false,
                    rawTrailing: placementData(row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan),
                    rawPayload: Data(),
                    unknownChildren: []
                ),
                paragraphArray: [paragraph(text: text)]
            )
        }

        func paragraph(text: String) -> CoreHwp.HwpParagraph {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = nil

            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = [0]
            paraCharShape.shapeId = [0]
            paragraph.paraCharShape = paraCharShape
            return paragraph
        }

        func index() -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: [0: CoreHwp.HwpParaShape(property1: 0, marginLeft: 0, tabDefId: 0, lineSpacing2: 160)],
                borderFills: [:],
                tabDefs: [:],
                styles: [:],
                bullets: [:],
                numberings: [:],
                binData: [:],
                faceNamesKorean: [:],
                faceNamesEnglish: [:],
                faceNamesChinese: [:],
                faceNamesJapanese: [:],
                faceNamesEtc: [:],
                faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }

        func placementData(row: UInt16, column: UInt16, rowSpan: UInt16, columnSpan: UInt16) -> Data {
            var data = Data()
            append(column, to: &data)
            append(row, to: &data)
            append(columnSpan, to: &data)
            append(rowSpan, to: &data)
            return data
        }

        func append(_ value: some FixedWidthInteger, to data: inout Data) {
            var littleEndian = value.littleEndian
            data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
        }
    }
#endif
