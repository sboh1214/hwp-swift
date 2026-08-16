@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 탐색 목록 수집의 **깊이 경계** (#77). 표와 비표 컨테이너가 서로 다른
    /// 카운터를 타는 규약을 고정한다 — 표 자체의 경계(조판되는 최심 표까지
    /// 수집하고 그 아래는 버린다)는 `HwpOutlineNavigationTests`의
    /// `testBookmarksInsideTheDeepestRenderedTableAreCollected`가 본다.
    final class HwpOutlineContainerDepthTests: XCTestCase {
        /// 표를 지나도 **컨테이너 깊이는 오르지 않는다.** 셀 안 개체는 흐름
        /// 방출(`appendNestedControlBlocks`)이 아니라 `HwpTableLayout`이 셀
        /// 콘텐츠로 그리므로 컨테이너 한도의 적용 대상이 아니다.
        ///
        /// 실측으로 확인한 형상이다 — 이 문서의 셀 페이로드를 훑으면 3겹째 표의
        /// 셀에 `textboxes` 1개가 실제로 그려져 있는데, 표가 카운터를 함께
        /// 올리던 시절에는 그 글상자가 `depth == 3`에 걸려 안쪽 책갈피가 조용히
        /// 빠졌다 (목록이 통째로 비었다).
        func testBookmarkInsideTextboxUnderNestedTablesIsCollected() async throws {
            var textboxParagraph = try HwpSynthetic.styledParagraph("글상자 텍스트")
            textboxParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("글상자 앵커")]
            var object = try HwpSynthetic.inlineTextboxObject(
                width: 5000, height: 3000, text: "자리 표시"
            )
            var component = object.shapeComponentArray[0]
            component.textBoxListArray = [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [textboxParagraph]
            )]
            object.shapeComponentArray[0] = component

            // 표 3겹(전부 조판됨) 안쪽 셀에 글상자를 둔다.
            let cell3 = try cell("표3 셀", [.genShapeObject(object)])
            let cell2 = try cell("표2 셀", [wrap(cell3)])
            let cell1 = try cell("표1 셀", [wrap(cell2)])
            let host = try cell("본문", [wrap(cell1)])

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["글상자 앵커"]
        }

        /// 비표 컨테이너는 여전히 자기 한도를 지킨다 — 글상자를 네 겹 쌓으면
        /// 마지막 겹의 안쪽은 렌더도 되지 않으므로(`appendNestedControlBlocks`가
        /// `depth < 3`에서 멈춘다) 그 책갈피는 계속 빠져야 한다. 이 단언이 없으면
        /// 비표 가드를 통째로 지워도 위 테스트가 통과한다.
        func testBookmarkBeyondTheContainerDepthLimitIsStillDropped() async throws {
            var innermost = try HwpSynthetic.styledParagraph("가장 안쪽")
            innermost.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("과다 깊이 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(try nestedTextboxes(depth: 4, innermost))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }
    }

    private extension HwpOutlineContainerDepthTests {
        func cell(_ text: String, _ ctrls: [CoreHwp.HwpCtrlId]) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.styledParagraph(text)
            paragraph.ctrlHeaderArray = ctrls
            return paragraph
        }

        func wrap(_ paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpCtrlId {
            .table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [8000], cellParagraphs: [[[paragraph]]]
            ))
        }

        /// 글상자 `depth`겹 — 가장 안쪽에 `innermost` 문단을 둔다.
        func nestedTextboxes(
            depth: Int,
            _ innermost: CoreHwp.HwpParagraph
        ) throws -> CoreHwp.HwpGenShapeObject {
            var paragraph = innermost
            var object = try textbox(containing: paragraph)
            for level in 1 ..< depth {
                paragraph = try cell("글상자 \(level)", [.genShapeObject(object)])
                object = try textbox(containing: paragraph)
            }
            return object
        }

        func textbox(containing paragraph: CoreHwp.HwpParagraph) throws
            -> CoreHwp.HwpGenShapeObject
        {
            var object = try HwpSynthetic.inlineTextboxObject(
                width: 5000, height: 3000, text: "자리 표시"
            )
            var component = object.shapeComponentArray[0]
            component.textBoxListArray = [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [paragraph]
            )]
            object.shapeComponentArray[0] = component
            return object
        }
    }
#endif
