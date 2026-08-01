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

        func testNestedTableLaysOutInsideHostCell() {
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

            guard case let .success(frame) = result else {
                fail("expected nested table layout success")
                return
            }
            let cell = frame.rows[0].cells[0]
            expect(cell.nestedTables.count) == 1
            guard let nestedFrame = cell.nestedTables.first else { return }
            // 중첩 표는 호스트 문단 아래에 쌓인다.
            expect(nestedFrame.rect.minY)
                >= (cell.paragraphs.first?.rect.maxY ?? 0) - 0.5
            expect(nestedFrame.table.rows.count) == 2
            let nestedTexts = nestedFrame.table.rows
                .flatMap(\.cells)
                .flatMap(\.paragraphs)
                .map(\.attributedString.string)
            expect(nestedTexts) == ["a", "b", "c", "d"]
            // 셀 높이는 문단 + 중첩 표 높이를 포함한다.
            expect(cell.cellFrame.maxY) >= nestedFrame.rect.maxY - 0.5
        }

        func testNestedTablesBeyondDepthLimitAreSkipped() {
            // 5단계 사슬: root(0) → d1 → d2 → d3 (배치) → d4의 중첩(d5 상당)은 생략
            var innermost = table(cells: [CoreHwp.HwpTableCell(
                header: cellHeader(row: 0, column: 0, rowSpan: 1, columnSpan: 1),
                paragraphArray: [paragraph(text: "depth5")]
            )])
            for depth in stride(from: 4, through: 1, by: -1) {
                var host = paragraph(text: "depth\(depth)")
                host.ctrlHeaderArray = [.table(innermost)]
                innermost = table(cells: [CoreHwp.HwpTableCell(
                    header: cellHeader(row: 0, column: 0, rowSpan: 1, columnSpan: 1),
                    paragraphArray: [host]
                )])
            }

            let result = layout().layout(
                table: innermost,
                availableWidth: 200,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            var cell = frame.rows[0].cells[0]
            var reachedDepth = 0
            while let nested = cell.nestedTables.first {
                reachedDepth += 1
                guard let nestedCell = nested.table.rows.first?.cells.first else { break }
                cell = nestedCell
            }
            expect(reachedDepth) == 3
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

        func testColumnRelativeTableWidthResolvesAsPercent() {
            var authored = table()
            // 크기 기준 '단'이면 저장 폭은 퍼센트다 — 5000 = 단 폭 400pt의 50%
            authored.commonCtrlProperty.width = 5000
            authored.commonCtrlProperty.propertyInfo.widthRelativeTo = .column
            let result = layout().layout(
                table: authored,
                availableWidth: 400,
                index: index(),
                sizeResolver: HwpObjectSizeResolver(
                    paperSize: CGSize(width: 595, height: 842),
                    contentSize: CGSize(width: 500, height: 700),
                    columnWidth: 400
                )
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.outerFrame.width).to(beCloseTo(200, within: 1))
        }

        func testFloatingTableKeepsAuthoredWidthBeyondColumn() {
            var authored = table()
            // 종이 100% (10000) — 떠 있는 표는 단 폭 클램프를 받지 않는다 (#3)
            authored.commonCtrlProperty.width = 10000
            authored.commonCtrlProperty.propertyInfo.widthRelativeTo = .paper
            let result = layout().layout(
                table: authored,
                availableWidth: 200,
                index: index(),
                sizeResolver: HwpObjectSizeResolver(
                    paperSize: CGSize(width: 595, height: 842),
                    contentSize: CGSize(width: 500, height: 700),
                    columnWidth: 400
                ),
                clampToAvailableWidth: false
            )
            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.outerFrame.width).to(beCloseTo(595, within: 1))
        }

        /// 혼합 높이 라인(origin 델타 불균등)은 등분(height/개수)이 아니라 실제
        /// origin.y 델타로 전진량을 낸다 — lineAlignedCut·slicedParagraph가 공유해
        /// 절단선과 조각 경계가 일치한다 (R53 #2).
        func testLineAdvancesUsesActualOriginDeltasNotAverage() {
            let lines = [
                HwpLineFrame(origin: CGPoint(x: 0, y: 0), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 0, length: 5)),
                HwpLineFrame(origin: CGPoint(x: 0, y: 20), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 5, length: 5)),
                HwpLineFrame(origin: CGPoint(x: 0, y: 50), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 10, length: 5)),
            ]
            let paragraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "abcdefghijklmno"),
                frame: HwpParagraphFrame(totalHeight: 70, lines: lines),
                rect: CGRect(x: 0, y: 0, width: 100, height: 70),
                paragraphId: 0
            )

            // 실제 델타 [20, 30, 20](마지막 = 70-(50-0))은 등분(70/3≈23.3)과 다르다.
            expect(HwpTableSplitter.lineAdvances(of: paragraph)) == [20, 30, 20]
        }

        /// 절단선 정렬은 첫 미적합 라인에서 멈춘다 — 안 맞는 중간 라인을 건너뛰고
        /// 뒤의 짧은 라인을 누적하면 절단선이 조각 경계(slicedParagraph)와 어긋난다.
        /// 전진량 [10, 30, 5]·절단선 25는 라인0(10)까지만 정렬하고 라인1(30)에서
        /// 멈춰 10을 낸다 — 라인2(5)까지 세면 15가 되어 조각 경계와 어긋난다 (R54 #1).
        func testLineAlignedCutStopsAtFirstNonFittingLine() {
            let lines = [
                HwpLineFrame(origin: CGPoint(x: 0, y: 0), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 0, length: 5)),
                HwpLineFrame(origin: CGPoint(x: 0, y: 10), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 5, length: 5)),
                HwpLineFrame(origin: CGPoint(x: 0, y: 40), width: 100, baseline: 10,
                             attributedRange: NSRange(location: 10, length: 5)),
            ]
            let paragraph = HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "abcdefghijklmno"),
                frame: HwpParagraphFrame(totalHeight: 45, lines: lines),
                rect: CGRect(x: 0, y: 0, width: 100, height: 45),
                paragraphId: 0
            )
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let cell = HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 0, width: 100, height: 45),
                row: 0,
                column: 0,
                rowSpan: 1,
                columnSpan: 1,
                paragraphs: [paragraph],
                borders: HwpBorderSet.uniform(width: 0, color: black),
                fillColor: nil
            )
            let row = HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
                cells: [cell]
            )

            expect(HwpTableSplitter.lineAlignedCut(for: row, proposed: 25)) == 10
        }

        /// 절단선 정렬은 고정점까지 수렴한다 — pass 수를 캡하면 셀 간 경계가
        /// 엇갈린 행에서 도중 값(어느 셀의 라인 경계도 아닌 y)을 반환한다 (R55 #3).
        /// 전진량 A[20×5]·B[10,20,20,20,20]·절단선 95는 pass마다 번갈아 낮아져
        /// 5-pass째 첫 라인 아래로 붕괴 — 원래 절단선 95로 폴백해야 한다.
        /// 4-pass 캡 코드는 도중 값 10(B 경계, A 비경계)을 반환했다.
        func testLineAlignedCutConvergesBeyondFourPasses() {
            func paragraph(
                origins: [CGFloat], height: CGFloat, x: CGFloat
            ) -> HwpLaidOutParagraph {
                let lines = origins.enumerated().map { index, y in
                    HwpLineFrame(origin: CGPoint(x: 0, y: y), width: 90, baseline: 8,
                                 attributedRange: NSRange(location: index * 3, length: 3))
                }
                return HwpLaidOutParagraph(
                    attributedString: NSAttributedString(
                        string: String(repeating: "가나다", count: origins.count)
                    ),
                    frame: HwpParagraphFrame(totalHeight: height, lines: lines),
                    rect: CGRect(x: x, y: 0, width: 100, height: height),
                    paragraphId: 0
                )
            }
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            func cell(
                _ paragraph: HwpLaidOutParagraph, x: CGFloat, column: Int
            ) -> HwpTableCellFrame {
                HwpTableCellFrame(
                    cellFrame: CGRect(x: x, y: 0, width: 100, height: 110),
                    row: 0, column: column, rowSpan: 1, columnSpan: 1,
                    paragraphs: [paragraph],
                    borders: HwpBorderSet.uniform(width: 0, color: black),
                    fillColor: nil
                )
            }
            let row = HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 200, height: 110),
                cells: [
                    cell(paragraph(origins: [0, 20, 40, 60, 80], height: 100, x: 0),
                         x: 0, column: 0),
                    cell(paragraph(origins: [0, 10, 30, 50, 70], height: 90, x: 100),
                         x: 100, column: 1),
                ]
            )

            expect(HwpTableSplitter.lineAlignedCut(for: row, proposed: 95)) == 95
        }

        /// pass 상한을 넘는 준-무한 ping-pong(조작 문서의 엇갈린 라인 그리드)은
        /// 미정렬 cutY로 폴백한다 — 상한 없이는 O(절단 높이) pass로 로드가
        /// 지연되고, 도중 값 반환은 셀 간 경계 불일치를 만든다 (R56 #1).
        /// A 경계 {70,72,…,168}·B 경계 {70,71,73,…,167}·절단선 169는 pass당
        /// 2pt씩 50 pass를 내려가 70에서 수렴 — 상한(32) 초과이므로 169 반환.
        func testLineAlignedCutFallsBackToProposedCutWhenPassCapExceeded() {
            func paragraph(origins: [CGFloat], height: CGFloat, x: CGFloat) -> HwpLaidOutParagraph {
                let lines = origins.enumerated().map { index, y in
                    HwpLineFrame(origin: CGPoint(x: 0, y: y), width: 90, baseline: 8,
                                 attributedRange: NSRange(location: index, length: 1))
                }
                return HwpLaidOutParagraph(
                    attributedString: NSAttributedString(
                        string: String(repeating: "가", count: origins.count)
                    ),
                    frame: HwpParagraphFrame(totalHeight: height, lines: lines),
                    rect: CGRect(x: x, y: 0, width: 100, height: height),
                    paragraphId: 0
                )
            }
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            func cell(_ paragraph: HwpLaidOutParagraph, x: CGFloat, column: Int) -> HwpTableCellFrame {
                HwpTableCellFrame(
                    cellFrame: CGRect(x: x, y: 0, width: 100, height: 175),
                    row: 0, column: column, rowSpan: 1, columnSpan: 1,
                    paragraphs: [paragraph],
                    borders: HwpBorderSet.uniform(width: 0, color: black),
                    fillColor: nil
                )
            }
            let aOrigins = [0, 70] + stride(from: 72, through: 168, by: 2).map(CGFloat.init)
            let bOrigins = [0, 70, 71] + stride(from: 73, through: 167, by: 2).map(CGFloat.init)
            let row = HwpTableRowFrame(
                rowFrame: CGRect(x: 0, y: 0, width: 200, height: 175),
                cells: [
                    cell(paragraph(origins: aOrigins, height: 170, x: 0), x: 0, column: 0),
                    cell(paragraph(origins: bOrigins, height: 169, x: 100), x: 100, column: 1),
                ]
            )

            expect(HwpTableSplitter.lineAlignedCut(for: row, proposed: 169)) == 169
        }
    }

    extension HwpTableLayoutTests {
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
