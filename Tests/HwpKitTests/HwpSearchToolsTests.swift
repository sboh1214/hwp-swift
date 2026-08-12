import CoreGraphics
import CoreText
import Foundation
@testable import HwpKit
import HwpKitCore
import Nimble
import SwiftUI
import XCTest

/// 검색 UI 컴포넌트(#75) — `HwpToolsTests` 관례대로 뷰를 만들고 body 밖
/// 메서드를 직접 부른다 (body를 렌더하지 않는다).
@MainActor
final class HwpSearchToolsTests: XCTestCase {
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
                            attributes: [
                                kCTFontAttributeName as NSAttributedString.Key: Self.font,
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

    private static func attached(pageTexts: [String])
        -> (HwpSelectionController, HwpSearchController)
    {
        let selection = HwpSelectionController()
        selection.setDocument(Self.document(pageTexts: pageTexts), preservingSelection: false)
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.attach(to: selection)
        return (selection, search)
    }

    // MARK: - 표시 번호 (순수 함수, 격리 없이 부른다)

    nonisolated func testDisplayMatchNumberIsOneBased() {
        expect(hwpDisplayMatchNumber(currentIndex: 0, matchCount: 3)) == 1
        expect(hwpDisplayMatchNumber(currentIndex: 2, matchCount: 3)) == 3
    }

    nonisolated func testDisplayMatchNumberIsZeroWithoutMatches() {
        expect(hwpDisplayMatchNumber(currentIndex: nil, matchCount: 0)) == 0
        expect(hwpDisplayMatchNumber(currentIndex: 0, matchCount: 0)) == 0
        expect(hwpDisplayMatchNumber(currentIndex: nil, matchCount: 5)) == 0
    }

    /// 클램프를 덧셈보다 먼저 하지 않으면 `Int.max`에서 오버플로 트랩이다.
    nonisolated func testDisplayMatchNumberClampsExtremesWithoutTrapping() {
        expect(hwpDisplayMatchNumber(currentIndex: Int.max, matchCount: 3)) == 3
        expect(hwpDisplayMatchNumber(currentIndex: Int.min, matchCount: 3)) == 1
        expect(hwpDisplayMatchNumber(currentIndex: -5, matchCount: 3)) == 1
        expect(hwpDisplayMatchNumber(currentIndex: 99, matchCount: 3)) == 3
    }

    // MARK: - HwpSearchNavigator

    func testNavigatorAdvancesAndWrapsThroughController() async {
        let (_, search) = Self.attached(pageTexts: ["hit hit"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
        let navigator = HwpSearchNavigator(controller: search)

        navigator.goToNext()
        expect(search.currentMatchIndex) == 1
        navigator.goToNext()
        expect(search.currentMatchIndex) == 0
        navigator.goToPrevious()
        expect(search.currentMatchIndex) == 1
    }

    func testNavigatorIsDisabledWithoutMatches() {
        let (_, search) = Self.attached(pageTexts: ["alpha"])

        expect(HwpSearchNavigator(controller: search).isNavigationDisabled) == true
    }

    // MARK: - HwpSearchBar

    /// 컨트롤러가 질의의 단일 진실이다 — 뷰에 사본을 두면 호스트가
    /// `search(text:)`를 직접 불렀을 때 필드가 낡은 값을 계속 보여 준다.
    func testBarQueryBindingReadsAndWritesThroughController() async {
        let (_, search) = Self.attached(pageTexts: ["alpha beta"])
        let bar = HwpSearchBar(controller: search)

        bar.queryText.wrappedValue = "beta"

        expect(search.query.text) == "beta"
        await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
        expect(bar.queryText.wrappedValue) == "beta"

        // 호스트가 컨트롤러를 직접 조작해도 바인딩이 따라온다
        search.search(text: "alpha")
        expect(bar.queryText.wrappedValue) == "alpha"
    }

    func testBarClearResetsControllerState() async {
        let (_, search) = Self.attached(pageTexts: ["alpha"])
        let bar = HwpSearchBar(controller: search)
        bar.setText("alpha")
        await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

        bar.clearQuery()

        expect(search.matchCount) == 0
        expect(search.query.isEmpty) == true
        expect(search.phase) == .idle
    }

    func testBarDismissClearsAndNotifiesHost() {
        let (_, search) = Self.attached(pageTexts: ["alpha"])
        var dismissed = false
        let bar = HwpSearchBar(controller: search, onDismiss: { dismissed = true })
        bar.setText("alpha")

        bar.dismiss()

        expect(dismissed) == true
        expect(search.query.isEmpty) == true
    }

    func testBarNavigationDelegatesToController() async {
        let (_, search) = Self.attached(pageTexts: ["hit hit hit"])
        let bar = HwpSearchBar(controller: search)
        bar.setText("hit")
        await expect(search.matchCount).toEventually(equal(3), timeout: .seconds(2))

        bar.goToNext()
        expect(search.currentMatchIndex) == 1
        bar.goToPrevious()
        expect(search.currentMatchIndex) == 0
    }

    // MARK: - 상태 문구

    /// "결과 0" / "스캔 중" / "상한에 걸려 잘림"이 서로 다른 문구여야 한다.
    func testStatusTextDistinguishesIdleEmptyAndTruncated() async {
        let (_, search) = Self.attached(pageTexts: ["alpha"])
        let bar = HwpSearchBar(controller: search)
        let idle = bar.statusText

        bar.setText("zebra")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        let empty = bar.statusText

        search.matchLimit = 1
        bar.setText("a")
        await expect(search.phase).toEventually(equal(.truncated), timeout: .seconds(2))
        let truncated = bar.statusText

        expect(idle) != empty
        expect(empty) != truncated
    }
}
