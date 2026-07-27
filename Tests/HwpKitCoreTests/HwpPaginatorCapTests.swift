@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpPaginatorCapTests: XCTestCase {
        /// 한 문단이 페이지 상한을 넘겨 이어져도 상한에서 종료한다 — cap 도달
        /// 후 cacheCurrentPage는 밴드/커서를 리셋하지 않으므로 분할 루프에
        /// 탈출이 없으면 같은 lineIndex 재시도가 무한 루프다 (R36 #1).
        func testPaginationTerminatesAtPageCapForOverflowingParagraph() async throws {
            let text = String(repeating: "가나다라 마바사아 자차카타 파하 ", count: 2000)
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph(text)]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            await paginator.overrideMaximumPages(1)
            var pages = 0
            while try await paginator.page(at: pages) != nil {
                pages += 1
            }
            expect(pages) == 1
        }

        /// 병렬 page 요청은 직렬화된다 — computeNextPage 재진입 교차 실행이
        /// 문단 배치를 오염시키지 않아, 동시 소비 결과가 순차 소비와 동일하다
        /// (R38 #1).
        func testConcurrentPageRequestsMatchSequentialPagination() async throws {
            func makePaginator() throws -> HwpPaginator {
                let text = String(repeating: "가나다라 마바사아 자차카타 파하 ", count: 800)
                let section = HwpSynthetic.section(
                    firstParagraphControls: [
                        .section(HwpSynthetic.sectionDef()),
                        .column(CoreHwp.HwpColumn()),
                    ],
                    bodyParagraphs: [try HwpSynthetic.textParagraph(text)]
                )
                return HwpPaginator(
                    sections: [section],
                    index: HwpIndex(from: CoreHwp.HwpFile()),
                    fontResolver: .testDeterministic
                )
            }
            let sequential = try makePaginator()
            var expected: [Int] = []
            var index = 0
            while let page = try await sequential.page(at: index) {
                expected.append(page.blocks.count)
                index += 1
            }
            expect(expected.count) >= 2

            let concurrent = try makePaginator()
            async let last = concurrent.page(at: expected.count - 1)
            async let first = concurrent.page(at: 0)
            _ = try await (first, last)
            var actual: [Int] = []
            var verifyIndex = 0
            while let page = try await concurrent.page(at: verifyIndex) {
                actual.append(page.blocks.count)
                verifyIndex += 1
            }
            expect(actual) == expected
        }
    }
#endif
