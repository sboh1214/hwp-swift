@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 번호 위치 (pgNumPos, 표 147/148)와 쪽 감추기 (pghd, 표 145) 렌더 검증
    final class HwpPaginatorPageNumberTests: XCTestCase {
        func testPageNumberEmittedOnEveryPage() async throws {
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            for pageIndex in 0 ..< totalPages {
                let page = try await paginator.page(at: pageIndex)
                expect(self.pageNumberTexts(of: page)).to(
                    contain("- \(pageIndex + 1) -"),
                    description: "page \(pageIndex + 1)에 쪽 번호가 없다"
                )
            }
        }

        func testPageNumberUsesNumberFormatAndDecorations() async throws {
            // 로마 소문자 (표 134 코드 3) + 앞/뒤 장식 '-'
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(
                        numberFormat: 3,
                        displayPosition: 5,
                        headDecoration: "-",
                        tailDecoration: "-"
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)

            expect(self.pageNumberTexts(of: firstPage)).to(contain("-i-"))
            expect(self.pageNumberTexts(of: secondPage)).to(contain("-ii-"))
        }

        func testPageHideSuppressesPageNumberOnControlPage() async throws {
            // 첫 문단의 pghd (0x20)는 1페이지 쪽 번호만 감춘다 (헌법주석 표지 구조)
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                    HwpSynthetic.pageHideControl(mask: 0x20),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            let firstPage = try await paginator.page(at: 0)
            expect(self.pageNumberTexts(of: firstPage)).to(
                beEmpty(),
                description: "감춘 페이지에 쪽 번호가 있다"
            )
            let secondPage = try await paginator.page(at: 1)
            expect(self.pageNumberTexts(of: secondPage)).to(contain("- 2 -"))
        }

        func testPageHideSuppressesHeaderAndFooterOnControlPage() async throws {
            let header = HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: [try HwpSynthetic.textParagraph("반복 머리말")]
            )
            let footer = HwpSynthetic.listControl(
                ctrlId: .footer,
                paragraphs: [try HwpSynthetic.textParagraph("반복 꼬리말")]
            )
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .header(header),
                    .footer(footer),
                    HwpSynthetic.pageHideControl(mask: 0x03),
                ]
            )

            let totalPages = await paginator.totalPages()
            expect(totalPages) >= 2

            let firstTexts = try await allTexts(of: paginator, pageIndex: 0)
            expect(firstTexts.contains { $0.contains("반복 머리말") }).to(beFalse())
            expect(firstTexts.contains { $0.contains("반복 꼬리말") }).to(beFalse())

            let secondTexts = try await allTexts(of: paginator, pageIndex: 1)
            expect(secondTexts.contains { $0.contains("반복 머리말") }).to(beTrue())
            expect(secondTexts.contains { $0.contains("반복 꼬리말") }).to(beTrue())
        }

        func testNewPageNumberResetsLogicalNumber() async throws {
            // nwno (kind 0 쪽, number 9): 컨트롤이 있는 페이지부터 9로 표시
            let paginator = try makePaginator(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
                ],
                leadingBodyParagraphs: [
                    HwpSynthetic.markerParagraph(
                        control: HwpSynthetic.newNumberControl(kind: 0, number: 9)
                    ),
                ]
            )

            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)

            expect(self.pageNumberTexts(of: firstPage)).to(contain("- 9 -"))
            expect(self.pageNumberTexts(of: secondPage)).to(contain("- 10 -"))
        }
    }

    private extension HwpPaginatorPageNumberTests {
        func makePaginator(
            firstParagraphControls: [CoreHwp.HwpCtrlId],
            leadingBodyParagraphs: [CoreHwp.HwpParagraph] = []
        ) throws -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: firstParagraphControls,
                bodyParagraphs: leadingBodyParagraphs + (try (0 ..< 30).map {
                    try HwpSynthetic.textParagraph("본문 문단 \($0)")
                })
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 본문 밖 (콘텐츠 아래/위 밴드)에 있는 텍스트 블록의 전체 문자열 =
        /// 쪽 번호 후보. 본문 텍스트 ("본문 문단 3")와 구분하기 위해
        /// 콘텐츠 프레임 밖의 블록만 모은다.
        func pageNumberTexts(of page: HwpPage?) -> [String] {
            guard let page else { return [] }
            let contentTop = page.margins.top
            let contentBottom = page.size.height - page.margins.bottom
            return page.blocks.compactMap { block -> String? in
                guard block.kind == .text,
                      let text = block.attributedString?.string,
                      block.frame.minY >= contentBottom - 0.5
                      || block.frame.maxY <= contentTop + 0.5
                else { return nil }
                return text
            }
        }

        func allTexts(of paginator: HwpPaginator, pageIndex: Int) async throws -> [String] {
            let page = try await paginator.page(at: pageIndex)
            return (page?.blocks ?? []).compactMap(\.attributedString?.string)
        }
    }
#endif
