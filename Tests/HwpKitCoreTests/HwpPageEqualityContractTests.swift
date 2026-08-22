import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// `HwpPage.==` / `hash` 의 계약을 고정한다 (#72 조각 ①).
///
/// 이 동등성은 렌더 갱신 스킵만 가르는 것이 아니라 **선택 지오메트리 재생성**과
/// **검색 재스캔 생략**(`HwpGeometryChange.isEquivalentRefresh`)의 입력이다.
/// 종전에는 `paintList.commands.count` 를 항으로 들고 있었는데, 그 항을 잠그는
/// 테스트가 저장소 전체에 0건이라 빼도 넣어도 아무것도 빨개지지 않았다.
final class HwpPageEqualityContractTests: XCTestCase {
    // MARK: paint 항이 동등성에 없다

    /// 커맨드 수만 다른 두 페이지는 **같다** — paint 커맨드는 blocks 의
    /// 파생값이라 판별력을 더하지 못한다.
    func testPagesDifferingOnlyInPaintCommandCountAreEqual() {
        let bare = makePage(commandCount: 0)
        let painted = makePage(commandCount: 7)
        expect(bare) == painted
        expect(bare.hashValue) == painted.hashValue
    }

    /// 메모 패널의 커맨드 수만 달라도 같다 — 풍선 수·줄 수는 패널 기하
    /// (`width`·`contentHeight`)가 대신 나른다.
    func testPagesDifferingOnlyInMemoPanelCommandCountAreEqual() {
        let thin = makePage(commandCount: 0, memoCommandCount: 1)
        let thick = makePage(commandCount: 0, memoCommandCount: 9)
        expect(thin) == thick
    }

    // MARK: 구조 항은 그대로 판별한다

    func testBlocksStillBreakEquality() {
        let text = AnyHwpBlock(frame: .zero, kind: .text)
        let other = AnyHwpBlock(frame: CGRect(x: 1, y: 2, width: 3, height: 4), kind: .text)
        let textPage = makePage(blocks: [text])
        let otherPage = makePage(blocks: [other])
        expect(textPage) != otherPage
    }

    func testPageNumberStillBreaksEquality() {
        let first = makePage(pageNumber: 1)
        let second = makePage(pageNumber: 2)
        expect(first) != second
    }

    /// 메모 패널 기하는 남는다 — 풍선 텍스트는 blocks 에 표현이 없어
    /// 이 두 항이 빠지면 메모 변화를 나를 것이 아무것도 없다.
    func testMemoPanelGeometryStillBreaksEquality() {
        let narrow = makePage(memoWidth: 100)
        let wide = makePage(memoWidth: 140)
        expect(narrow) != wide

        let short = makePage(memoContentHeight: 50)
        let tall = makePage(memoContentHeight: 90)
        expect(short) != tall
    }

    // MARK: 검색 재스캔 생략과의 연결

    /// 커맨드 수만 다른 재전달은 이제 **등가 재전달**로 보고된다 —
    /// `HwpSearchController` 가 이 플래그를 보고 전량 재스캔을 생략한다.
    /// paint 항이 `==` 에 있던 시절에는 등가가 아니어서 매번 재스캔이 돌았다.
    ///
    /// nil-token 문서를 쓰는 이유: 토큰이 있으면 `setDocument` 이 `==` 를 믿고
    /// **아예 조기 반환**해 콜백 자체가 뜨지 않는다 (그 경로는 아래 테스트).
    @MainActor
    func testPaintOnlyRedeliveryIsReportedAsEquivalentRefresh() {
        let controller = HwpSelectionController()
        var changes: [HwpGeometryChange] = []
        controller.onGeometryChanged = { changes.append($0) }

        controller.setDocument(makeDocument(commandCount: 3), preservingSelection: false)
        controller.setDocument(makeDocument(commandCount: 11), preservingSelection: false)
        expect(changes.last?.isEquivalentRefresh) == true

        // 구조가 달라진 재전달은 등가가 아니다 — 재스캔이 돌아야 한다.
        controller.setDocument(
            makeDocument(commandCount: 11, pageNumber: 2), preservingSelection: false
        )
        expect(changes.last?.isEquivalentRefresh) == false
    }

    /// 토큰이 있는 문서라면 커맨드 수만 다른 재전달은 지오메트리 재생성 자체를
    /// 건너뛴다. 조판 구조가 같으므로 새로 만들어 봐야 같은 지오메트리다.
    @MainActor
    func testTokenedPaintOnlyRedeliveryIsSkippedEntirely() {
        let token = UUID()
        let controller = HwpSelectionController()
        controller.setDocument(
            makeDocument(commandCount: 3, loadToken: token), preservingSelection: false
        )

        var changes: [HwpGeometryChange] = []
        controller.onGeometryChanged = { changes.append($0) }
        controller.setDocument(
            makeDocument(commandCount: 11, loadToken: token), preservingSelection: false
        )
        expect(changes).to(beEmpty())
    }

    // MARK: 헬퍼

    private func makePage(
        blocks: [AnyHwpBlock] = [AnyHwpBlock(frame: .zero, kind: .text)],
        pageNumber: Int = 1,
        commandCount: Int = 0,
        memoCommandCount: Int? = nil,
        memoWidth: CGFloat? = nil,
        memoContentHeight: CGFloat? = nil
    ) -> HwpPage {
        let memoPanel: HwpMemoPanel? =
            if memoCommandCount != nil || memoWidth != nil || memoContentHeight != nil {
                HwpMemoPanel(
                    width: memoWidth ?? 120,
                    paintList: paintList(commandCount: memoCommandCount ?? 0),
                    contentHeight: memoContentHeight ?? 0
                )
            } else {
                nil
            }
        return HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 10, left: 10, bottom: 10, right: 10),
            blocks: blocks,
            pageNumber: pageNumber,
            paintList: paintList(commandCount: commandCount),
            memoPanel: memoPanel
        )
    }

    private func paintList(commandCount: Int) -> HwpPaintList {
        HwpPaintList(commands: (0 ..< commandCount).map { index in
            .fillRect(
                rect: CGRect(x: CGFloat(index), y: 0, width: 1, height: 1),
                color: .hwpBlack
            )
        })
    }

    private func makeDocument(
        commandCount: Int,
        pageNumber: Int = 1,
        loadToken: UUID? = nil
    ) -> HwpDocument {
        HwpDocument(
            pages: [makePage(pageNumber: pageNumber, commandCount: commandCount)],
            metadata: HwpDocumentMetadata(pageCount: 1, loadToken: loadToken),
            unsupportedElements: []
        )
    }
}
