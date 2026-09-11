@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 미주 문서/구역 끝 배치 페이지네이션 통합 테스트
    final class HwpPaginatorEndnoteTests: XCTestCase {
        func testEndnotesPlaceOnLastPageWithSeparateNumbering() async throws {
            let footnote = HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [try HwpSynthetic.textParagraph("각주 본문")]
            )
            let endnote = HwpSynthetic.listControl(
                ctrlId: .endnote,
                paragraphs: [try HwpSynthetic.textParagraph("미주 본문")]
            )
            var host = try HwpSynthetic.textParagraph("각주와 미주가 달린 문단")
            host.ctrlHeaderArray = [.footnote(footnote), .endnote(endnote)]
            var bodyParagraphs: [CoreHwp.HwpParagraph] = [host]
            bodyParagraphs.append(contentsOf: try (0 ..< 40).map {
                try HwpSynthetic.textParagraph("본문 채움 \($0)")
            })
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
            expect(totalPages) >= 2

            var footnotePage: Int?
            var endnotePage: Int?
            var endnoteNumber: Int?
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks where block.kind == .footnote {
                    guard case let .footnote(note) = block.payload else { continue }
                    let text = note.paragraphs.first?.attributedString.string ?? ""
                    if text.contains("각주 본문") {
                        footnotePage = pageIndex
                        expect(note.number) == 1
                    }
                    if text.contains("미주 본문") {
                        endnotePage = pageIndex
                        endnoteNumber = note.number
                    }
                }
            }
            // 각주는 참조 페이지 (첫 페이지), 미주는 마지막 페이지.
            expect(footnotePage) == 0
            expect(endnotePage) == totalPages - 1
            // 미주 번호는 각주와 분리된 카운터로 1부터 시작한다.
            expect(endnoteNumber) == 1
        }

        func testSectionEndEndnotesPlaceBeforeNextSection() async throws {
            // 표 134 bits 8-9 == 1: 구역의 마지막에 미주 배치
            var sectionDef = HwpSynthetic.sectionDef(pageHeight: 40000)
            sectionDef.endNoteShape.property = 1 << 8
            let endnote = HwpSynthetic.listControl(
                ctrlId: .endnote,
                paragraphs: [try HwpSynthetic.textParagraph("1구역 미주")]
            )
            var host = try HwpSynthetic.textParagraph("1구역 본문")
            host.ctrlHeaderArray = [.endnote(endnote)]
            var firstSection = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(sectionDef),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host]
            )
            let secondSection = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 40000)),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("2구역 본문")]
            )
            let paginator = HwpPaginator(
                sections: [firstSection, secondSection],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            var endnotePage: Int?
            var secondSectionPage: Int?
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                for block in page.blocks {
                    let text = block.attributedString?.string ?? ""
                    if block.kind == .footnote, text.contains("1구역 미주") {
                        endnotePage = pageIndex
                    }
                    if block.kind == .text, text.contains("2구역 본문") {
                        secondSectionPage = pageIndex
                    }
                }
            }
            expect(endnotePage).toNot(beNil())
            expect(secondSectionPage).toNot(beNil())
            // 구역-끝 미주는 다음 구역이 시작되기 전 페이지에 있다.
            if let endnotePage, let secondSectionPage {
                expect(endnotePage) < secondSectionPage
            }
        }

        /// 구역 끝 미주의 "새 쪽" 판정은 배치와 같은 높이로 한다 (#165 리뷰): 한 문단짜리 미주는
        /// 마지막 줄의 줄 간격을 빼면 남은 자리에 들어가는데, 그 간격을 더한 높이로 재면 들어가는
        /// 미주를 새 쪽으로 옮긴다.
        func testSectionEndEndnoteStaysWhenItFitsByItsNoteEndHeight() async throws {
            // 쪽 153.2pt → 본문 자리 54pt; 구역 정의 문단과 본문 한 줄(16pt씩) 뒤 22pt가 남는다.
            // 두 줄 미주는 줄 간격을 뺀 20.72pt론 들어가고 더한 23.44pt론 안 들어간다.
            var sectionDef = HwpSynthetic.sectionDef(pageHeight: 15320)
            sectionDef.endNoteShape.property = 1 << 8
            var endnoteParagraph = HwpSynthetic.noteParagraph(
                " 미주 첫 줄\n미주 둘째 줄",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 2, decorationTail: ")")
            )
            endnoteParagraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                FootnoteContinuationSupport.lineSegPayload(
                    FootnoteContinuationSupport.noteLines([0, 1172])
                )
            )
            let endnote = HwpSynthetic.listControl(ctrlId: .endnote, paragraphs: [endnoteParagraph])
            var host = try HwpSynthetic.textParagraph("1구역 본문")
            host.ctrlHeaderArray = [.endnote(endnote)]
            let firstSection = HwpSynthetic.section(
                firstParagraphControls: [.section(sectionDef), .column(CoreHwp.HwpColumn())],
                bodyParagraphs: [host]
            )
            let secondSection = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 15320)), .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("2구역 본문")]
            )
            let paginator = HwpPaginator(
                sections: [firstSection, secondSection],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let page = try await paginator.page(at: 0)
            let firstPage = try XCTUnwrap(page)
            let body = try XCTUnwrap(firstPage.blocks.first {
                $0.kind == .text && ($0.attributedString?.string ?? "").contains("1구역 본문")
            })
            let endnoteBlock = try XCTUnwrap(firstPage.blocks.first {
                $0.kind == .footnote && ($0.attributedString?.string ?? "").contains("미주 첫 줄")
            })
            expect(endnoteBlock.frame.minY) >= body.frame.maxY - 0.01
            expect(endnoteBlock.frame.maxY) <= firstPage.size.height - firstPage.margins.bottom + 0.01
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
        }
    }
#endif
