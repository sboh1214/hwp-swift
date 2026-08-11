import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 검색 컨트롤러의 **관찰자 통지** 계약 (#75).
///
/// `HwpSearchControllerTests` 에서 갈라 나왔다 (`HwpSearchBudgetTests` 와 같은
/// 선례). 나누는 축은 "상태가 언제 바뀌는가"가 아니라 "그 변화가 어떻게 밖으로
/// 나가는가"다 — 커스텀 네이티브 뷰에는 이 콜백 말고 알 통로가 없다
/// (`attach` 가 선택 컨트롤러의 단일 지오메트리 콜백을 점유한다).
@MainActor
final class HwpSearchNotificationTests: XCTestCase {
    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private static func document(pageTexts: [String]) -> HwpDocument {
        HwpDocument(
            pages: pageTexts.enumerated().map { index, text in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [AnyHwpBlock(
                        frame: CGRect(x: 10, y: 20, width: 400, height: 20),
                        kind: .text,
                        attributedString: NSAttributedString(
                            string: text,
                            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                        ),
                        role: .body
                    )],
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pageTexts.count),
            unsupportedElements: []
        )
    }

    private static func makeAttached(
        pageTexts: [String]
    ) -> (HwpSelectionController, HwpSearchController) {
        let selection = HwpSelectionController()
        selection.setDocument(Self.document(pageTexts: pageTexts), preservingSelection: false)
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.attach(to: selection)
        return (selection, search)
    }

    /// 결과가 있는 질의를 교체하면 리셋도 **발행**해야 한다. 새 질의에 매치가
    /// 없으면 `publish` 가 세 분기를 모두 빗나가 `onCurrentMatchChanged(nil)` 이
    /// 영영 오지 않아, 콜백 소비자가 사라진 매치를 계속 들고 있다
    /// (#75 리뷰 8차).
    func testReplacingQueryClearsCurrentMatchForObservers() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit one", "hit two"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))

        var reported: [HwpSearchMatch?] = []
        var repaints = 0
        search.onCurrentMatchChanged = { reported.append($0) }
        search.onMatchesChanged = { repaints += 1 }
        search.search(text: "zzz")

        // 스캔이 돌기 **전에** 이미 알려야 한다
        expect(reported.count) == 1
        expect(reported[0]).to(beNil())
        expect(repaints) >= 1
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 0
    }

    /// 매치가 없다가 없는 상태로 가는 교체는 통지하지 않는다 — 타이핑마다
    /// 빈 오버레이를 다시 칠할 이유가 없다.
    func testReplacingQueryWithoutResultsDoesNotNotify() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit one"])
        search.search(text: "zzz")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))

        var repaints = 0
        search.onMatchesChanged = { repaints += 1 }
        search.search(text: "zzzz")

        expect(repaints) == 0
    }

    /// 동등 재전달은 재스캔하지 않지만 지오메트리는 새것이라 rect 는 다시
    /// 계산돼야 한다 — 통지가 없으면 커스텀 뷰가 옛 사각형을 영구히 들고 있다
    /// (#75 리뷰 8차).
    func testEquivalentRefreshNotifiesRepaintWithoutRescanning() async {
        let (selection, search) = Self.makeAttached(pageTexts: ["hit one", "hit two"])
        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        search.next()
        var repaints = 0
        search.onMatchesChanged = { repaints += 1 }

        selection.setDocument(
            Self.document(pageTexts: ["hit one", "hit two"]),
            preservingSelection: true
        )

        expect(repaints) == 1
        // 재스캔은 없다 — 골라 둔 현재 매치가 그대로다 (#75 리뷰 6차 계약)
        expect(search.currentMatchIndex) == 1
        expect(search.phase) == .complete
    }

    // MARK: - 부착 소유권

    /// 슬롯이 하나뿐이라 나중에 붙은 쪽이 이기는데, **밀려난 쪽은 그 사실을
    /// 모른다**. 그 상태에서 밀려난 컨트롤러를 떼면 현재 소유자의 콜백이
    /// 지워져, 그쪽은 붙어 있다고 보고하면서 영영 재스캔하지 않는다
    /// (#75 리뷰 13차).
    func testDetachingDisplacedControllerKeepsCurrentOwnerWired() async {
        let selection = HwpSelectionController()
        selection.setDocument(Self.document(pageTexts: ["hit one"]), preservingSelection: false)
        let displaced = HwpSearchController()
        displaced.publishInterval = .zero
        displaced.attach(to: selection)
        let owner = HwpSearchController()
        owner.publishInterval = .zero
        owner.attach(to: selection)
        owner.search(text: "hit")
        await expect(owner.matchCount).toEventually(equal(1), timeout: .seconds(2))

        displaced.detach()

        // 현재 소유자는 문서 교체에 여전히 반응한다
        selection.setDocument(
            Self.document(pageTexts: ["hit one", "hit two"]),
            preservingSelection: false
        )
        await expect(owner.matchCount).toEventually(equal(2), timeout: .seconds(2))
    }

    /// 그릴 것이 없으면 동등 재전달도 통지하지 않는다 — nil-token 문서는 이
    /// 사건이 SwiftUI 업데이트마다 온다.
    func testEquivalentRefreshWithoutHighlightsIsSilent() async {
        let (selection, search) = Self.makeAttached(pageTexts: ["hit one"])
        search.search(text: "zzz")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))

        var repaints = 0
        search.onMatchesChanged = { repaints += 1 }
        selection.setDocument(
            Self.document(pageTexts: ["hit one"]),
            preservingSelection: true
        )

        expect(repaints) == 0
    }
}
