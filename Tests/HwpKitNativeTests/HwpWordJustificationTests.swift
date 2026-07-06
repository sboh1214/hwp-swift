import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitNative
import Nimble
import XCTest

/// 양쪽 정렬의 한글식 재조판 (남는 폭을 공백에만 배분) 테스트.
final class HwpWordJustificationTests: XCTestCase {
    private func justifiedString(_ text: String) -> NSAttributedString {
        var alignment = CTTextAlignment.justified
        let style = withUnsafeMutablePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointer
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName("Helvetica" as CFString, 12, nil),
            kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
        ])
    }

    /// 프레임 첫 줄을 얻는다 (두 줄 이상으로 감싸는 좁은 폭).
    private func firstLine(
        of attributed: NSAttributedString,
        width: CGFloat
    ) -> CTLine? {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: width, height: 1000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        return (CTFrameGetLines(frame) as? [CTLine])?.first
    }

    /// 남는 폭 전부가 공백에 들어간다: 재조판 줄의 폭 == 목표 폭,
    /// 공백 앞뒤 단어의 글리프 간격 (자간)은 자연 조판과 동일해야 한다.
    func testExtraWidthGoesIntoSpacesOnly() throws {
        let attributed = justifiedString("alpha beta gamma delta epsilon zeta")
        let width: CGFloat = 120
        let line = try XCTUnwrap(firstLine(of: attributed, width: width))
        let range = CTLineGetStringRange(line)
        expect(range.length) < attributed.length // 두 줄 이상으로 감쌌다

        let replacement = HwpWordJustification.wordJustifiedLine(
            frameLine: line,
            attributedString: attributed,
            availableWidth: width
        )
        expect(replacement).toNot(beNil())
        guard let replacement else { return }

        // 재조판 줄이 목표 폭을 채운다
        let filledWidth = CGFloat(CTLineGetTypographicBounds(replacement, nil, nil, nil))
            - CGFloat(CTLineGetTrailingWhitespaceWidth(replacement))
        expect(filledWidth).to(beCloseTo(width, within: 0.6))

        // 첫 단어 ("alpha")의 폭은 자연 조판과 같다 — 글자 사이는 늘리지 않았다
        let firstWord = attributed.attributedSubstring(
            from: NSRange(location: 0, length: 5)
        )
        let naturalFirstWord = CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(firstWord), nil, nil, nil
        ))
        let offsetAfterFirstWord = CTLineGetOffsetForStringIndex(replacement, 5, nil)
        expect(offsetAfterFirstWord).to(beCloseTo(naturalFirstWord, within: 0.5))
    }

    /// 문단 마지막 줄과 공백 없는 줄은 재조판하지 않는다.
    func testLastLineAndSpacelessLinesAreLeftAlone() throws {
        let attributed = justifiedString("alpha beta gamma delta epsilon zeta")
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 120, height: 1000), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        let lines = try XCTUnwrap(CTFrameGetLines(frame) as? [CTLine])
        let lastLine = try XCTUnwrap(lines.last)
        expect(HwpWordJustification.wordJustifiedLine(
            frameLine: lastLine,
            attributedString: attributed,
            availableWidth: 120
        )).to(beNil())

        // 공백 없는 줄 (한 단어가 줄을 차지)
        let spaceless = justifiedString("가나다라마바사아자차카타파하 다음문단")
        let first = try XCTUnwrap(firstLine(of: spaceless, width: 60))
        expect(HwpWordJustification.wordJustifiedLine(
            frameLine: first,
            attributedString: spaceless,
            availableWidth: 60
        )).to(beNil())
    }
}
