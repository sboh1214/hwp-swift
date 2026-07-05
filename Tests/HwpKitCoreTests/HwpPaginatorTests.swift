@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    final class HwpPaginatorTests: XCTestCase {
        func testEmptySectionsReturnsSingleEmptyPage() async throws {
            let paginator = HwpPaginator(
                sections: [],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            expect(page).notTo(beNil())
            expect(page?.blocks) == []
            expect(page?.pageNumber) == 1
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 1
        }

        func testBlankFileReturnsOnePage() async throws {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)
            let totalPages = await paginator.totalPages()
            let secondPage = try await paginator.page(at: 1)

            expect(page).notTo(beNil())
            expect(totalPages) == 1
            expect(secondPage).to(beNil())
        }

        func testMissingLineSegmentFallback() async throws {
            let file = CoreHwp.HwpFile()
            var section = file.sectionArray[0]
            section.paragraph[0].paraLineSeg.paraLineSegInternalArray = []
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)

            expect(page).notTo(beNil())
            expect(page?.pageNumber) == 1
        }

        func testActiveHeaderFooterRepeatOnEveryPage() async throws {
            let header = HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: [try HwpSynthetic.textParagraph("반복 머리말")]
            )
            let footer = HwpSynthetic.listControl(
                ctrlId: .footer,
                paragraphs: [try HwpSynthetic.textParagraph("반복 꼬리말")]
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                    .header(header),
                    .footer(footer),
                ],
                bodyParagraphs: try (0 ..< 30).map {
                    try HwpSynthetic.textParagraph("본문 문단 \($0)")
                }
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            for pageIndex in 0 ..< totalPages {
                let page = try await paginator.page(at: pageIndex)
                let texts = page?.blocks.compactMap(\.attributedString?.string) ?? []
                expect(texts.contains { $0.contains("반복 머리말") }).to(
                    beTrue(),
                    description: "page \(pageIndex)에 머리말이 없다"
                )
                expect(texts.contains { $0.contains("반복 꼬리말") }).to(
                    beTrue(),
                    description: "page \(pageIndex)에 꼬리말이 없다"
                )
            }
        }

        func testHeaderScopeRespectsEvenOddPages() async throws {
            // 표 141: 1 = 짝수 쪽만, 2 = 홀수 쪽만
            let evenHeader = HwpSynthetic.listControl(
                ctrlId: .header,
                property: 1,
                paragraphs: [try HwpSynthetic.textParagraph("짝수쪽 머리말")]
            )
            let oddHeader = HwpSynthetic.listControl(
                ctrlId: .header,
                property: 2,
                paragraphs: [try HwpSynthetic.textParagraph("홀수쪽 머리말")]
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(CoreHwp.HwpColumn()),
                    .header(evenHeader),
                    .header(oddHeader),
                ],
                bodyParagraphs: try (0 ..< 30).map {
                    try HwpSynthetic.textParagraph("본문 문단 \($0)")
                }
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            for pageIndex in 0 ..< totalPages {
                let page = try await paginator.page(at: pageIndex)
                let texts = page?.blocks.compactMap(\.attributedString?.string) ?? []
                let expected = (pageIndex + 1).isMultiple(of: 2) ? "짝수쪽 머리말" : "홀수쪽 머리말"
                let unexpected = (pageIndex + 1).isMultiple(of: 2) ? "홀수쪽 머리말" : "짝수쪽 머리말"
                expect(texts.contains { $0.contains(expected) }).to(
                    beTrue(),
                    description: "page \(pageIndex + 1)에 \(expected)이 없다"
                )
                expect(texts.contains { $0.contains(unexpected) }).to(
                    beFalse(),
                    description: "page \(pageIndex + 1)에 \(unexpected)이 있다"
                )
            }
        }

        func testLongFootnotesCarryOverToNextPageWithoutClipping() async throws {
            let longText = String(repeating: "긴 각주 본문 문장. ", count: 20)
            let footnoteParagraphs = try (1 ... 4).map {
                try HwpSynthetic.textParagraph("각주\($0) \(longText)")
            }
            let footnote = HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: footnoteParagraphs
            )
            var host = try HwpSynthetic.textParagraph("각주가 달린 본문 문단")
            host.ctrlHeaderArray = [.footnote(footnote)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 40000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            var placedNumbers: [Int] = []
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                let contentMaxY = page.size.height - page.margins.bottom
                for block in page.blocks where block.kind == .footnote {
                    guard case let .footnote(footnoteBlock) = block.payload else { continue }
                    placedNumbers.append(footnoteBlock.number)
                    expect(block.frame.maxY).to(
                        beLessThanOrEqualTo(contentMaxY + 0.5),
                        description: "page \(pageIndex + 1) 각주가 하단 여백을 침범한다"
                    )
                }
            }
            // 각주 4개가 잘리지 않고 전부 (순서대로) 배치되어야 한다.
            expect(placedNumbers) == [1, 2, 3, 4]
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
                if case let .drawText(attributed, _, _) = command { return attributed.string }
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

        func testLazyDoesNotComputeAllPagesUpFront() async throws {
            let file = CoreHwp.HwpFile()
            let paginator = HwpPaginator(
                sections: file.sectionArray,
                index: HwpIndex(from: file),
                fontResolver: .testDeterministic
            )

            let initialCacheCount = await paginator.cachedPages.count
            expect(initialCacheCount) == 0

            _ = try await paginator.page(at: 0)

            let cachedPages = await paginator.cachedPages
            expect(cachedPages.count) == 1
            expect(cachedPages[0]).notTo(beNil())
        }
    }
#endif
