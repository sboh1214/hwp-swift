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

        /// **각주에는 흐름 폴백이 없다.** 표 셀은 수집기가 건너뛴 개체를 흐름
        /// 경로가 받아 첫 컴포넌트라도 그리지만, 각주는 `appendNestedControlBlocks`를
        /// 부르지 않아 **아무도 그리지 않는다** (실측: 각주 안 OLE 포함 개체의
        /// 글상자 텍스트가 렌더에 없는데 목록엔 앵커가 있었다). 표 셀과 각주를
        /// 한 문맥으로 묶으면 이 칸이 틀린다.
        func testBookmarksInUncollectibleFootnoteObjectAreNotCollected() async throws {
            var textboxParagraph = try HwpSynthetic.styledParagraph("각주 글상자")
            textboxParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("각주 글상자 앵커")]
            var object = try textbox(containing: textboxParagraph)
            var ole = object.shapeComponentArray[0]
            ole.textBoxListArray = []
            ole.oleArray = [CoreHwp.HwpShapeComponentOLE(
                rawPayload: Data(), binaryDataId: 1, rawTrailing: nil, unknownChildren: []
            )]
            object.shapeComponentArray.append(ole)
            var noteParagraph = try HwpSynthetic.styledParagraph("각주 본문")
            noteParagraph.ctrlHeaderArray = [.genShapeObject(object)]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [noteParagraph]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// **각주의 no-fallback은 자손에게 상속된다.** 각주 안 글상자의 문단에 또
        /// 글상자가 있으면 `HwpTextboxLayout`이 안쪽을 수집하지 않고
        /// (`collectsTextboxes: false`) 각주엔 흐름 폴백도 없어 **아무도 그리지
        /// 않는다** (실측: 안쪽 텍스트가 렌더에 없는데 앵커는 목록에 있었다).
        /// 문맥을 컨트롤 종류만으로 계산하면 `.note`가 `.flow`로 리셋돼 샌다.
        func testBookmarksNestedTwiceInsideANoteAreNotCollected() async throws {
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [try noteHostParagraph()]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["바깥 앵커"]
        }

        /// **각주 안 표의 셀에도 흐름 폴백은 없다.** 표는 각주 안에서도 그려지므로
        /// 셀 문맥으로 내려가지만, 수집기가 건너뛴 개체(OLE 포함)를 받아 줄 흐름이
        /// 없다 — 문맥을 케이스로만 나열하면 이 조합(컨테이너가 그림 + 폴백 없음)이
        /// 빠져 팬텀이 난다 (실측: 셀 글상자가 렌더에 없는데 앵커는 있었다).
        func testBookmarksInUncollectibleObjectInsideANoteTableAreNotCollected() async throws {
            var textboxParagraph = try HwpSynthetic.styledParagraph("셀 글상자")
            textboxParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("셀 글상자 앵커")]
            var object = try textbox(containing: textboxParagraph)
            var ole = object.shapeComponentArray[0]
            ole.textBoxListArray = []
            ole.oleArray = [CoreHwp.HwpShapeComponentOLE(
                rawPayload: Data(), binaryDataId: 1, rawTrailing: nil, unknownChildren: []
            )]
            object.shapeComponentArray.append(ole)
            var cellParagraph = try HwpSynthetic.styledParagraph("셀 본문")
            cellParagraph.ctrlHeaderArray = [.genShapeObject(object)]
            var noteParagraph = try HwpSynthetic.styledParagraph("각주 본문")
            noteParagraph.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [6000], cellParagraphs: [[[cellParagraph]]]
            ))]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [noteParagraph]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// **각주는 어디에 있든 그려진다.** 각주 안 글상자에 또 각주가 있으면
        /// `HwpFootnoteCoordinator`가 그것을 걷어 자기 블록으로 그리므로(실측:
        /// 안쪽 각주 텍스트가 렌더에 있다) 앵커도 목록에 있어야 한다 — 안 그려지는
        /// 자리라고 통째로 막으면 이 칸이 빠진다.
        func testBookmarksInNoteNestedInsideANoteObjectAreCollected() async throws {
            var innerNoteParagraph = try HwpSynthetic.styledParagraph("안쪽 각주")
            innerNoteParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("안쪽 각주 앵커")]
            var textboxParagraph = try HwpSynthetic.styledParagraph("각주 글상자")
            textboxParagraph.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [innerNoteParagraph]
            ))]
            var noteParagraph = try HwpSynthetic.styledParagraph("바깥 각주")
            noteParagraph.ctrlHeaderArray = [
                .genShapeObject(try textbox(containing: textboxParagraph)),
            ]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote, paragraphs: [noteParagraph]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["안쪽 각주 앵커"]
        }

        /// **그림이 글상자보다 앞선다.** `collect(component:)`는 그림이 있으면 그림만
        /// 그리고 반환하므로, 그림과 글상자를 함께 가진 컴포넌트의 글상자 텍스트는
        /// 컨테이너에서 렌더되지 않는다 — 순회가 같은 우선순위를 써야 한다.
        func testBookmarksInPictureBearingComponentTextboxAreNotCollected() async throws {
            var textboxParagraph = try HwpSynthetic.styledParagraph("그림 글상자")
            textboxParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("그림 글상자 앵커")]
            var object = HwpSynthetic.inlinePictureObject(width: 6000, height: 4000, binItemId: 1)
            var component = object.shapeComponentArray[0]
            component.textBoxListArray = [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: [textboxParagraph]
            )]
            object.shapeComponentArray[0] = component
            var cellParagraph = try HwpSynthetic.styledParagraph("셀 본문")
            cellParagraph.ctrlHeaderArray = [.genShapeObject(object)]
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [6000], cellParagraphs: [[[cellParagraph]]]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// 대조군 — **같은 중첩을 표 셀에 두면** 흐름이 안쪽 글상자까지 그리므로
        /// 그 앵커는 수집이 옳다 (실측: 안쪽 텍스트가 렌더에 있다). 이 짝이 없으면
        /// 위 테스트는 "중첩을 통째로 막는다"로도 통과해 계약이 흐려진다.
        func testSameNestingInsideATableCellKeepsTheInnerBookmark() async throws {
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000,
                rowHeights: [12000],
                cellParagraphs: [[[try noteHostParagraph()]]]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline.map(\.title)) == ["바깥 앵커", "안쪽 앵커"]
        }

        /// 흐름 개체의 **둘째 이후 컴포넌트**는 텍스트가 안 그려지지만 그 안
        /// 중첩 컨트롤은 `appendNestedControlBlocks`가 방출해 **그려진다**
        /// (실측: 둘째 컴포넌트 안 표의 셀 텍스트가 렌더에 있다). 그래서 직접
        /// 앵커만 빼고 자식 순회는 이어 가야 한다 — 서브트리를 통째로 자르면
        /// 그려진 셀의 앵커가 빠지고, 통째로 두면 안 그려진 텍스트의 앵커가 샌다.
        func testNestedControlsInLaterComponentsAreStillTraversed() async throws {
            var cellParagraph = try HwpSynthetic.styledParagraph("중첩 셀")
            cellParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("중첩 셀 앵커")]
            var secondParagraph = try HwpSynthetic.styledParagraph("둘째 컴포넌트")
            secondParagraph.ctrlHeaderArray = [
                HwpSynthetic.bookmarkControl("둘째 컴포넌트 앵커"),
                .table(HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [4000], cellParagraphs: [[[cellParagraph]]]
                )),
            ]
            var firstParagraph = try HwpSynthetic.styledParagraph("첫 컴포넌트")
            firstParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("첫 컴포넌트 앵커")]
            var object = try textbox(containing: firstParagraph)
            object.shapeComponentArray.append(
                try textbox(containing: secondParagraph).shapeComponentArray[0]
            )
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.genShapeObject(object)]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            // 첫 컴포넌트 텍스트의 앵커와 **그려진 중첩 셀**의 앵커만 남는다 —
            // 둘째 컴포넌트 텍스트의 직접 앵커는 그려지지 않으므로 빠진다.
            expect(outline.map(\.title)) == ["첫 컴포넌트 앵커", "중첩 셀 앵커"]
        }

        /// 수식으로 그려지는 개체의 글상자 앵커는 내지 않는다 — EQEDIT 스크립트가
        /// 있으면 `appendEquationBlock`이 성공해 `appendShapeObjectBlocks`(글상자
        /// 렌더)를 **건너뛰기** 때문이다. 렌더 분기와 순회가 같은 판정
        /// (`equationAttributedString`)을 공유해야 어긋나지 않는다.
        func testBookmarksInEquationTextboxAreNotCollected() async throws {
            var textboxParagraph = try HwpSynthetic.styledParagraph("수식 글상자")
            textboxParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("수식 글상자 앵커")]
            let component = try textbox(containing: textboxParagraph).shapeComponentArray[0]
            // EQEDIT 레코드는 합성 생성자가 없어 실제 픽스처에서 가져온다 —
            // 스크립트가 실물이라 `HwpEquationLayout`이 근사 텍스트를 실제로 만든다.
            let edit = try XCTUnwrap(equationEditFromFixture())
            let equation = CoreHwp.HwpShapeControl(
                ctrlId: .equation,
                commonCtrlProperty: CoreHwp.HwpCommonCtrlProperty(),
                rawPayload: Data(),
                rawTrailing: Data(),
                shapeComponentArray: [component],
                eqEditArray: [edit],
                eqEditRecords: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.equation(equation)]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host], index: HwpSynthetic.outlineIndex()
            )

            _ = await paginator.totalPages()
            let outline = await paginator.outline()
            expect(outline).to(beEmpty())
        }

        /// 세그먼트 상한에 걸려 **방출되지 않은 행**의 앵커도 내지 않는다.
        /// 배치(occupancy)는 그 셀을 받아들였지만 페이지에 그려진 적이 없다 —
        /// 두 한도가 서로 다른 지점이라 `renderedCells`만으로는 걸러지지 않는다.
        /// 상한을 1로 낮춰 작은 표로 그 경로를 탄다 (실문서 상한은 4,096).
        func testBookmarksInRowsBeyondTheSegmentCapAreNotCollected() async throws {
            func row(_ text: String, _ anchor: String) throws -> [CoreHwp.HwpParagraph] {
                var paragraph = try HwpSynthetic.styledParagraph(text)
                paragraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl(anchor)]
                return [paragraph]
            }
            // 한 쪽에 한 행씩만 들어가게 행을 크게 잡아 세그먼트를 강제로 나눈다.
            var host = try HwpSynthetic.styledParagraph("본문")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 30000,
                rowHeights: [16000, 16000, 16000],
                cellParagraphs: [
                    try [row("1행", "1행 앵커")],
                    try [row("2행", "2행 앵커")],
                    try [row("3행", "3행 앵커")],
                ]
            ))]

            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host],
                index: HwpSynthetic.outlineIndex(),
                pageHeight: 20000
            )
            await paginator.overrideMaximumTableSegments(1)

            _ = await paginator.totalPages()
            let outline = await paginator.outline()

            // 첫 세그먼트에 실린 행만 남는다 — 뒤 행은 그려지지 않았다.
            expect(outline.map(\.title)) == ["1행 앵커"]
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

        /// 글상자 **안** 글상자를 품은 문단 — 바깥·안쪽에 앵커가 하나씩이다.
        /// 각주에 넣으면 안쪽이 안 그려지고, 표 셀에 넣으면 그려진다.
        func noteHostParagraph() throws -> CoreHwp.HwpParagraph {
            var innerParagraph = try HwpSynthetic.styledParagraph("안쪽 글상자")
            innerParagraph.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("안쪽 앵커")]
            var outerParagraph = try HwpSynthetic.styledParagraph("바깥 글상자")
            outerParagraph.ctrlHeaderArray = [
                HwpSynthetic.bookmarkControl("바깥 앵커"),
                .genShapeObject(try textbox(containing: innerParagraph)),
            ]
            var host = try HwpSynthetic.styledParagraph("담는 문단")
            host.ctrlHeaderArray = [.genShapeObject(try textbox(containing: outerParagraph))]
            return host
        }

        /// `equation` 픽스처의 첫 EQEDIT 레코드 — 합성 생성자가 없어 실물을 쓴다.
        func equationEditFromFixture() throws -> CoreHwp.HwpEquationEdit? {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/equation/document.hwp")
            let file = try CoreHwp.HwpFile(fromPath: url.path)
            for section in file.displaySectionArray {
                for paragraph in section.paragraph {
                    for ctrl in paragraph.ctrlHeaderArray ?? [] {
                        if case let .equation(shape) = ctrl, let edit = shape.eqEditArray.first {
                            return edit
                        }
                    }
                }
            }
            return nil
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
