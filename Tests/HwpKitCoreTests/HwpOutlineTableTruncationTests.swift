@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 표 행 절단 기록이 **다른 표로 새지 않는다** (#77).
    ///
    /// 절단 자체(방출되지 않은 행의 앵커를 빼는 것)는
    /// `HwpOutlineContainerDepthTests`가 보고, 여기서는 그 기록의 **적용 대상**을
    /// 잠근다 — `instanceId`는 "문서 내 고유"를 표방하지만 파서가 중복을 거부하지
    /// 않고 공개 모델의 기본값이 0이라, id로만 조회하면 잘린 표가 남긴 상한이 뒤의
    /// **온전히 렌더된** 표에 적용돼 그려진 행의 책갈피가 조용히 사라진다.
    final class HwpOutlineTableTruncationTests: XCTestCase {
        /// 세그먼트 상한 1에서 첫 행만 방출되는 표 — 행 하나가 한 쪽을 채운다.
        private func truncatedTable() throws -> CoreHwp.HwpTable {
            HwpSynthetic.table(
                cellWidth: 30000,
                rowHeights: [16000, 16000, 16000],
                cellParagraphs: [
                    try [anchoredCell("A1", "A1 앵커")],
                    try [anchoredCell("A2", "A2 앵커")],
                    try [anchoredCell("A3", "A3 앵커")],
                ]
            )
        }

        /// 두 행이 한 세그먼트에 들어가는 표 — 같은 상한에서도 온전히 렌더된다.
        private func fullyRenderedTable() throws -> CoreHwp.HwpTable {
            HwpSynthetic.table(
                cellWidth: 30000,
                rowHeights: [3000, 3000],
                cellParagraphs: [
                    try [anchoredCell("B1", "B1 앵커")],
                    try [anchoredCell("B2", "B2 앵커")],
                ]
            )
        }

        /// 잘린 표 **뒤 문단**의 온전한 표는 두 행의 앵커를 모두 낸다.
        /// 두 표의 `instanceId`는 공개 기본값 그대로 둘 다 0이다.
        func testRowLimitOfATruncatedTableDoesNotLeakToALaterTable() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try hostParagraph("본문 A", tables: [try truncatedTable()]),
                    try hostParagraph("본문 B", tables: [try fullyRenderedTable()]),
                ],
                index: HwpSynthetic.outlineIndex(),
                pageHeight: 20000
            )
            await paginator.overrideMaximumTableSegments(1)

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let rendered = try await renderedCellTexts(of: paginator)

            // 뒤 표의 2행은 **실제로 그려진다** — 목록에서만 빠지면 유실이다.
            expect(rendered).to(contain("B2"))
            // 잘린 표의 A2·A3는 계속 빠져야 한다 (절단 규약 자체는 그대로).
            expect(outline.map(\.title)) == ["A1 앵커", "B1 앵커", "B2 앵커"]
        }

        /// **같은 문단**에 나란히 붙은 표에도 새지 않는다 — 기록 수명을 문단으로
        /// 줄이는 것만으로는 막히지 않는 축이라 앞 테스트와 짝을 이룬다.
        func testRowLimitOfATruncatedTableDoesNotLeakToASiblingTable() async throws {
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [
                    try hostParagraph(
                        "본문", tables: [try truncatedTable(), try fullyRenderedTable()]
                    ),
                ],
                index: HwpSynthetic.outlineIndex(),
                pageHeight: 20000
            )
            await paginator.overrideMaximumTableSegments(1)

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            let rendered = try await renderedCellTexts(of: paginator)

            expect(rendered).to(contain("B2"))
            expect(outline.map(\.title)) == ["A1 앵커", "B1 앵커", "B2 앵커"]
        }

        private func anchoredCell(
            _ text: String, _ anchor: String
        ) throws -> [CoreHwp.HwpParagraph] {
            var paragraph = try HwpSynthetic.styledParagraph(text)
            paragraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl(anchor)]
            return [paragraph]
        }

        private func hostParagraph(
            _ text: String, tables: [CoreHwp.HwpTable]
        ) throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.styledParagraph(text)
            host.ctrlHeaderArray = tables.map { .table($0) }
            return host
        }

        /// 페이지에 실제로 그려진 표 셀 텍스트 — 목록과 대조할 렌더 실물이다.
        private func renderedCellTexts(of paginator: HwpPaginator) async throws -> [String] {
            var texts: [String] = []
            let pageCount = await paginator.totalPages()
            for index in 0 ..< pageCount {
                guard let page = try await paginator.page(at: index) else { continue }
                for block in page.blocks {
                    guard case let .table(frame) = block.payload else { continue }
                    texts.append(contentsOf: frame.rows
                        .flatMap(\.cells)
                        .flatMap(\.paragraphs)
                        .map(\.attributedString.string))
                }
            }
            return texts
        }
    }
#endif
