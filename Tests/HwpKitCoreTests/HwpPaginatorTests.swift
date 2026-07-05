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
