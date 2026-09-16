import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// `HwpDrawnLine.endsParagraph` — 문단의 마지막 줄 판정 (#187 PR 리뷰: MS 워드 호환 문단
/// 끝 상자를 마지막 줄에만 합치는 열쇠). 양쪽 정렬의 마지막 줄 판정과 같은 규약이다.
final class HwpDrawnLineParagraphEndTests: XCTestCase {
    private func lines(_ text: NSAttributedString, width: CGFloat) -> [HwpDrawnLine] {
        HwpDrawnTextLayout.lines(attributedString: text, origin: .zero, lineWidth: width)
    }

    private var menlo: [NSAttributedString.Key: Any] {
        let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)
        return [kCTFontAttributeName as NSAttributedString.Key: font]
    }

    private let wrapping = "AAAAAAAAA AAAAAAAAA AAAAAAAAA AAAAAAAAA"

    /// 두 줄로 접힌 문단은 끝 줄만 참이고, 한 줄 문단(한 줄 넘침 경로 포함)은 그 줄이 참이다.
    func testOnlyTheLineReachingTheStringEndEndsTheParagraph() {
        let wrapped = lines(NSAttributedString(string: wrapping, attributes: menlo), width: 200)
        expect(wrapped.count) == 2
        expect(wrapped.map(\.endsParagraph)) == [false, true]
        let single = lines(NSAttributedString(string: "AAAA", attributes: menlo), width: 200)
        expect(single.map(\.endsParagraph)) == [true]
        // 폭을 살짝 넘는 개행 없는 한 줄(slight-overflow 경로)도 마지막 줄이다.
        let overflow = lines(
            NSAttributedString(string: "AAAAAAAAAAAAAAAAAAAA", attributes: menlo), width: 118
        )
        expect(overflow.count) == 1
        expect(overflow.map(\.endsParagraph)) == [true]
    }

    /// 이어짐 표식(`HwpTableSplitter.markedAsContinuedFragment`)은 조각 전체에 붙어 글리프
    /// 조합 경계를 만들지 않는다 — `a😀`에 붙여도 CoreText run이 표식 없는 문자열과 같고,
    /// 첫 글자와 끝 글자 모두 표식을 가지며, 그 줄은 문단의 마지막 줄이 아니다.
    func testContinuedMarkerCoversTheWholeFragmentWithoutSplittingGlyphs() throws {
        let plain = NSAttributedString(string: "a😀", attributes: menlo)
        let marked = HwpTableSplitter.markedAsContinuedFragment(plain)
        func runs(_ text: NSAttributedString) throws -> [(Int, Int)] {
            let line = CTLineCreateWithAttributedString(text)
            return try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun]).map {
                (CTRunGetStringRange($0).location, CTRunGetStringRange($0).length)
            }
        }
        expect(try runs(marked).map(\.0)) == (try runs(plain).map(\.0))
        expect(try runs(marked).map(\.1)) == (try runs(plain).map(\.1))
        for location in [0, marked.length - 1] {
            expect(marked.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: location, effectiveRange: nil
            )).toNot(beNil(), description: "\(location)")
        }
        expect(self.lines(marked, width: 200).map(\.endsParagraph)) == [false]
    }

    /// 다음 단·쪽으로 이어지는 조각(`continuedParagraphFragment`)의 끝 줄은 마지막 줄이 아니다.
    func testContinuedFragmentNeverEndsTheParagraph() {
        let text = NSMutableAttributedString(string: wrapping, attributes: menlo)
        text.addAttribute(
            HwpAttributedStringKey.continuedParagraphFragment, value: NSNumber(value: true),
            range: NSRange(location: text.length - 1, length: 1)
        )
        let wrapped = lines(text, width: 200)
        expect(wrapped.count) == 2
        expect(wrapped.map(\.endsParagraph)) == [false, false]
    }
}
