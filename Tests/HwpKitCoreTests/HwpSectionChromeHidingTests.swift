@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 구역 정의 (표 132)의 감추기 플래그는 pageHide 컨트롤 (표 145)과 같은
    /// 효과로 크롬을 억제해야 한다 — 구역 내내 유지되므로 페이지가 넘어가도
    /// 다시 나타나지 않는다 (R70 #2).
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
                bodyParagraphs: [try HwpSynthetic.textParagraph("본문")]
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        private func pageNumberBlockCount(_ paginator: HwpPaginator) async throws -> Int {
            var count = 0
            let totalPages = await paginator.totalPages()
            for pageIndex in 0 ..< totalPages {
                guard let page = try await paginator.page(at: pageIndex) else { continue }
                count += page.blocks.filter { $0.role == .pageChrome }.count
            }
            return count
        }

        func testSectionHideFlagSuppressesPageNumberChrome() async throws {
            let visible = try await pageNumberBlockCount(paginator(hidePageNumber: false))
            let hidden = try await pageNumberBlockCount(paginator(hidePageNumber: true))

            expect(visible) > 0
            expect(hidden) == 0
        }
    }
#endif
