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

        func testAbsoluteLineSegmentLocationsAreRelativized() async throws {
            // 한/글 2007 계열 저장본: lineLocation이 문단-상대 (0 시작)가 아니라
            // 페이지 내 누적 절대 y로 기록된다. 문단 높이는 세그먼트 상대 높이
            // (max(loc+h) − 첫 loc)여야 하며, 절대 y를 그대로 쓰면 문단 하나가
            // 페이지를 통째로 차지해 페이지가 폭발한다.
            let bodyParagraphs = try (0 ..< 10).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "절대 좌표 문단 \(index)",
                    segments: [(location: Int32(2720 + index * 2000), height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: bodyParagraphs
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 1

            let page = try await paginator.page(at: 0)
            let textBlocks = (page?.blocks ?? []).filter { $0.kind == .text }
            expect(textBlocks.count) == 11 // 첫 문단 + 본문 10
            for block in textBlocks where block.attributedString?.string.contains("절대") == true {
                expect(block.frame.height).to(beCloseTo(15, within: 0.01))
            }
        }

        func testRelativeLineSegmentHeightsKeepLegacyBehavior() async throws {
            // 문단-상대 (첫 loc == 0) 캐시는 기존과 동일하게 max(loc+h)가 높이다.
            let paragraph = try HwpSynthetic.lineSegParagraph(
                "상대 좌표 문단",
                segments: [(location: 0, height: 1000), (location: 1000, height: 1000)]
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let page = try await paginator.page(at: 0)
            let block = page?.blocks.first {
                $0.attributedString?.string.contains("상대") == true
            }
            expect(block?.frame.height).to(beCloseTo(20, within: 0.01))
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
            // 실제 HWP 구조: 각주 하나 = 각주 컨트롤 하나 (번호도 컨트롤당 1씩)
            let footnotes = try (1 ... 4).map { number in
                HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [try HwpSynthetic.textParagraph("각주\(number) \(longText)")]
                )
            }
            var host = try HwpSynthetic.textParagraph("각주가 달린 본문 문단")
            host.ctrlHeaderArray = footnotes.map { .footnote($0) }
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
