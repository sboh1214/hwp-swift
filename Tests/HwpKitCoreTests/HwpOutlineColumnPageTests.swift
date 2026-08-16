@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 다단에서의 개요 쪽 귀속 (#77). 1단 경로의 같은 계약은
    /// `HwpOutlineNavigationTests.testHeadingOnPageBoundaryReportsTheStartingPage`가
    /// 본다 — 그쪽은 미루기(`placeFlowParagraph`의 `false` 반환)로 쪽이 재계산되므로
    /// 애초에 낡을 여지가 없다.
    final class HwpOutlineColumnPageTests: XCTestCase {
        /// 개요 쪽은 문단의 **첫 조각이 놓인** 쪽이다.
        ///
        /// 다단에는 미루기가 없다 — `placeMultiColumnParagraph`가 무조건 성공을
        /// 돌려주고 `appendParagraphAcrossColumns`가 마지막 단이 모자라면 스스로
        /// 쪽을 넘긴 뒤 첫 줄을 놓는다. 그래서 배치 **전**에 잡은 쪽은 낡는다:
        /// 실측(2단 · 40pt 채움 3개)에서 제목은 2쪽에 그려지는데 목록은 1쪽을
        /// 가리켰다.
        ///
        /// **채움 수는 3이어야 한다** — 4개 이상이면 제목 문단을 처리하기 전에
        /// 이미 쪽이 확정돼 사전 포착값이 우연히 맞고(실측: 4·5·6 전부 2쪽 보고),
        /// 2개 이하면 한 쪽에 다 들어가 경계가 서지 않는다.
        func testMultiColumnHeadingReportsThePageItRendersOn() async throws {
            let fillers = try (0 ..< 3).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "채움 \(index)", segments: [(location: 0, height: 4000)]
                )
            }
            var heading = try HwpSynthetic.lineSegParagraph(
                "제목", segments: [(location: 0, height: 4000)]
            )
            heading.paraHeader = try HwpSynthetic.outlineParaHeader(
                paraShapeId: 1, paraStyleId: 0
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 20000)),
                    .column(HwpSynthetic.column(count: 2)),
                ],
                bodyParagraphs: fillers + [heading]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                fontResolver: .testDeterministic
            )

            let totalPages = await paginator.totalPages()
            let outline = await paginator.outline()
            let renderedPage = try await pageContaining("제목", in: paginator, upTo: totalPages)

            expect(totalPages) == 2
            expect(renderedPage) == 2
            // 보고 쪽을 **렌더 오라클**에 묶는다 — 상수만 단언하면 조판이 바뀔 때
            // 둘이 함께 틀려도 통과한다.
            expect(outline.map(\.pageNumber)) == [renderedPage]
        }
    }

    private extension HwpOutlineColumnPageTests {
        /// 그 텍스트가 실제로 그려진 1-기반 쪽 (없으면 0).
        func pageContaining(
            _ text: String,
            in paginator: HwpPaginator,
            upTo pages: Int
        ) async throws -> Int {
            for index in 0 ..< pages {
                guard let page = try await paginator.page(at: index) else { continue }
                let texts = page.blocks.compactMap(\.attributedString?.string)
                if texts.contains(where: { $0.contains(text) }) {
                    return index + 1
                }
            }
            return 0
        }
    }
#endif
