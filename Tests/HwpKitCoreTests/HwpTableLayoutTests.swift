@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpTableLayoutTests: XCTestCase {
        func testTwoByTwoUniformTableProducesTwoRowsAndTwoCells() {
            let result = layout().layout(
                table: table(),
                availableWidth: 200,
                index: index()
            )

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

        func testCellsCarryGridPositionAndParagraphText() {
            let result = layout().layout(
                table: table(),
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            let firstCell = frame.rows[0].cells[0]
            expect(firstCell.row) == 0
            expect(firstCell.column) == 0
            expect(firstCell.rowSpan) == 1
            expect(firstCell.columnSpan) == 1
            expect(firstCell.paragraphs.first?.attributedString.string) == "a"
            let lastCell = frame.rows[1].cells[1]
            expect(lastCell.row) == 1
            expect(lastCell.column) == 1
            expect(lastCell.paragraphs.first?.attributedString.string) == "d"
        }

        /// 페이지보다 큰 표도 layout 자체는 성공한다.
        /// 페이지 분할은 paginator가 row 단위로 수행한다 (구 동작: "표: 다중 페이지" 실패).
        func testTallTableSucceedsWithAllRowsPresent() {
            let result = layout().layout(
                table: table(),
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success even when taller than a page")
                return
            }
            expect(frame.rows.count) == 2
            expect(frame.outerFrame.height) > 0
        }

        func testNestedTableReturnsPlaceholderFailure() {
            let nested = table()
            var host = paragraph(text: "outer")
            host.ctrlHeaderArray = [.table(nested)]
            let hostCell = CoreHwp.HwpTableCell(
                header: cellHeader(row: 0, column: 0, rowSpan: 1, columnSpan: 1),
                paragraphArray: [host]
            )
            let outer = table(cells: [hostCell])

            let result = layout().layout(
                table: outer,
                availableWidth: 200,
                index: index()
            )

            guard case let .failure(element) = result else {
                fail("expected nested table layout failure")
                return
            }
            expect(element.kind) == .placeholder
            expect(element.hint) == "표: 중첩 표"
        }

        func testAuthoredCellWidthsDriveColumnWidths() {
            // 150 + 50 HWPUNIT*100 = 150pt + 50pt authored → scaled to 200pt outer width
            let cells = [
                cell(text: "a", row: 0, column: 0, width: 15000),
                cell(text: "b", row: 0, column: 1, width: 5000),
                cell(text: "c", row: 1, column: 0, width: 15000),
                cell(text: "d", row: 1, column: 1, width: 5000),
            ]
            let result = layout().layout(
                table: table(cells: cells),
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            let first = frame.rows[0].cells[0].cellFrame.width
            let second = frame.rows[0].cells[1].cellFrame.width
            expect(first).to(beCloseTo(150, within: 1))
            expect(second).to(beCloseTo(50, within: 1))
        }

        func testZeroWidthCellsFallBackToEqualColumnDivision() {
            let result = layout().layout(
                table: table(),
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            let first = frame.rows[0].cells[0].cellFrame.width
            let second = frame.rows[0].cells[1].cellFrame.width
            expect(first).to(beCloseTo(100, within: 1))
            expect(second).to(beCloseTo(100, within: 1))
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
            columnSpan: UInt16 = 1,
            width: UInt32 = 0
        ) -> CoreHwp.HwpTableCell {
            CoreHwp.HwpTableCell(
                header: cellHeader(
                    row: row,
                    column: column,
                    rowSpan: rowSpan,
                    columnSpan: columnSpan,
                    width: width
                ),
                paragraphArray: [paragraph(text: text)]
            )
        }

        func cellHeader(
            row: UInt16,
            column: UInt16,
            rowSpan: UInt16,
            columnSpan: UInt16,
            width: UInt32 = 0
        ) -> CoreHwp.HwpTableCellHeader {
            // 표 80 layout: LE u16 colAddr@0, rowAddr@2, colSpan@4, rowSpan@6,
            // u32 width@8, u32 height@12, 4x i16 margins@16, u16 borderFillId@24
            let rawTrailing = cellPropertyData(
                row: row,
                column: column,
                rowSpan: rowSpan,
                columnSpan: columnSpan,
                width: width
            )
            return CoreHwp.HwpTableCellHeader(
                paragraphCount: 1,
                property: 0,
                propertyInfo: CoreHwp.HwpListHeaderProperty(),
                listHeaderWidthRef: 0,
                cellPropertyInfo: CoreHwp.HwpTableCellHeaderProperty(),
                isHeader: false,
                cellProperty: CoreHwp.HwpTableCellProperty.decode(from: rawTrailing),
                rawTrailing: rawTrailing,
                rawPayload: Data(),
                unknownChildren: []
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
            let paraShape = CoreHwp.HwpParaShape(
                property1: 0,
                marginLeft: 0,
                tabDefId: 0,
                lineSpacing2: 160
            )
            return HwpIndex(
                charShapes: [:],
                paraShapes: [0: paraShape],
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

        func cellPropertyData(
            row: UInt16,
            column: UInt16,
            rowSpan: UInt16,
            columnSpan: UInt16,
            width: UInt32,
            height: UInt32 = 0,
            borderFillId: UInt16 = 0
        ) -> Data {
            var data = Data()
            append(column, to: &data)
            append(row, to: &data)
            append(columnSpan, to: &data)
            append(rowSpan, to: &data)
            append(width, to: &data)
            append(height, to: &data)
            for _ in 0 ..< 4 {
                append(Int16(0), to: &data)
            }
            append(borderFillId, to: &data)
            return data
        }

        func append(_ value: some FixedWidthInteger, to data: inout Data) {
            var littleEndian = value.littleEndian
            data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
        }
    }
#endif
