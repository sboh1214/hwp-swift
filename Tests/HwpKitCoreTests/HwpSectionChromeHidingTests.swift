@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 구역 정의 (표 132)의 감추기 플래그는 pageHide 컨트롤 (표 145)과 같은
    /// 효과로 크롬을 억제하되, 구역의 **첫 쪽**에만 적용된다
    /// (HwpSectionDefProperty 문서) — 2쪽부터는 되살아난다 (R70 #2, R71 #1).
    final class HwpSectionChromeHidingTests: XCTestCase {
        private func paginator(hidePageNumber: Bool) throws -> HwpPaginator {
            var sectionDef = HwpSynthetic.sectionDef()
            sectionDef.propertyInfo.hidePageNumberPosition = hidePageNumber
            var position = CoreHwp.HwpPageNumberPosition()
            position.propertyInfo.displayPosition = 5 // 표 148: 아래 가운데
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(sectionDef),
                    .pageNumberPosition(position),
                ],
                bodyParagraphs: [
                    try HwpSynthetic.textParagraph("첫 쪽"),
                    try HwpSynthetic.pageBreakParagraph("둘째 쪽"),
                ]
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 페이지별 크롬(쪽 번호) 블록 수
        private func chromeCounts(_ paginator: HwpPaginator) async throws -> [Int] {
            var counts: [Int] = []
            let totalPages = await paginator.totalPages()
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                counts.append(page.blocks.filter { $0.role == .pageChrome }.count)
            }
            return counts
        }

        func testSectionHideFlagSuppressesChromeOnFirstPageOnly() async throws {
            let visible = try await chromeCounts(paginator(hidePageNumber: false))
            let hidden = try await chromeCounts(paginator(hidePageNumber: true))

            expect(visible.count) >= 2
            expect(visible.allSatisfy { $0 > 0 }) == true
            // 첫 쪽만 감추고 둘째 쪽부터는 종전대로 방출한다.
            expect(hidden.first) == 0
            expect(hidden.dropFirst().allSatisfy { $0 > 0 }) == true
        }
    }
#endif
