import CoreGraphics
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 자간(#260)의 경계 사례 — 줄 끝 공백 판정, 대체 글꼴 캐시 열쇠, 뒤 단위만 글꼴에 없는 묶음,
    /// 묶음 경계(방점·첫가끝 초성). 규칙 본문은 `HwpLetterSpacingTests`다.
    final class HwpLetterSpacingEdgeCaseTests: XCTestCase {
        private static let fontKey = kCTFontAttributeName as NSAttributedString.Key

        private static func menlo(_ size: CGFloat = 20) -> CTFont {
            CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        }

        private static func advance(_ character: UniChar, in font: CTFont) -> CGFloat {
            var character = character
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width
        }

        func testLineEndSpacingSkipsEverySpaceSeparator() {
            // 묶음 빈칸(U+00A0)·전각 빈칸(U+3000)도 CoreText가 줄 끝에서 매다는 공백이다 — 그 글자를 줄의
            // 마지막 글자로 읽으면 빈칸 폭 kern이나 전각 빈칸의 tracking을 자간으로 읽는다.
            let font = Self.menlo()
            let expected = Self.advance(0x62, in: font) * -0.2
            for trailing in ["\u{00A0}", "\u{3000}", "\u{2009}", "\t"] {
                let spaced = HwpTextRunBuilder.letterSpacedString(
                    "ab" + trailing, attributes: [Self.fontKey: font], ratio: -0.2
                )
                let range = NSRange(location: 0, length: spaced.length)
                expect(HwpLetterSpacing.lineEndSpacing(in: spaced, range: range))
                    .to(beCloseTo(expected, within: 1e-9), description: trailing.debugDescription)
            }
            // 공백이 아닌 마지막 글자는 그대로 그 글자다.
            expect(HwpLetterSpacing.isLineEndWhitespace(0x3001)) == false
            expect(HwpLetterSpacing.isLineEndWhitespace(0x200B)) == false
        }

        func testFallbackCacheKeysOnCodeUnitsNotCanonicalEquivalence() {
            // U+2329와 U+3008은 정준 분해가 같아 `String ==`이 같다고 본다 — 글리프가 다를 수 있으므로
            // 두 항목이어야 한다.
            expect("\u{2329}" == "\u{3008}") == true
            let cache = HwpTextAttributeCache()
            var calls = 0
            for unit: UniChar in [0x2329, 0x3008, 0x2329] {
                _ = cache.fallback(for: [unit], in: Self.menlo()) {
                    calls += 1
                    return nil
                }
            }
            expect(calls) == 2
        }

        func testClusterWhoseTrailingUnitsAreMissingUsesTheDrawnFont() throws {
            // Menlo에 `#`은 있지만 U+FE0F·U+20E3은 없다 — CoreText는 키캡 묶음 전체를 이모지 글꼴로
            // 그리므로 자간은 Menlo `#`의 전진량이 아니라 그려지는 묶음 폭의 %다.
            let font = Self.menlo()
            for text in ["#\u{FE0F}\u{20E3}", "\u{263A}\u{FE0F}", "\u{2764}\u{FE0E}"] {
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: text, attributes: [Self.fontKey: font])
                )
                let run = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
                let drawn = CGFloat(CTRunGetTypographicBounds(run, CFRange(), nil, nil, nil))
                let segments = HwpLetterSpacing.segments(
                    of: text as NSString, font: font, ratio: 0.2
                )
                expect(segments.count) == 1
                expect(segments.first?.spacing)
                    .to(beCloseTo(drawn * 0.2, within: 1e-9), description: text.debugDescription)
            }
            // 대조군: 이모지로 그려지는 묶음은 Menlo `#`의 전진량과 다르다.
            let keycap = HwpLetterSpacing.segments(
                of: "#\u{FE0F}\u{20E3}" as NSString, font: font, ratio: 0.2
            )
            expect(abs((keycap.first?.spacing ?? 0) - Self.advance(0x23, in: font) * 0.2)) > 0.5
        }

        func testClusterRangeJoinsToneMarksAndChoseongSequences() {
            func cluster(_ text: String) -> Int {
                let string = text as NSString
                var units = [UniChar](repeating: 0, count: string.length)
                string.getCharacters(&units, range: NSRange(location: 0, length: string.length))
                return HwpLetterSpacing.clusterRange(at: 0, units: units, text: string).length
            }
            // 한글 방점(U+302E)은 앞 음절에 붙는다 — 결합 부호인 U+302A–302F는 빠른 경로 밖이다.
            expect(cluster("가\u{302E}나")) == 2
            // 첫가끝 초성은 뒤 음절과도 한 묶음이다 (L + LV).
            expect(cluster("\u{1100}가나")) == 2
            // 빠른 경로: 한글 음절 뒤 한글 음절은 묶이지 않는다.
            expect(cluster("가나")) == 1
        }
    }
#endif
