import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 선택 변경 API 스위트 — `beginAdjusting(edge:)`의 anchor/focus 교환 계약과
/// `selectionCarets()`의 끝점 캐럿 (#84).
///
/// `begin`/`extend`/`selectWord`/`selectAll`/`clear`를 직접 부르는 HwpKitCore
/// 테스트는 이 파일이 처음이다 — 그전까지 선택 변경은 뷰 테스트에서만 밟혔다.
@MainActor
final class HwpSelectionControllerTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func makeDocument(pageTexts: [String]) -> HwpDocument {
        HwpDocument(
            pages: pageTexts.enumerated().map { index, text in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [AnyHwpBlock(
                        frame: CGRect(x: 50, y: 100, width: 300, height: 20),
                        kind: .text,
                        attributedString: NSAttributedString(
                            string: text,
                            attributes: [
                                kCTFontAttributeName as NSAttributedString.Key: font,
                            ]
                        )
                    )],
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pageTexts.count),
            unsupportedElements: []
        )
    }

    private func position(page: Int = 0, _ offset: Int) -> HwpTextPosition {
        HwpTextPosition(
            pageIndex: page, blockIndex: 0, unitIndex: 0, characterOffset: offset
        )
    }

    private func makeController(
        pageTexts: [String] = ["Hello world"]
    ) -> HwpSelectionController {
        let controller = HwpSelectionController()
        controller.document = makeDocument(pageTexts: pageTexts)
        return controller
    }

    // MARK: - beginAdjusting

    func testAdjustingNeedsANonCollapsedSelection() {
        let controller = makeController()

        expect(controller.beginAdjusting(edge: .start)) == false

        controller.begin(at: position(3))

        expect(controller.beginAdjusting(edge: .start)) == false
        expect(controller.beginAdjusting(edge: .end)) == false
    }

    /// 시작 핸들을 잡으면 시작이 focus가 된다 — 그래야 이후 `extend(to:)`
    /// 하나로 그 끝점을 밀 수 있고, 오토스크롤 틱(늘 focus를 민다)도 그대로
    /// 재사용된다. 범위 자체는 바뀌지 않는다.
    func testAdjustingStartSwapsAnchorAndFocusWithoutMovingTheRange() {
        let controller = makeController()
        controller.begin(at: position(2))
        controller.extend(to: position(8))

        expect(controller.beginAdjusting(edge: .start)) == true

        expect(controller.selection?.focus) == position(2)
        expect(controller.selection?.anchor) == position(8)
        expect(controller.selection?.range.start) == position(2)
        expect(controller.selection?.range.end) == position(8)
    }

    /// 역방향 드래그(anchor > focus)로 만든 선택도 끝 핸들을 잡으면 끝이
    /// focus가 된다 — `range` 정규화만 믿고 anchor를 그대로 두면 끝 핸들을
    /// 끌었는데 시작이 움직인다.
    func testAdjustingEndNormalizesABackwardSelection() {
        let controller = makeController()
        controller.begin(at: position(9))
        controller.extend(to: position(1))

        expect(controller.beginAdjusting(edge: .end)) == true

        expect(controller.selection?.focus) == position(9)
        expect(controller.selection?.anchor) == position(1)
    }

    /// 교환은 `.began`에서 딱 한 번이지만, 실수로 두 번 불러도 방향이 이미
    /// 맞으면 통지하지 않는다 — 범위가 그대로인 재도색을 아낀다.
    func testAdjustingTheSameEdgeTwiceDoesNotRenotify() {
        let controller = makeController()
        controller.begin(at: position(2))
        controller.extend(to: position(8))
        var notifications = 0
        controller.onSelectionChanged = { notifications += 1 }

        expect(controller.beginAdjusting(edge: .start)) == true
        expect(notifications) == 1

        expect(controller.beginAdjusting(edge: .start)) == true
        expect(notifications) == 1
    }

    /// 시작 핸들을 끝 핸들 **너머로** 끌면 잡고 있던 것이 '끝 핸들'이 된다
    /// (UITextView와 같은 동작). 뷰가 아무 상태도 뒤집지 않아도 손가락을
    /// 따라오는 것은 계속 focus다 — 이 계약이 깨지면 드래그가 반대 끝점을
    /// 끌기 시작한다.
    func testHandleRolesSwapWhenDraggedPastTheOppositeEnd() {
        let controller = makeController()
        controller.begin(at: position(2))
        controller.extend(to: position(8))
        controller.beginAdjusting(edge: .start)

        controller.extend(to: position(10))

        expect(controller.selection?.focus) == position(10)
        expect(controller.selection?.range.start) == position(8)
        expect(controller.selection?.range.end) == position(10)
        // 잡고 있는 끝점(focus)이 이제 범위의 **끝**이다
        expect(controller.selection?.focus) == controller.selection?.range.end
    }

    // MARK: - selectionCarets

    func testNoCaretsWithoutASelection() {
        let controller = makeController()

        expect(controller.selectionCarets()).to(beEmpty())

        controller.begin(at: position(4))

        expect(controller.selectionCarets()).to(beEmpty())
    }

    func testCaretsAreOrderedStartThenEndInDocumentOrder() {
        let controller = makeController()
        // 역방향 드래그 — 캐럿은 anchor/focus가 아니라 문서 순서를 따른다
        controller.begin(at: position(9))
        controller.extend(to: position(1))

        let carets = controller.selectionCarets()

        expect(carets.count) == 2
        expect(carets[0].edge) == .start
        expect(carets[1].edge) == .end
        expect(carets[0].rect.width) == 0
        expect(carets[1].rect.width) == 0
        expect(carets[0].rect.minX) < carets[1].rect.minX
    }

    func testCaretsCarryTheirOwnPageIndex() {
        let controller = makeController(pageTexts: ["first page", "second page"])
        controller.begin(at: position(page: 0, 3))
        controller.extend(to: position(page: 1, 4))

        let carets = controller.selectionCarets()

        expect(carets.count) == 2
        expect(carets[0].pageIndex) == 0
        expect(carets[1].pageIndex) == 1
    }

    /// 캐럿을 못 구한 끝점은 빠지고 나머지는 남는다 — 전부 버리면 반대쪽
    /// 핸들까지 사라진다.
    func testUnresolvableEdgeDropsOnlyThatCaret() {
        let controller = makeController()
        controller.begin(at: position(2))
        // 존재하지 않는 블록으로 확장 — 끝점 캐럿만 못 구한다
        controller.extend(to: HwpTextPosition(
            pageIndex: 0, blockIndex: 42, unitIndex: 0, characterOffset: 0
        ))

        let carets = controller.selectionCarets()

        expect(carets.count) == 1
        expect(carets[0].edge) == .start
    }

    func testCaretsFollowSelectAll() {
        let controller = makeController(pageTexts: ["first page", "second page"])

        controller.selectAll()

        let carets = controller.selectionCarets()
        expect(carets.count) == 2
        expect(carets[0].pageIndex) == 0
        expect(carets[1].pageIndex) == 1
    }
}
