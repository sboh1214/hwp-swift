import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 검색 엔진(#75) — 매치 좌표계·스코프·옵션·상한·dedup·스니펫.
final class HwpTextSearcherTests: XCTestCase {
    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private static func attributed(_ text: String, clone: Bool = false) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: Self.font,
        ]
        if clone {
            attributes[HwpAttributedStringKey.repeatedTableHeaderClone] = true
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func textBlock(
        _ text: String,
        y: CGFloat = 20,
        role: HwpBlockRole = .body,
        paragraphId: UInt32? = nil,
        clone: Bool = false
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: CGRect(x: 10, y: y, width: 400, height: 20),
            kind: .text,
            attributedString: attributed(text, clone: clone),
            source: paragraphId.map { HwpBlockSource(paragraphId: $0) },
            role: role
        )
    }

    private static func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: blocks,
            pageNumber: 1
        )
    }

    private static func find(
        _ text: String,
        in blocks: [AnyHwpBlock],
        options: HwpSearchOptions = .default,
        matchLimit: Int = 0,
        snippetPadding: Int = 0
    ) -> [HwpSearchMatch] {
        HwpTextSearcher.matches(
            in: page(blocks),
            pageIndex: 0,
            query: HwpSearchQuery(text: text, options: options),
            matchLimit: matchLimit,
            snippetPadding: snippetPadding
        )
    }

    // MARK: - 좌표계

    /// 매치 위치는 배열 ordinal이 아니라 `blockIndex`/`unitIndex` 기준이다.
    /// `unitIndex`는 블록마다 0으로 리셋되므로 둘을 함께 봐야 단위가 정해진다.
    func testMatchPositionUsesBlockAndUnitIndexNotArrayOrdinal() {
        let matches = Self.find("target", in: [
            Self.textBlock("nothing here", y: 20),
            Self.textBlock("a target word", y: 60),
        ])

        expect(matches.count) == 1
        let start = matches[0].selection.range.start
        expect(start.pageIndex) == 0
        expect(start.blockIndex) == 1
        expect(start.unitIndex) == 0
        expect(start.characterOffset) == 2
        expect(matches[0].selection.range.end.characterOffset) == 8
    }

    func testPageNumberIsOneBasedAndPageIndexIsZeroBased() {
        let matches = HwpTextSearcher.matches(
            in: Self.page([Self.textBlock("hit")]),
            pageIndex: 7,
            query: HwpSearchQuery(text: "hit")
        )

        expect(matches[0].pageIndex) == 7
        expect(matches[0].pageNumber) == 8
    }

    /// 스캐너 출력은 별도 정렬 없이 이미 문서 순서다.
    func testResultsAreInDocumentOrderWithoutSorting() {
        let matches = Self.find("x", in: [
            Self.textBlock("x a x", y: 20),
            Self.textBlock("x b", y: 60),
        ])

        expect(matches.count) == 3
        expect(matches) == matches.sorted()
    }

    // MARK: - 스코프

    func testPageChromeIsNotSearched() {
        let matches = Self.find("page", in: [
            Self.textBlock("body page", y: 20),
            Self.textBlock("page footer", y: 800, role: .pageChrome),
        ])

        expect(matches.count) == 1
        expect(matches[0].selection.range.start.blockIndex) == 0
    }

    func testEmptyQueryMatchesNothing() {
        expect(Self.find("", in: [Self.textBlock("anything")])).to(beEmpty())
        expect(Self.find("   ", in: [Self.textBlock("anything")])).to(beEmpty())
    }

    // MARK: - 옵션

    func testCaseInsensitiveByDefaultAndCaseSensitiveWhenCleared() {
        expect(Self.find("HELLO", in: [Self.textBlock("hello world")]).count) == 1
        expect(Self.find("HELLO", in: [Self.textBlock("hello world")], options: []))
            .to(beEmpty())
    }

    func testWholeWordUsesSameBoundaryRuleAsDoubleClickSelection() {
        let blocks = [Self.textBlock("cat category cat.")]

        let loose = Self.find("cat", in: blocks)
        let strict = Self.find("cat", in: blocks, options: [.caseInsensitive, .wholeWord])

        expect(loose.count) == 3
        // "category"의 접두 cat은 뒤가 단어 문자라 빠지고, 마침표 앞 cat은 남는다
        expect(strict.count) == 2
        expect(strict.map(\.selection.range.start.characterOffset)) == [0, 13]
    }

    /// 겹치는 매치는 보고하지 않는다 — 편집기 관례대로 비겹침 스캔이다.
    func testOverlappingOccurrencesAreNotDoubleReported() {
        let matches = Self.find("aa", in: [Self.textBlock("aaaa")])

        expect(matches.count) == 2
        expect(matches.map(\.selection.range.start.characterOffset)) == [0, 2]
    }

    // MARK: - 상한

    func testMatchLimitStopsScanEarly() {
        let blocks = (0 ..< 10).map { index in
            Self.textBlock("hit hit hit", y: CGFloat(20 + index * 30))
        }

        let limited = Self.find("hit", in: blocks, matchLimit: 5)
        let unlimited = Self.find("hit", in: blocks)

        expect(limited.count) == 5
        expect(unlimited.count) == 30
        // 조기 종료라 앞에서부터 정확히 상한만큼이다
        expect(limited) == Array(unlimited.prefix(5))
    }

    func testZeroMatchLimitMeansUnlimited() {
        let matches = Self.find("a", in: [Self.textBlock(String(repeating: "a ", count: 50))],
                                matchLimit: 0)

        expect(matches.count) == 50
    }

    // MARK: - 반복 표 머리행 dedup

    /// 클론 단위의 매치는 **통째로** 남거나 통째로 빠진다. 매치 단위로
    /// 판정하면 같은 클론 행의 두 번째 매치가 첫 매치 때문에 사라진다.
    func testDedupDropsCloneUnitWholeWhenOriginAlreadyContributed() {
        let matches = Self.find("h", in: [
            Self.textBlock("h and h", y: 20, paragraphId: 100),
            Self.textBlock("h and h", y: 60, paragraphId: 100, clone: true),
        ])
        expect(matches.count) == 4

        let deduped = HwpTextSearcher.deduplicatingRepeatedTableHeaders(matches)

        expect(deduped.count) == 2
        expect(deduped.allSatisfy { $0.selection.range.start.blockIndex == 0 }) == true
    }

    /// 원본이 매치되지 않았으면 클론을 남긴다 — `plainText`의 '먼저 나온 것을
    /// 살린다' 규약과 같은 의미다.
    func testDedupKeepsCloneWhenOriginNeverContributed() {
        let matches = Self.find("zebra", in: [
            Self.textBlock("no match here", y: 20, paragraphId: 100),
            Self.textBlock("zebra and zebra", y: 60, paragraphId: 100, clone: true),
        ])
        expect(matches.count) == 2

        let deduped = HwpTextSearcher.deduplicatingRepeatedTableHeaders(matches)

        expect(deduped.count) == 2
        expect(deduped.allSatisfy(\.isRepeatedTableHeaderClone)) == true
    }

    /// 같은 텍스트라도 paraId가 다르면 데이터 셀이므로 남긴다.
    func testDedupDoesNotDropDifferentParagraphsWithSameText() {
        let matches = Self.find("same", in: [
            Self.textBlock("same", y: 20, paragraphId: 1),
            Self.textBlock("same", y: 60, paragraphId: 2, clone: true),
        ])

        let deduped = HwpTextSearcher.deduplicatingRepeatedTableHeaders(matches)

        expect(deduped.count) == 2
    }

    func testDedupIsIdentityOnNonCloneInput() {
        let matches = Self.find("a", in: [
            Self.textBlock("a a", y: 20, paragraphId: 1),
            Self.textBlock("a", y: 60, paragraphId: 2),
        ])

        expect(HwpTextSearcher.deduplicatingRepeatedTableHeaders(matches)) == matches
    }

    // MARK: - 스니펫

    func testSnippetIsNilUnlessPaddingRequested() {
        expect(Self.find("mid", in: [Self.textBlock("left mid right")])[0].snippet).to(beNil())
    }

    /// `snippetPadding` 은 공개 인자다 — 극단값에 트랩하면 안 된다. `min` 이
    /// 자르기 전에 `location + length + padding` 이 먼저 터진다 (#75 리뷰 3차).
    func testExtremeSnippetPaddingDoesNotTrap() {
        let matches = Self.find(
            "mid", in: [Self.textBlock("left mid right")], snippetPadding: .max
        )

        expect(matches.count) == 1
        expect(matches[0].snippet?.text) == "left mid right"
    }

    func testSnippetCarriesMatchRangeWithinItsOwnText() {
        let matches = Self.find(
            "mid", in: [Self.textBlock("aaaaa left mid right bbbbb")], snippetPadding: 5
        )

        let snippet = matches[0].snippet
        expect(snippet).toNot(beNil())
        guard let snippet else { return }
        let nsText = snippet.text as NSString
        let highlighted = nsText.substring(
            with: NSRange(
                location: snippet.matchRange.lowerBound,
                length: snippet.matchRange.count
            )
        )
        expect(highlighted) == "mid"
    }

    func testSnippetClampsAtStringBounds() {
        let matches = Self.find("ab", in: [Self.textBlock("ab")], snippetPadding: 50)

        expect(matches[0].snippet?.text) == "ab"
        expect(matches[0].snippet?.matchRange) == 0 ..< 2
    }

    // MARK: - 단위 배열 오버로드

    /// 두 오버로드는 같은 결과를 낸다 — 하나는 캐시 공유, 하나는 오프메인용이다.
    func testUnitsOverloadMatchesPageOverload() {
        let blocks = [Self.textBlock("alpha beta", y: 20), Self.textBlock("beta gamma", y: 60)]
        let units = HwpSelectableText.units(in: Self.page(blocks))

        let viaUnits = HwpTextSearcher.matches(
            in: units, pageIndex: 3, query: HwpSearchQuery(text: "beta")
        )
        let viaPage = HwpTextSearcher.matches(
            in: Self.page(blocks), pageIndex: 3, query: HwpSearchQuery(text: "beta")
        )

        expect(viaUnits) == viaPage
        expect(viaUnits.count) == 2
    }
}
