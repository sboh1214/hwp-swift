@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 머리말·꼬리말 적용 범위(표 141)가 실제로 쪽을 가르는지 (#167).
    ///
    /// HWPX 매퍼는 `applyPageType`을 이 비트로 옮기는데, 매퍼 단위 테스트는
    /// 비트까지만 본다. 여기서는 조판까지 태워 홀수 쪽에만 그려지는지 확인한다 —
    /// 비트가 맞아도 크롬 빌더가 범위를 무시하면 그 자리에서 갈린다.
    final class HwpPageChromeApplyScopeTests: XCTestCase {
        func testOddScopeHeaderDrawsOnOddPagesOnly() async throws {
            let pages = try await chromeTexts(scope: .oddPagesOnly)
            expect(pages[0]) == ["머리말"]
            expect(pages[1]) == []
        }

        func testEvenScopeHeaderDrawsOnEvenPagesOnly() async throws {
            let pages = try await chromeTexts(scope: .evenPagesOnly)
            expect(pages[0]) == []
            expect(pages[1]) == ["머리말"]
        }

        func testBothScopeHeaderDrawsOnEveryPage() async throws {
            let pages = try await chromeTexts(scope: .bothPages)
            expect(pages[0]) == ["머리말"]
            expect(pages[1]) == ["머리말"]
        }

        /// 첫 두 쪽의 크롬 텍스트.
        private func chromeTexts(
            scope: CoreHwp.HwpHeaderFooterApplyScope
        ) async throws -> [[String]] {
            let paginator = paginator(scope: scope)
            var pages: [[String]] = []
            for index in 0 ..< 2 {
                // `XCTUnwrap`은 autoclosure라 await를 못 받는다 — 먼저 let에 받는다.
                let rendered = try await paginator.page(at: index)
                let page = try XCTUnwrap(rendered)
                pages.append(page.blocks
                    .filter { $0.role == .pageChrome && $0.kind == .text }
                    .compactMap { $0.attributedString?.string })
            }
            return pages
        }

        /// 머리말 컨트롤 하나 + 쪽 나눔 문단으로 2쪽을 만든다.
        private func paginator(
            scope: CoreHwp.HwpHeaderFooterApplyScope
        ) -> HwpPaginator {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .header(Self.headerControl(scope: scope)),
                ],
                bodyParagraphs: (try? HwpSynthetic.pageBreakParagraph("둘째 쪽"))
                    .map { [$0] } ?? []
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 표 140 payload를 HWPX 매퍼와 같은 모양으로 합성한 머리말 컨트롤.
        private static func headerControl(
            scope: CoreHwp.HwpHeaderFooterApplyScope
        ) -> CoreHwp.HwpListControl {
            var payload = Data()
            withUnsafeBytes(of: HwpOtherCtrlId.header.rawValue.littleEndian) {
                payload.append(contentsOf: $0)
            }
            withUnsafeBytes(of: UInt32(scope.rawValue).littleEndian) {
                payload.append(contentsOf: $0)
            }
            let paragraph = (try? HwpSynthetic.textParagraph("머리말")) ?? CoreHwp.HwpParagraph()
            var listPayload = Data()
            withUnsafeBytes(of: Int32(1).littleEndian) { listPayload.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(0).littleEndian) { listPayload.append(contentsOf: $0) }
            let listHeader = (try? CoreHwp.HwpListHeader.load(listPayload))
                ?? CoreHwp.HwpListHeader()
            return CoreHwp.HwpListControl(
                header: CoreHwp.HwpCtrlHeader(
                    ctrlId: HwpOtherCtrlId.header.rawValue, rawPayload: payload
                ),
                listArray: [CoreHwp.HwpListControlList(
                    header: listHeader,
                    headerRawPayload: listPayload,
                    headerUnknownChildren: [],
                    paragraphArray: [paragraph]
                )],
                unknownChildren: []
            )
        }
    }
#endif
