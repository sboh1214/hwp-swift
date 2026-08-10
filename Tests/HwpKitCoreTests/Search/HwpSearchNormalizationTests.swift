import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 한글 정규화와 매칭 좌표계의 함정(#75).
///
/// `HwpSearchQuery.compareOptions`는 `.literal`을 넣지 않는다. 덕분에 조합형
/// (NFD)과 완성형(NFC)이 동치로 비교되지만, 그 대가로 **반환 range의 길이가
/// 질의의 UTF-16 길이와 다를 수 있다.** 하이라이트 오프셋을
/// `location + query.utf16.count`로 계산하면 조용히 어긋난다 — 이 파일이 그
/// 계약을 잠근다.
final class HwpSearchNormalizationTests: XCTestCase {
    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private static func matches(in text: String, for query: String) -> [HwpSearchMatch] {
        let block = AnyHwpBlock(
            frame: CGRect(x: 10, y: 20, width: 400, height: 20),
            kind: .text,
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: Self.font]
            ),
            role: .body
        )
        let page = HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: [block],
            pageNumber: 1
        )
        return HwpTextSearcher.matches(
            in: page, pageIndex: 0, query: HwpSearchQuery(text: query)
        )
    }

    /// 매치 오프셋으로 원문을 잘라내면 **정확히 매치 구간**이 나와야 한다.
    /// 길이를 질의에서 유도하면 이 단언이 깨진다.
    private static func slice(_ match: HwpSearchMatch, of text: String) -> String {
        let range = match.selection.range
        return (text as NSString).substring(
            with: NSRange(
                location: range.start.characterOffset,
                length: range.end.characterOffset - range.start.characterOffset
            )
        )
    }

    // MARK: - 한글 정규 동치

    func testPrecomposedQueryFindsDecomposedText() {
        let decomposed = "한글".decomposedStringWithCanonicalMapping
        let found = Self.matches(in: "문서 \(decomposed) 검색", for: "한글")

        expect(found.count) == 1
        // NFD 원문에서 잘라낸 구간은 UTF-16 길이가 질의(2)보다 길다
        expect(Self.slice(found[0], of: "문서 \(decomposed) 검색"))
            == "한글".decomposedStringWithCanonicalMapping
    }

    func testDecomposedQueryFindsPrecomposedText() {
        let text = "문서 한글 검색"
        let found = Self.matches(in: text, for: "한글".decomposedStringWithCanonicalMapping)

        expect(found.count) == 1
        expect(Self.slice(found[0], of: text)) == "한글"
    }

    /// 이 테스트가 이 파일의 존재 이유다 — NFD 원문에서 NFC 질의의 매치는
    /// 질의보다 **긴** UTF-16 범위를 차지한다.
    func testMatchLengthCanDifferFromQueryUTF16Length() {
        let decomposed = "한글".decomposedStringWithCanonicalMapping
        let found = Self.matches(in: decomposed, for: "한글")

        expect(found.count) == 1
        let range = found[0].selection.range
        let matchedLength = range.end.characterOffset - range.start.characterOffset
        expect("한글".utf16.count) == 2
        expect(matchedLength) == decomposed.utf16.count
        expect(matchedLength) > "한글".utf16.count
    }

    // MARK: - 대소문자·발음 구별 부호

    func testDiacriticInsensitiveByDefault() {
        let text = "café résumé"
        let found = Self.matches(in: text, for: "cafe")

        expect(found.count) == 1
        expect(Self.slice(found[0], of: text)) == "café"
    }

    // MARK: - 비-BMP

    /// 서로게이트 쌍을 쪼개지 않는다.
    func testSurrogatePairMatchKeepsWholeScalar() {
        let text = "before 𝕏 after"
        let found = Self.matches(in: text, for: "𝕏")

        expect(found.count) == 1
        expect(Self.slice(found[0], of: text)) == "𝕏"
    }

    // MARK: - U+FFFC

    /// 개체 자리 표시 마커는 매칭 문자열에 **남아 있다** — `plainText`만
    /// 제거한다. 하이라이트 오프셋 정합을 위해 감수하는 한계다.
    func testObjectReplacementMarkerRemainsInMatchableText() {
        let text = "left\u{FFFC}right"
        let found = Self.matches(in: text, for: "right")

        expect(found.count) == 1
        expect(found[0].selection.range.start.characterOffset) == 5
    }
}
