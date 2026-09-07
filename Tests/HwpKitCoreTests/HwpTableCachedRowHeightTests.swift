@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 저작된 셀 높이 (표 80)가 라인 캐시의 줄 상자보다 작을 때의 행 높이 (#160).
    ///
    /// 규약 요약: 셀 문단 전부가 라인 캐시로 측정된 셀은 저작 높이를 신뢰하되,
    /// 그 값이 `캐시 줄 상자를 쌓은 높이 + 위아래 안쪽 여백`(`PlacedCell.cachedCellHeight`)
    /// 보다 작으면 그 높이로 올린다. 경계는 마지막 줄의 줄 **간격을 뺀** 줄 상자다 —
    /// 줄 간격까지 든 `cachedParagraphHeight`를 경계로 삼으면 저작 높이가 살짝
    /// 아래인 정상 셀(헌법주석 25개·noori 8개)까지 부푼다.
    final class HwpTableCachedRowHeightTests: XCTestCase {
        /// numbering-sequence 3쪽 재현: 한컴오피스 한글 12.30 macOS가 셀 높이를
        /// 위아래 여백 합 282 HWPUNIT로 저장했고 줄은 1000 (줄 간격 600). 한글은
        /// 1000 + 282 = 12.82pt로 그린다 (표 공통 속성 height와 같다).
        func testAuthoredHeightBelowLineBoxRisesToLineBoxPlusMargins() throws {
            let frame = try layoutRows(
                authoredHeights: [282],
                cells: [[
                    [try lineParagraph(lines: 1)],
                    [try lineParagraph(lines: 1)],
                ]]
            )
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))
            for cell in frame.rows[0].cells {
                expect(cell.cellFrame.height).to(beCloseTo(12.82, within: 0.01))
            }
            expect(frame.outerFrame.height).to(beCloseTo(12.82, within: 0.01))
        }

        /// 대조군: 저작 높이가 줄 상자 + 여백(12.82) 이상이지만 줄 간격을 포함한
        /// 캐시 높이 + 여백(16 + 2.82 = 18.82)보다는 작은 셀 — 저작 높이가 그대로다.
        /// 경계를 줄 간격 포함으로 잡으면 이 셀이 18.82로 부푼다.
        func testAuthoredHeightAtOrAboveLineBoxStaysAuthored() throws {
            let frame = try layoutRows(
                authoredHeights: [1300],
                cells: [[[try lineParagraph(lines: 1)]]]
            )
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(13.00, within: 0.01))

            let exact = try layoutRows(
                authoredHeights: [1282],
                cells: [[[try lineParagraph(lines: 1)]]]
            )
            expect(exact.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))
        }

        /// 여러 줄·여러 문단: 문단마다 캐시 전진량(줄 높이 + 줄 간격)을 배치와 같은
        /// 순서로 쌓고 마지막 줄의 줄 간격만 뺀다 — 2줄 문단 3200 + 1줄 문단 1000 +
        /// 여백 282 = 4482. 캐시의 줄 위치는 쓰지 않으므로 둘째 문단이 셀 누적
        /// 위치(3200)에서 시작하든 0에서 다시 시작하든(헌법주석 s22/p201/c16) 같다.
        func testMultiLineMultiParagraphStacksAdvancesMinusTrailingSpacing() throws {
            for secondStart in [Int32(3200), 0] {
                let frame = try layoutRows(
                    authoredHeights: [282],
                    cells: [[[
                        try lineParagraph(lines: 2),
                        try HwpSynthetic.lineSegParagraph(
                            "다", segments: [(location: secondStart, height: 1000)]
                        ),
                    ]]]
                )
                expect(frame.rows[0].rowFrame.height).to(beCloseTo(44.82, within: 0.01))
            }
        }

        /// 문단 위/아래 간격은 배치가 셀 안에 그대로 더하므로 (첫 문단 위 간격만큼
        /// 글자가 내려간다) 하한에도 든다 — 줄 1000 + 위 400 + 아래 200 + 여백 282 =
        /// 1882. 간격을 빼면 저작 282인 셀에서 글자가 아래 여백을 넘는다.
        func testParagraphSpacingCountsTowardFloor() throws {
            let paragraph = try oneLine()
            let table = CoreHwp.HwpTable(
                property: tableProperty(rowCount: 1, columnCount: 1),
                cellArray: [cell(row: 0, column: 0, height: 282, paragraphs: [paragraph])]
            )
            let result = layout().layout(
                table: table, availableWidth: 400, index: index(spacingTop: 800, spacingBottom: 400)
            )
            guard case let .success(frame) = result else {
                XCTFail("expected table layout success")
                return
            }
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(18.82, within: 0.01))
            let rect = try XCTUnwrap(frame.rows[0].cells[0].paragraphs.first?.rect)
            // 글자 줄 상자(10pt)가 위 여백 1.41 + 위 간격 4 아래에서 시작해 아래 여백 안에 끝난다.
            expect(rect.minY).to(beCloseTo(5.41, within: 0.01))
            expect(rect.minY + 10) <= frame.rows[0].cells[0].cellFrame.maxY - 1.41 + 0.01
        }

        /// 여러 행에 걸친 셀도 같은 하한을 쓰고, 부족한 높이는 마지막 행에 더한다.
        func testRowSpanCellAddsShortfallToLastRow() throws {
            let spanning = try lineParagraph(lines: 3)
            let table = CoreHwp.HwpTable(
                property: tableProperty(rowCount: 2, columnCount: 2),
                cellArray: [
                    cell(row: 0, column: 0, rowSpan: 2, height: 282, paragraphs: [spanning]),
                    cell(row: 0, column: 1, height: 1282, paragraphs: [try oneLine()]),
                    cell(row: 1, column: 1, height: 1282, paragraphs: [try oneLine()]),
                ]
            )
            let frame = try layout(table)
            // 걸친 셀은 4200 + 282 = 44.82pt가 필요하고 두 행이 12.82 + 12.82 = 25.64뿐이라
            // 나머지 19.18을 둘째 행에 더한다.
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(12.82, within: 0.01))
            expect(frame.rows[1].rowFrame.height).to(beCloseTo(32.00, within: 0.01))
            expect(frame.rows[0].cells[0].cellFrame.height).to(beCloseTo(44.82, within: 0.01))
        }

        /// 캐시가 없는 문단이 하나라도 있으면 (다시 조판하는 셀) 하한을 쓰지 않고
        /// 종전대로 CT 측정 높이와 저작 높이의 max를 쓴다 — 줄 간격까지 든
        /// 콘텐츠 높이라 하한보다 크다.
        func testCellWithoutFullCacheKeepsContentHeight() throws {
            let frame = try layoutRows(
                authoredHeights: [282],
                cells: [[[try HwpSynthetic.textParagraph("가")]]]
            )
            let contentHeight = frame.rows[0].cells[0].paragraphs[0].frame.totalHeight + 2.82
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(contentHeight, within: 0.01))
            expect(frame.rows[0].rowFrame.height) > 12.82
        }

        /// 셀 여백을 셀 고유 값으로 두는 셀은 그 여백으로 하한을 잰다.
        func testCellSpecificMarginsCountTowardFloor() throws {
            var cell = cell(row: 0, column: 0, height: 100, paragraphs: [try oneLine()])
            cell.header.cellPropertyInfo = CoreHwp.HwpTableCellHeaderProperty(rawValue: 1 << 0)
            cell.header.cellProperty?.marginArray = [0, 0, 500, 300]
            let frame = try layout(CoreHwp.HwpTable(
                property: tableProperty(rowCount: 1, columnCount: 1),
                cellArray: [cell]
            ))
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(18.00, within: 0.01))
        }

        /// `cachedLineExtent`: `cachedParagraphHeight`와 같은 유효성 검사 — 줄 위치가
        /// 되돌아가면 둘 다 nil이고, 유효하면 전진량 높이가 서로 같다.
        func testCachedLineExtentSharesValidityWithCachedParagraphHeight() throws {
            let valid = try HwpSynthetic.lineSegParagraph(
                "가나", segments: [(location: 200, height: 1000), (location: 1800, height: 900)]
            )
            let extent = try XCTUnwrap(HwpParagraphLayout.cachedLineExtent(valid))
            expect(extent.top) == 200
            expect(extent.bottom) == 2700
            expect(extent.spacedBottom) == 3300
            expect(extent.advanceHeight) == HwpParagraphLayout.cachedParagraphHeight(valid)
            expect(extent.advanceHeight).to(beCloseTo(31.00, within: 0.001))

            let reversed = try HwpSynthetic.lineSegParagraph(
                "가나", segments: [(location: 1600, height: 1000), (location: 0, height: 1000)]
            )
            expect(HwpParagraphLayout.cachedLineExtent(reversed)).to(beNil())
            expect(HwpParagraphLayout.cachedParagraphHeight(reversed)).to(beNil())
            let uncached = try HwpSynthetic.textParagraph("가")
            expect(HwpParagraphLayout.cachedLineExtent(uncached)).to(beNil())
        }
    }

    private extension HwpTableCachedRowHeightTests {
        func layout() -> HwpTableLayout {
            HwpTableLayout(fontResolver: .testDeterministic)
        }

        struct LayoutFailure: Error {}

        func layout(_ table: CoreHwp.HwpTable) throws -> HwpTableFrame {
            let result = layout().layout(table: table, availableWidth: 400, index: index())
            guard case let .success(frame) = result else {
                XCTFail("expected table layout success")
                throw LayoutFailure()
            }
            return frame
        }

        /// `authoredHeights[r]`를 r행 모든 셀의 저작 높이로 둔 표.
        func layoutRows(
            authoredHeights: [UInt32],
            cells: [[[CoreHwp.HwpParagraph]]]
        ) throws -> HwpTableFrame {
            var cellArray: [CoreHwp.HwpTableCell] = []
            for (row, columns) in cells.enumerated() {
                for (column, paragraphs) in columns.enumerated() {
                    cellArray.append(cell(
                        row: row, column: column, height: authoredHeights[row],
                        paragraphs: paragraphs
                    ))
                }
            }
            return try layout(CoreHwp.HwpTable(
                property: tableProperty(rowCount: cells.count, columnCount: cells[0].count),
                cellArray: cellArray
            ))
        }

        func oneLine() throws -> CoreHwp.HwpParagraph {
            try lineParagraph(lines: 1)
        }

        /// 줄 1000·줄 간격 600 (`HwpSynthetic.lineSegParagraph` 기본)의 `lines`줄 문단 —
        /// 줄 위치는 전진량 1600씩 누적한다.
        func lineParagraph(lines: Int) throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph(
                String(repeating: "가", count: lines),
                segments: (0 ..< lines).map { (location: Int32($0 * 1600), height: 1000) }
            )
        }

        /// 실물(numbering-sequence·noori)과 같은 안쪽 여백 — 좌우 510·위아래 141.
        func tableProperty(rowCount: Int, columnCount: Int) -> CoreHwp.HwpTableProperty {
            var rowSize = Data()
            for _ in 0 ..< rowCount {
                withUnsafeBytes(of: UInt16(columnCount).littleEndian) {
                    rowSize.append(contentsOf: $0)
                }
            }
            return CoreHwp.HwpTableProperty(
                property: 0,
                rowCount: UInt16(rowCount),
                columnCount: UInt16(columnCount),
                cellSpacing: 0,
                leftInnerMargin: 510,
                rightInnerMargin: 510,
                topInnerMargin: 141,
                bottomInnerMargin: 141,
                rowSize: [UInt8](rowSize),
                borderFillId: 0,
                validZoneInfoSize: nil,
                zonePropertyArray: nil,
                rawPayload: Data(),
                rawTrailing: Data()
            )
        }

        func cell(
            row: Int,
            column: Int,
            rowSpan: Int = 1,
            height: UInt32,
            paragraphs: [CoreHwp.HwpParagraph]
        ) -> CoreHwp.HwpTableCell {
            var cell = HwpSynthetic.tableCell(
                row: row, column: column, width: 20000, height: height, paragraphs: paragraphs
            )
            cell.header.cellProperty?.rowSpan = UInt16(rowSpan)
            return cell
        }

        /// 문단 위/아래 간격은 표 43 여백 계열의 1/2 단위 — 800 → 4pt, 400 → 2pt.
        func index(spacingTop: Int32 = 0, spacingBottom: Int32 = 0) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0,
                    marginLeft: 0,
                    paragraphSpacingTop: spacingTop,
                    paragraphSpacingBottom: spacingBottom,
                    tabDefId: 0,
                    lineSpacing2: 160
                )],
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
    }
#endif
