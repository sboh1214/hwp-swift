@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 머리말·꼬리말의 **빈 문단도 한 줄을 차지한다** (#137).
    ///
    /// `HwpPageChromeBuilder`는 `HwpParagraphMeasurer`를 거치지 않고 `layout`을
    /// 직접 부르는 네 경로 중 하나라(`Sources/HwpKitCore/AGENTS.md` "layout에 닿는
    /// 경로"), 측정 계층에 건 빈 문단 하한이 여기까지 오지 않는다. 문단 끝 코드를
    /// 접은 뒤로 빈 문단의 조판 문자열이 길이 0이 되므로, 자리를 따로 비우지
    /// 않으면 뒤 줄이 한 줄 위로 올라온다.
    final class HwpPageChromeEmptyParagraphTests: XCTestCase {
        /// 머리말 문단 목록으로 페이지를 만든다.
        private func paginator(
            headerParagraphs: [CoreHwp.HwpParagraph]
        ) throws -> HwpPaginator {
            let header = HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: headerParagraphs
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .header(header),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph("본문")]
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 머리말 텍스트 블록의 문자열과 y 좌표 (문서 순서).
        private func chromeTextBlocks(
            _ paginator: HwpPaginator
        ) async throws -> [(text: String, y: CGFloat)] {
            guard let page = try await paginator.page(at: 0) else { return [] }
            return page.blocks
                .filter { $0.role == .pageChrome && $0.kind == .text }
                .map { ($0.attributedString?.string ?? "", $0.frame.minY) }
        }

        func testEmptyHeaderParagraphStillAdvancesTheBand() async throws {
            // HWPX의 빈 문단이 정확히 이 모양이다 — WCHAR 스트림이 문단 끝
            // 코드 13 하나뿐이라 조판 문자열이 비어 있다.
            let withEmptyFirst = try await chromeTextBlocks(paginator(headerParagraphs: [
                try HwpSynthetic.textParagraph("\u{0D}"),
                try HwpSynthetic.textParagraph("둘째 줄"),
            ]))
            let withoutEmpty = try await chromeTextBlocks(paginator(headerParagraphs: [
                try HwpSynthetic.textParagraph("둘째 줄"),
            ]))

            // 빈 문단은 그릴 글자가 없어 블록을 만들지 않는다 — 양쪽 다 한 개.
            expect(withEmptyFirst.map(\.text)) == ["둘째 줄"]
            expect(withoutEmpty.map(\.text)) == ["둘째 줄"]

            // 그러나 자리는 차지한다 — 빈 문단이 앞에 있으면 아래에 놓인다.
            let advanced = try XCTUnwrap(withEmptyFirst.first?.y)
            let base = try XCTUnwrap(withoutEmpty.first?.y)
            expect(advanced).to(beGreaterThan(base))
        }
    }
#endif
