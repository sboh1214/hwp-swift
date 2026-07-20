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
    }
#endif
