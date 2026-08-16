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

        /// **최심 글상자의 자기 문단은 렌더되므로 수집한다.** 글상자 네 겹이면
        /// 가장 안쪽 글상자가 상한 depth에 놓이는데, 거기까지는 레이아웃이 도달해
        /// (`appendNestedControlBlocks`는 `depth < 3`에서 **자식 방출**만 멈춘다)
        /// 그 글상자의 텍스트가 `HwpTextboxLayout`으로 그려진다 — 실측으로 확인했다
        /// (렌더 텍스트에 "가장 안쪽"이 있는데 목록은 비어 있었다).
        func testBookmarkInsideTheDeepestRenderedTextboxIsCollected() async throws {
            var innermost = try HwpSynthetic.styledParagraph("가장 안쪽")
            innermost.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("최심 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(try nestedTextboxes(depth: 4, innermost))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["최심 앵커"]
        }

        /// 경계 반대쪽: 글상자 **다섯** 겹이면 가장 안쪽 글상자가 상한을 넘어
        /// 레이아웃 자체가 없으므로 그 안 책갈피는 계속 빠진다. 이 단언이 없으면
        /// 비표 가드를 통째로 지워도 위 테스트들이 통과한다.
        func testBookmarkBeyondTheContainerDepthLimitIsStillDropped() async throws {
            var innermost = try HwpSynthetic.styledParagraph("가장 안쪽")
            innermost.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("과다 깊이 앵커")]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(try nestedTextboxes(depth: 5, innermost))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// 개체 순회는 **렌더되는 컴포넌트**만 본다 — `HwpTextboxLayout`이 텍스트를
        /// 가진 첫 컴포넌트 하나만 그리므로(묶음 개체의 나머지는 안 그려진다),
        /// 전 컴포넌트를 돌면 그려지지 않은 텍스트의 앵커가 목록에 올라 누르면
        /// 아무것도 없는 자리로 간다 (실측: 렌더는 "컴포넌트1"뿐인데 목록엔 둘 다).
        func testBookmarksInUnrenderedShapeComponentsAreNotCollected() async throws {
            var first = try HwpSynthetic.styledParagraph("컴포넌트 1")
            first.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("첫 컴포넌트 앵커")]
            var second = try HwpSynthetic.styledParagraph("컴포넌트 2")
            second.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("둘째 컴포넌트 앵커")]
            var object = try textbox(containing: first)
            object.shapeComponentArray.append(try textbox(containing: second).shapeComponentArray[0])
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(object)]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["첫 컴포넌트 앵커"]
        }

        /// **컨테이너 안에서는 반대다** — 표 셀·각주 안 개체는
        /// `HwpParagraphObjectCollector`가 컴포넌트마다 글상자를 그리므로 전
        /// 컴포넌트가 렌더된다 (실측: 셀 안 컴포넌트 2개가 둘 다 그려진다).
        /// 위 흐름 테스트와 범위가 갈리므로 순회가 문맥을 봐야 한다 — 한쪽으로
        /// 통일하면 반드시 다른 쪽이 틀린다.
        func testBookmarksInEveryComponentInsideATableCellAreCollected() async throws {
            var first = try HwpSynthetic.styledParagraph("컴포넌트 1")
            first.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("셀 첫 컴포넌트 앵커")]
            var second = try HwpSynthetic.styledParagraph("컴포넌트 2")
            second.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("셀 둘째 컴포넌트 앵커")]
            var object = try textbox(containing: first)
            object.shapeComponentArray.append(try textbox(containing: second).shapeComponentArray[0])
            var cellParagraph = try HwpSynthetic.styledParagraph("셀")
            cellParagraph.ctrlHeaderArray = [.genShapeObject(object)]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [12000], cellParagraphs: [[[cellParagraph]]]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["셀 첫 컴포넌트 앵커", "셀 둘째 컴포넌트 앵커"]
        }

        /// 컨테이너 안이라도 **수집기가 건너뛰는 컨트롤**은 흐름 경로가 그린다 —
        /// OLE를 품은 개체가 그렇다 (`HwpParagraphObjectCollector.collectible`이
        /// false). 그때 렌더는 첫 컴포넌트뿐이므로 순회도 거기서 멈춰야 한다
        /// (실측: 렌더는 "컴포넌트 1"뿐인데 목록엔 둘 다 올랐다). 부모가 셀이라는
        /// 것만으로 전 컴포넌트를 도는 판정은 이 경우를 놓친다.
        func testBookmarksInUncollectibleCellObjectFollowTheFlowScope() async throws {
            var first = try HwpSynthetic.styledParagraph("컴포넌트 1")
            first.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("첫 컴포넌트 앵커")]
            var second = try HwpSynthetic.styledParagraph("컴포넌트 2")
            second.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("둘째 컴포넌트 앵커")]
            var object = try textbox(containing: first)
            var extra = try textbox(containing: second).shapeComponentArray[0]
            // OLE를 품은 컴포넌트 하나가 컨트롤 전체를 수집 대상에서 뺀다.
            extra.oleArray = [CoreHwp.HwpShapeComponentOLE(
                rawPayload: Data(), binaryDataId: 1, rawTrailing: nil, unknownChildren: []
            )]
            object.shapeComponentArray.append(extra)
            var cellParagraph = try HwpSynthetic.styledParagraph("셀")
            cellParagraph.ctrlHeaderArray = [.genShapeObject(object)]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [12000], cellParagraphs: [[[cellParagraph]]]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["첫 컴포넌트 앵커"]
        }

        /// 배치가 **거부한 셀**의 앵커는 내지 않는다 — 선언 격자(1×1) 밖 주소의
        /// 셀은 `HwpTableLayout.placement`가 nil을 돌려줘 그려지지 않는다
        /// (실측: 렌더 텍스트에 "여분 셀"이 없는데 목록엔 그 앵커가 있었다).
        func testBookmarksInCellsRejectedByLayoutAreNotCollected() async throws {
            var declared = try HwpSynthetic.styledParagraph("선언 셀")
            declared.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("선언 셀 앵커")]
            var extra = try HwpSynthetic.styledParagraph("여분 셀")
            extra.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("여분 셀 앵커")]
            var table = HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [6000], cellParagraphs: [[[declared]]]
            )
            table.cellArray.append(HwpSynthetic.tableCell(
                row: 5, column: 5, width: 30000, height: 6000, paragraphs: [extra]
            ))
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(table)]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["선언 셀 앵커"]
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
