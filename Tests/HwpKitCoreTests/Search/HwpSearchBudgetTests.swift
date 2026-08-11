import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 검색 예산(#75) — 매치 상한과 단위 캐시 축출.
///
/// `HwpSearchControllerTests` 에서 갈라 나왔다. 나누는 축은 AGENTS.md 가
/// "예산 (성능 — 결과의 **의미**를 바꾸지 않는다)"으로 묶어 둔 그 경계다.
@MainActor
final class HwpSearchBudgetTests: XCTestCase {
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
        pageTexts: [String], loadToken: UUID? = nil, isComplete: Bool = true
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
            metadata: HwpDocumentMetadata(
                pageCount: pageTexts.count, loadToken: loadToken, isComplete: isComplete
            ),
            unsupportedElements: []
        )
    }

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

    // MARK: - 매치 상한

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

    /// 상한과 총계가 정확히 같으면 빠뜨린 것이 없다 — `count >= limit` 로
    /// 판정하면 검색 바가 "1 of 1+"를 띄운다 (#75 리뷰 3차).
    func testExactMatchLimitReportsCompleteNotTruncated() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit"])
        search.matchLimit = 1

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 1
    }

    /// 넘침 증거(probe 로 본 상한+1)는 발행 접두에 남지 않는다 — append 가
    /// 거기서 이어받으므로 상태로 지속하지 않으면 뒤 페이지에 매치가 없을 때
    /// "1 of 1+"가 "1 of 1"로 뒤집힌다 (#75 리뷰 4차).
    func testTruncationSurvivesProgressiveAppends() async {
        let token = UUID()
        let selection = HwpSelectionController()
        selection.setDocument(
            Self.document(pageTexts: ["hit hit"], loadToken: token, isComplete: false),
            preservingSelection: false
        )
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.matchLimit = 1
        search.attach(to: selection)
        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.truncated), timeout: .seconds(2))

        // 매치가 없는 페이지가 붙어도 절단은 그대로다
        selection.setDocument(
            Self.document(
                pageTexts: ["hit hit", "nothing here"], loadToken: token, isComplete: false
            ),
            preservingSelection: true
        )

        await expect(search.phase).toEventuallyNot(equal(.scanning), timeout: .seconds(2))
        expect(search.phase) == .truncated

        // 동일 개수 최종 스냅샷(빈 구간 append)도 마찬가지다
        selection.setDocument(
            Self.document(
                pageTexts: ["hit hit", "nothing here"], loadToken: token, isComplete: true
            ),
            preservingSelection: true
        )

        await expect(search.phase).toEventuallyNot(equal(.scanning), timeout: .seconds(2))
        expect(search.phase) == .truncated
        expect(search.matchCount) == 1
    }

    /// 상한을 하나 넘겨 훑으므로 `Int.max` 에서 덧셈이 터지지 않아야 한다.
    func testExtremeMatchLimitDoesNotTrap() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit"])
        search.matchLimit = .max

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matchCount) == 2
    }

    private static func paragraphBlock(
        _ text: String, y: CGFloat, paragraphId: UInt32, clone: Bool
    ) -> AnyHwpBlock {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
        ]
        if clone {
            attributes[HwpAttributedStringKey.repeatedTableHeaderClone] = true
        }
        return AnyHwpBlock(
            frame: CGRect(x: 10, y: y, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(string: text, attributes: attributes),
            source: HwpBlockSource(paragraphId: paragraphId),
            role: .body
        )
    }

    private static func makeAttached(
        blocks: [AnyHwpBlock], matchLimit: Int
    ) -> (HwpSelectionController, HwpSearchController) {
        let selection = HwpSelectionController()
        selection.setDocument(
            HwpDocument(
                pages: [HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: blocks,
                    pageNumber: 1
                )],
                metadata: HwpDocumentMetadata(pageCount: 1),
                unsupportedElements: []
            ),
            preservingSelection: false
        )
        let search = HwpSearchController()
        search.publishInterval = .zero
        search.matchLimit = matchLimit
        search.attach(to: selection)
        return (selection, search)
    }

    /// 예산은 **목록 기준**이다. 클론이 상한을 쓰면 뒤의 고유 매치가 노출되지
    /// 않고, 빠뜨린 고유 매치가 없는데도 잘렸다고 보고한다 (#75 리뷰 6차).
    func testMatchLimitCountsDeduplicatedResults() async {
        let (_, search) = Self.makeAttached(
            blocks: [
                Self.paragraphBlock("header", y: 20, paragraphId: 7, clone: false),
                Self.paragraphBlock("header", y: 60, paragraphId: 7, clone: true),
                Self.paragraphBlock("header", y: 100, paragraphId: 8, clone: false),
            ],
            matchLimit: 2
        )

        search.search(text: "header")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        // 고유 매치 둘이 상한에 들어간다 — 클론이 자리를 차지하지 않는다
        expect(search.matchCount) == 2
        expect(search.matches.map(\.paragraphId)) == [7, 8]
        // 하이라이트에는 클론이 그대로 남는다
        expect(search.highlightMatches.count) == 3
    }

    /// 한 쪽 안에서도 자르는 지점은 **단위 경계**여야 한다. 클론이 raw 예산을
    /// 채우면 그 쪽의 뒤 단위가 통째로 안 훑기는데, dedup 이 클론을 버려 목록은
    /// 안 늘고 절단 표시도 안 서므로 고유 매치가 조용히 빠진 채 `.complete` 로
    /// 발행된다 (#75 리뷰 7차).
    func testClonesDoNotStarveLaterUnitsOnSamePage() async {
        let (_, search) = Self.makeAttached(
            blocks: [
                Self.paragraphBlock("hit", y: 20, paragraphId: 7, clone: false),
                Self.paragraphBlock("hit hit hit", y: 60, paragraphId: 7, clone: true),
                Self.paragraphBlock("hit", y: 100, paragraphId: 9, clone: false),
            ],
            matchLimit: 2
        )

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(search.matches.map(\.paragraphId)) == [7, 9]
        expect(search.highlightMatches.count) == 5
    }

    /// 절단 감지용 프로브(상한+1)가 발행된 하이라이트에 남으면 **탐색할 수
    /// 없는 자리**가 칠해진다 — 두 목록의 차이는 클론뿐이라는 계약이 깨진다
    /// (#75 리뷰 10차).
    func testTruncationDoesNotPaintUnreachableMatch() async {
        let (_, search) = Self.makeAttached(pageTexts: ["hit hit"])
        search.matchLimit = 1

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.truncated), timeout: .seconds(2))
        expect(search.matchCount) == 1
        expect(search.highlightMatches.count) == 1
    }

    /// 빠지는 것은 프로브뿐이다 — 잘린 지점 **앞**의 클론 하이라이트는 남는다.
    func testTruncationKeepsCloneHighlightsBeforeCut() async {
        let (_, search) = Self.makeAttached(
            blocks: [
                Self.paragraphBlock("hit", y: 20, paragraphId: 7, clone: false),
                Self.paragraphBlock("hit", y: 60, paragraphId: 7, clone: true),
                Self.paragraphBlock("hit", y: 100, paragraphId: 9, clone: false),
            ],
            matchLimit: 1
        )

        search.search(text: "hit")

        await expect(search.phase).toEventually(equal(.truncated), timeout: .seconds(2))
        expect(search.matches.map(\.paragraphId)) == [7]
        // 원본 + 클론 = 2. 초과분(paraId 9)만 빠진다
        expect(search.highlightMatches.count) == 2
    }

    // MARK: - 스캔 중 상주

    /// 스캔이 도는 동안 소유자가 컨트롤러를 놓으면 **그 자리에서** 풀려야 한다.
    /// `await self?.runScan(...)` 처럼 async 메서드를 통째로 부르면 옵셔널
    /// 체이닝이 호출 전 구간 강한 참조를 잡아, 스캔이 끝날 때까지 컨트롤러가
    /// 선택 컨트롤러를, 그것이 다시 문서 전체를 붙든다 (#75 리뷰 11차).
    func testDroppingControllerMidScanReleasesIt() async {
        weak var observed: HwpSearchController?
        do {
            let selection = HwpSelectionController()
            selection.setDocument(
                Self.document(pageTexts: (0 ..< 400).map { "hit page \($0)" }),
                preservingSelection: false
            )
            let search = HwpSearchController()
            search.publishInterval = .zero
            search.attach(to: selection)
            search.search(text: "hit")
            observed = search
            // 첫 배치를 돌고 양보하게 둔다 — 이 시점에 스캔은 진행 중이다
            await Task.yield()
            expect(observed).toNot(beNil())
        }

        expect(observed).to(beNil())
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

    /// 스캔 중 축출만으로는 상한이 서지 않는다 — 스캔이 끝난 뒤에도 하이라이트
    /// 조회가 페이지마다 단위를 다시 전개해 캐시에 넣기 때문이다. 뷰가 가시
    /// 범위를 바꿀 때 부르는 훅이 그것을 되돌린다 (#75 리뷰 5차).
    func testEvictHookTrimsUnitsRepopulatedAfterScan() async {
        let (selection, search) = Self.makeAttached(
            pageTexts: (0 ..< 40).map { "hit page \($0)" }
        )
        search.retainedPageRange = { 0 ..< 3 }
        search.search(text: "hit")
        await expect(search.phase).toEventually(equal(.complete), timeout: .seconds(2))
        expect(selection.geometry?.unitCache.count) == 3

        // 스캔이 끝난 뒤 스크롤이 하는 일 — 페이지마다 하이라이트를 묻는다
        for page in 0 ..< 40 {
            _ = search.highlightRects(forPage: page)
        }
        expect(selection.geometry?.unitCache.count) == 40

        search.evictUnitsOutsideRetainedRange()

        expect(selection.geometry?.unitCache.count) == 3
    }
}
