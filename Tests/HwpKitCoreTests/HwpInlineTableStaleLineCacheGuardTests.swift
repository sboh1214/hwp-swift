import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 낡은 줄 캐시 판정이 **신선한 캐시를 버리지 않는** 경계 (#214 PR 리뷰) — 판정은 우리 표
    /// 레이아웃·CT 높이를 한글 캐시와 견주므로, 그 둘을 믿을 수 없는 자리에서는 캐시를 따른다.
    final class HwpInlineTableStaleLineCacheGuardTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport

        /// 흐름 문서의 호스트(줄 캐시 한 줄, 높이 `lineHeight` HWPUNIT)와 뒤 문단 — 호스트 블록과 뒤
        /// 문단 블록을 돌려준다.
        private static func flowBlocks(
            table: CoreHwp.HwpTable,
            lineHeight: Int32
        ) async throws -> (host: AnyHwpBlock, tail: AnyHwpBlock) {
            var host = Support.host(table: table, suffix: " 뒤")
            host.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "캐시", segments: [(location: 0, height: lineHeight)]
            ).paraLineSeg
            let pages = try await InlineControlFragmentSupport.pages(
                of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: [
                    host, try HwpSynthetic.textParagraph("뒤 문단"),
                ])
            )
            let page = try XCTUnwrap(pages.first)
            return (
                try XCTUnwrap(Support.textBlock(on: page, containing: " 뒤")),
                try XCTUnwrap(Support.textBlock(on: page, containing: "뒤 문단"))
            )
        }

        /// 1열 2행을 한 셀로 합친 표(20pt) — 둘째 행에서 시작하는 셀이 없어 우리 레이아웃은 첫 행에
        /// 기본 높이(안쪽 여백, 여기서는 1pt 하한)를 얹어 21pt로 잡는다. 한글이 저장한 캐시(표를 담는
        /// 20pt 줄)는 신선하므로 판정에서 빼 캐시 높이(20 + 6pt)를 따른다 — 견주면 1pt를 낡았다고 보고
        /// 뒤 문단을 민다.
        func testRowsCoveredOnlyByMergedCellsDoNotInvalidateAFreshCache() async throws {
            var table = try Support.staleTable(rows: 2, instanceId: 32, authoredRowHeight: 1000)
            table.cellArray.removeLast()
            table.cellArray[0].header.cellProperty?.rowSpan = 2
            table.cellArray[0].header.cellProperty?.height = 2000
            table.commonCtrlProperty.height = 2000
            expect(HwpParagraphLayout.rowsHaveOwnCells(table)) == false
            let blocks = try await Self.flowBlocks(table: table, lineHeight: 2000)
            expect(blocks.host.frame.height).to(beCloseTo(26, within: 0.01))
            expect(blocks.tail.frame.minY).to(beCloseTo(blocks.host.frame.maxY, within: 0.01))
            // 대조군: 행마다 셀이 있는 같은 높이의 표는 판정 대상이다.
            expect(HwpParagraphLayout.rowsHaveOwnCells(
                try Support.staleTable(rows: 2, instanceId: 33, authoredRowHeight: 1000)
            )) == true
        }

        /// 공통 폭이 0인 표는 줄이 자리를 예약하지 못해(`inlineObjectReservation`) CT 줄이 글자
        /// 높이(16pt)뿐이다 — 표를 실은 30pt 캐시 줄이 100pt 표보다 낮아도 CT가 더 낮으므로 캐시를
        /// 버리지 않는다. 버리면 블록이 36 → 16pt로 줄어 뒤 문단이 표를 더 덮는다.
        func testStaleCacheIsKeptWhenTheMeasuredParagraphIsNotTaller() async throws {
            var table = try Support.staleTable(rows: 10, instanceId: 34)
            table.commonCtrlProperty.width = 0
            let blocks = try await Self.flowBlocks(table: table, lineHeight: 3000)
            expect(blocks.host.frame.height).to(beCloseTo(36, within: 0.01))
            expect(blocks.tail.frame.minY).to(beCloseTo(blocks.host.frame.maxY, within: 0.01))
        }
    }
#endif
