@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 표/다단 흐름 (분할·이월·배분) 페이지네이션 통합 테스트
    final class HwpPaginatorFlowTests: XCTestCase {
        func testTreatAsCharObjectAnchorsToItsLine() async throws {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "앞 텍스트 ", suffix: " 뒤")
            host.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.inlineShapeObject(
                width: 6000,
                height: 3000,
                instanceId: 42
            ))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            guard let page = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            guard let textBlock = page.blocks.first(where: {
                $0.kind == .text && $0.attributedString?.string.contains("앞 텍스트") == true
            }) else {
                fail("호스트 문단 블록이 없다")
                return
            }
            guard let objectBlock = page.blocks.first(where: {
                $0.kind == .shape && $0.source?.controlInstanceId == 42
            }) else {
                fail("인라인 개체 블록이 없다")
                return
            }

            // 개체(30pt)가 줄에서 가장 크므로 개체 위 == FFFC가 있는 첫 줄 위 == 블록 위.
            expect(objectBlock.frame.minY).to(beCloseTo(textBlock.frame.minY, within: 1))
            // "앞 텍스트 " 글리프 뒤 (줄 중간)에 배치된다.
            expect(objectBlock.frame.minX) > textBlock.frame.minX + 1
            expect(objectBlock.frame.height).to(beCloseTo(30, within: 0.5))
            expect(objectBlock.frame.width).to(beCloseTo(60, within: 0.5))
            // 줄 높이 보정 방식: 개체가 흐름 높이를 추가 소비하지 않는다
            // (문단 블록 높이가 이미 개체 높이를 포함).
            expect(textBlock.frame.height) >= 30
        }

        func testNestedTableCellTextAppearsInPaintList() async throws {
            let nested = HwpSynthetic.table(
                cellWidth: 8000,
                rowHeights: [2000],
                cellParagraphs: [[[try HwpSynthetic.textParagraph("중첩 셀 텍스트")]]]
            )
            var hostCellParagraph = try HwpSynthetic.textParagraph("바깥 셀 텍스트")
            hostCellParagraph.ctrlHeaderArray = [.table(nested)]
            let outer = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [10000],
                cellParagraphs: [[[hostCellParagraph]]]
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(outer)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            guard let page = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            // 바깥 표는 placeholder가 아니라 실제 표 블록으로 방출된다.
            expect(page.blocks.filter { $0.kind == .placeholder }).to(beEmpty())
            let tableBlocks = page.blocks.filter { $0.kind == .table }
            expect(tableBlocks.count) == 1

            let paintText = page.paintList.commands.compactMap { command -> String? in
                if case let .drawText(attributed, _, _) = command {
                    return attributed.string
                }
                return nil
            }.joined(separator: "\n")
            expect(paintText).to(contain("바깥 셀 텍스트"))
            expect(paintText).to(contain("중첩 셀 텍스트"))
        }

        func testOversizedRowSplitsAcrossPagesWithinContentBounds() async throws {
            // 콘텐츠 높이(~200pt)보다 큰 row (500pt) → 여러 페이지로 분할
            let table = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [50000],
                property: 2,
                cellParagraphs: [[[try HwpSynthetic.textParagraph("아주 큰 셀")]]]
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(table)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [tableHost]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            var totalTableHeight: CGFloat = 0
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                let contentMaxY = page.size.height - page.margins.bottom
                for block in page.blocks where block.kind == .table {
                    totalTableHeight += block.frame.height
                    expect(block.frame.maxY).to(
                        beLessThanOrEqualTo(contentMaxY + 0.5),
                        description: "page \(pageIndex + 1) 표 조각이 하단 여백을 침범한다"
                    )
                }
            }
            // 분할 조각 높이 합이 원본 row 높이(500pt)와 같아야 한다 (클립 없이 이월).
            expect(totalTableHeight).to(beCloseTo(500, within: 1))
        }

        func testPageBreakModeNoneMovesWholeTableToNextPage() async throws {
            let table = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [15000],
                property: 0, // 쪽 경계 나눔 없음
                cellParagraphs: [[[try HwpSynthetic.textParagraph("통째 표")]]]
            )
            var tableHost = try HwpSynthetic.textParagraph("")
            tableHost.ctrlHeaderArray = [.table(table)]
            var bodyParagraphs = try (0 ..< 8).map {
                try HwpSynthetic.textParagraph("본문 채움 \($0)")
            }
            bodyParagraphs.append(tableHost)
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: bodyParagraphs
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            var tableBlocks: [(page: Int, block: AnyHwpBlock)] = []
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.kind == .table {
                    tableBlocks.append((pageIndex, block))
                }
            }
            // 나누지 않는 표는 조각내지 않고 통째로 다음 페이지에 배치된다.
            expect(tableBlocks.count) == 1
            expect(tableBlocks.first?.page) == 1
            expect(tableBlocks.first?.block.frame.height).to(beCloseTo(150, within: 1))
        }

        func testTwoColumnFlowFillsSecondColumnBeforeNewPage() async throws {
            var twoColumn = CoreHwp.HwpColumn()
            twoColumn.property = CoreHwp.HwpColumnProperty(
                rawValue: 0,
                type: .general,
                count: 2,
                direction: .left,
                isSameWidth: true
            )
            twoColumn.spacing = 2000
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(twoColumn),
                ],
                bodyParagraphs: try (0 ..< 60).map {
                    try HwpSynthetic.textParagraph("다단 본문 문단 \($0)")
                }
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            guard let page = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            let contentMinX = page.margins.left
            let contentMaxX = page.size.width - page.margins.right
            let bodyBlocks = page.blocks.filter {
                $0.kind == .text && $0.attributedString?.string.contains("다단 본문") == true
            }
            let origins = Set(bodyBlocks.map(\.frame.minX))
            // 두 단이 채워졌으므로 서로 다른 x-origin이 존재한다.
            expect(origins.count) >= 2

            // 어떤 블록도 단 폭을 넘거나 콘텐츠 영역을 벗어나지 않는다.
            let columnWidth = (contentMaxX - contentMinX - 20) / 2
            for block in bodyBlocks {
                expect(block.frame.width).to(beLessThanOrEqualTo(columnWidth + 0.5))
                expect(block.frame.minX).to(beGreaterThanOrEqualTo(contentMinX - 0.5))
                expect(block.frame.maxX).to(beLessThanOrEqualTo(contentMaxX + 0.5))
            }

            // 두 단이 모두 찬 뒤에야 두 번째 페이지가 생긴다.
            expect(totalPages) >= 2
        }

        func testColumnBandRebalancesSoloParagraphAcrossColumns() async throws {
            // 단 하나에만 들어간 밴드가 닫힐 때 (다음 단 정의) 라인이 배분된다.
            var twoColumn = CoreHwp.HwpColumn()
            twoColumn.property = CoreHwp.HwpColumnProperty(
                rawValue: 0,
                type: .general,
                count: 2,
                direction: .left,
                isSameWidth: true
            )
            twoColumn.spacing = 2000
            var oneColumn = CoreHwp.HwpColumn()

            var longParagraph = try HwpSynthetic.textParagraph(
                String(repeating: "두 단으로 배분될 본문 문장. ", count: 20)
            )
            longParagraph.ctrlHeaderArray = [.column(twoColumn)]
            var closingParagraph = try HwpSynthetic.textParagraph("한 단 본문")
            closingParagraph.ctrlHeaderArray = [.column(oneColumn)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(oneColumn),
                ],
                bodyParagraphs: [longParagraph, closingParagraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            guard let page = try await paginator.page(at: 0) else {
                fail("첫 페이지가 없다")
                return
            }
            let balanced = page.blocks.filter {
                $0.kind == .text && $0.attributedString?.string.contains("배분될 본문") == true
            }
            // 라인이 두 단으로 나뉘어 서로 다른 x-origin 블록이 된다.
            expect(balanced.count) >= 2
            expect(Set(balanced.map(\.frame.minX)).count) >= 2
        }
    }
#endif
