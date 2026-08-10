import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 검색 세션(#75) — 단계 전이·증분 재스캔·순환 탐색·클램프 방어·축출 훅.
@MainActor
final class HwpSearchControllerTests: XCTestCase {
    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private static func textBlock(_ text: String) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            role: .body
        )
    }

    private static func document(
        pageTexts: [String], loadToken: UUID? = nil
    ) -> HwpDocument {
        HwpDocument(
            pages: pageTexts.enumerated().map { index, text in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [Self.textBlock(text)],
                    pageNumber: index + 1
                )
            },
            metadata: HwpDocumentMetadata(pageCount: pageTexts.count, loadToken: loadToken),
            unsupportedElements: []
        )
    }

    /// 스캔은 Task로 돌므로 완료를 기다린다. 발행 코얼레싱을 끄고
    /// (`publishInterval = .zero`) 결정론적으로 만든다.
    private static func makeAttached(
        pageTexts: [String], loadToken: UUID? = nil
    ) -> (HwpSelectionController, HwpSearchController) {
        let selection = HwpSelectionController()
        selection.setDocument(
            Self.document(pageTexts: pageTexts, loadToken: loadToken),
            preservingSelection: false
        )
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.attach(to: selection)
        return (selection, search)
    }

    // MARK: - 단계 전이

    func testIdleWhileQueryIsEmpty() {
        let (_, search) = Self.makeAttached(pageTexts: ["alpha"])

        expect(search.phase) == .idle
        expect(search.matchCount) == 0
        expect(search.currentMatchIndex).to(beNil())
    }

    func testCompletesScanAndSelectsFirstMatch() async {
        let (_, search) = Self.makeAttached(pageTexts: ["alpha beta", "beta gamma"])

        search.search(text: "beta")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 2
        expect(search.currentMatchIndex) == 0
        expect(search.currentMatch?.pageNumber) == 1
        expect(search.scannedPageCount) == 2
        expect(search.pageCount) == 2
    }

    func testCompletesWithZeroMatches() async {
        let (_, search) = Self.makeAttached(pageTexts: ["alpha"])

        search.search(text: "nothing")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 0
        expect(search.currentMatchIndex).to(beNil())
    }

    /// `.truncated`가 `.complete`와 갈리는 것이 이 상태의 존재 이유다 —
    /// 표시된 개수가 전부가 아니라는 사실을 호스트가 알아야 한다.
    func testTruncatesAtMatchLimit() async {
        let (_, search) = Self.makeAttached(
            pageTexts: (0 ..< 5).map { _ in "hit hit hit hit" }
        )
        search.matchLimit = 6

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.truncated), timeout: .seconds(2))
        expect(search.matchCount) == 6
    }

    // MARK: - 증분 재스캔

    /// 프로그레시브 스냅샷마다 전량 재스캔하면 1,030쪽 전개가 스냅샷 수만큼
    /// 반복된다. append면 늘어난 구간만 본다.
    func testProgressiveAppendScansOnlyNewPages() async {
        let token = UUID()
        let (selection, search) = Self.makeAttached(
            pageTexts: ["hit one", "hit two"], loadToken: token
        )
        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 2

        selection.setDocument(
            Self.document(
                pageTexts: ["hit one", "hit two", "hit three", "hit four"],
                loadToken: token
            ),
            preservingSelection: true
        )

        await expect(search.matchCount).toEventually(equal(4), timeout: .seconds(2))
        expect(search.phase) == .complete
        // 앞 두 페이지를 다시 훑지 않았다 — scannedPageCount는 새 구간의 끝이다
        expect(search.scannedPageCount) == 4
        expect(search.matches.map(\.pageNumber)) == [1, 2, 3, 4]
    }

    func testDocumentReplacementRescansFromScratch() async {
        let (selection, search) = Self.makeAttached(
            pageTexts: ["hit one"], loadToken: UUID()
        )
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

        selection.setDocument(
            Self.document(pageTexts: ["hit a", "hit b"], loadToken: UUID()),
            preservingSelection: false
        )

        await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
        expect(search.phase) == .complete
    }

    func testDetachClearsGeometryDependentState() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

        search.detach()

        expect(search.pageCount) == 0
        expect(search.scannedPageCount) == 0
    }

    // MARK: - 탐색

    func testNextAndPreviousWrapAround() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit", "hit"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(3), timeout: .seconds(2))

        expect(search.currentMatchIndex) == 0
        search.next()
        expect(search.currentMatchIndex) == 1
        search.next()
        expect(search.currentMatchIndex) == 2
        search.next()
        expect(search.currentMatchIndex) == 0
        search.previous()
        expect(search.currentMatchIndex) == 2
    }

    func testNavigationIsNoOpWithoutMatches() {
        let (_, search) = Self.makeAttached(pageTexts: ["alpha"])

        search.next()
        search.previous()
        search.select(matchIndex: 3)

        expect(search.currentMatchIndex).to(beNil())
    }

    /// 공개 진입점이라 임의 값이 들어온다 — 클램프를 산술보다 먼저 해야
    /// `Int.min`이 트랩하지 않는다.
    func testSelectClampsExtremeIndicesWithoutTrapping() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit hit"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(3), timeout: .seconds(2))

        search.select(matchIndex: Int.min)
        expect(search.currentMatchIndex) == 0
        search.select(matchIndex: Int.max)
        expect(search.currentMatchIndex) == 2
        search.select(matchIndex: -1)
        expect(search.currentMatchIndex) == 0
        search.select(matchIndex: 999)
        expect(search.currentMatchIndex) == 2
    }

    func testCurrentMatchChangedFiresOnNavigation() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit"])
        var reported: [Int] = []
        search.onCurrentMatchChanged = { match in
            reported.append(match?.selection.range.start.characterOffset ?? -1)
        }
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))

        search.next()

        expect(reported.last) == 4
    }

    // MARK: - 목록 vs 하이라이트

    /// 목록은 dedup, 하이라이트는 전량 — 기존 `plainText` 정책과 같다.
    func testHighlightListKeepsClonesThatMatchListDrops() async {
        let selection = HwpSelectionController()
        let cloneAttributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: Self.font,
            HwpAttributedStringKey.repeatedTableHeaderClone: true,
        ]
        let origin = AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(
                string: "header",
                attributes: [kCTFontAttributeName as NSAttributedString.Key: Self.font]
            ),
            source: HwpBlockSource(paragraphId: 7),
            role: .body
        )
        let clone = AnyHwpBlock(
            frame: CGRect(x: 10, y: 60, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(string: "header", attributes: cloneAttributes),
            source: HwpBlockSource(paragraphId: 7),
            role: .body
        )
        selection.setDocument(
            HwpDocument(
                pages: [HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [origin, clone],
                    pageNumber: 1
                )],
                metadata: HwpDocumentMetadata(pageCount: 1),
                unsupportedElements: []
            ),
            preservingSelection: false
        )
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.attach(to: selection)

        search.search(text: "header")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matches.count) == 1
        expect(search.highlightMatches.count) == 2
    }

    // MARK: - revision

    func testRevisionIncreasesMonotonicallyOnPublishAndNavigation() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit"])
        let initial = search.revision

        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
        let afterScan = search.revision
        search.next()

        expect(afterScan) > initial
        expect(search.revision) > afterScan
    }

    // MARK: - 캐시 축출 훅

    /// nil이면 축출하지 않는다 — 엔진만 쓰는 배치 인덱싱은 전량 상주가 맞다.
    func testDoesNotEvictWhenNoRetainedRangeProvided() async {
        let (selection, search) = Self.makeAttached(
            pageTexts: (0 ..< 40).map { "hit page \($0)" }
        )

        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))

        expect(selection.geometry?.unitCache.count) == 40
    }

    func testEvictsScannedUnitsOutsideRetainedRange() async {
        let (selection, search) = Self.makeAttached(
            pageTexts: (0 ..< 40).map { "hit page \($0)" }
        )
        search.retainedPageRange = { 0 ..< 3 }

        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))

        expect(search.matchCount) == 40
        expect(selection.geometry?.unitCache.count) == 3
    }

    // MARK: - clear

    func testClearResetsEverything() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit"])
        search.search(text: "hit")
        await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

        search.clear()

        expect(search.matchCount) == 0
        expect(search.highlightMatches).to(beEmpty())
        expect(search.currentMatchIndex).to(beNil())
        expect(search.phase) == .idle
        expect(search.query.isEmpty) == true
    }
}
