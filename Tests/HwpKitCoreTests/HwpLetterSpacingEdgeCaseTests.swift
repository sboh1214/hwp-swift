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

        /// 폭 0 컨트롤 표식(필드 끝·책갈피) — `HwpTextRunBuilder.appendControlMarker`와 같은 속성.
        private static func controlMarker(_ font: CTFont) -> NSAttributedString {
            var attributes: [NSAttributedString.Key: Any] = [
                fontKey: font, HwpAttributedStringKey.controlIndex: NSNumber(value: 0),
            ]
            if let delegate = HwpInlineObjectReservation.runDelegate(width: 0, height: 0) {
                attributes[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
            }
            return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
        }

        func testLineEndSkipsZeroWidthControlMarkers() {
            // 한글은 줄 끝 자간 규칙에서 필드 끝·책갈피를 없는 것으로 본다 (#260 리뷰 실측) — 그 앞 글자가
            // 마지막 글자다. 양수 자간은 표식에 막혀 CoreText가 매달지 못하므로 CoreText 몫(excess)이 된다.
            let font = Self.menlo()
            let expected = Self.advance(0x64, in: font) * 0.2
            for ratio: CGFloat in [-0.2, 0.2] {
                let string = NSMutableAttributedString(
                    attributedString: HwpTextRunBuilder.letterSpacedString(
                        "abcd", attributes: [Self.fontKey: font], ratio: ratio
                    )
                )
                string.append(Self.controlMarker(font))
                string.append(NSAttributedString(string: " ", attributes: [Self.fontKey: font]))
                let range = NSRange(location: 0, length: string.length)
                let end = HwpLetterSpacing.lineEnd(in: string, range: range)
                expect(end.spacing).to(beCloseTo(expected * (ratio < 0 ? -1 : 1), within: 1e-9))
                expect(end.followedByControl) == true
                expect(HwpLetterSpacing.lineEndExcess(in: string, range: range)) == end.spacing
            }
            // 표식이 없으면 양수 자간은 CoreText가 매다는 몫이라 excess가 0이다.
            let plain = HwpTextRunBuilder.letterSpacedString(
                "abcd ", attributes: [Self.fontKey: font], ratio: 0.2
            )
            let range = NSRange(location: 0, length: plain.length)
            expect(HwpLetterSpacing.lineEndExcess(in: plain, range: range)) == 0
            expect(HwpLetterSpacing.lineEndSpacing(in: plain, range: range))
                .to(beCloseTo(expected, within: 1e-9))
        }

        func testRightAlignedLineIgnoresATrailingControlMarker() throws {
            // 링크 끝·책갈피가 줄 끝에 있어도 마지막 글자는 자간 없는 전진량으로 오른쪽 끝에 맞는다 (한글:
            // 표식 유무와 같은 498.24pt).
            let font = Self.menlo()
            var alignment = CTTextAlignment.right
            let style = withUnsafePointer(to: &alignment) { pointer in
                CTParagraphStyleCreate([CTParagraphStyleSetting(
                    spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer
                )], 1)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                Self.fontKey: font, kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
            ]
            for ratio: CGFloat in [-0.2, 0.2] {
                let string = NSMutableAttributedString(
                    attributedString: HwpTextRunBuilder.letterSpacedString(
                        "abcd", attributes: attributes, ratio: ratio
                    )
                )
                let marker = NSMutableAttributedString(attributedString: Self.controlMarker(font))
                marker.addAttribute(
                    kCTParagraphStyleAttributeName as NSAttributedString.Key, value: style,
                    range: NSRange(location: 0, length: 1)
                )
                string.append(marker)
                let lines = HwpDrawnTextLayout.lines(
                    attributedString: string, origin: .zero, lineWidth: 200
                )
                let line = try XCTUnwrap(lines.first)
                let run = try XCTUnwrap((CTLineGetGlyphRuns(line.line) as? [CTRun])?.first {
                    let range = CTRunGetStringRange($0)
                    return (range.location ..< range.location + range.length).contains(3)
                })
                let index = 3 - CTRunGetStringRange(run).location
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: index, length: 1), &position)
                let dEnd = line.baselineOrigin.x + position.x + Self.advance(0x64, in: font)
                expect(dEnd).to(beCloseTo(200, within: 0.01), description: "\(ratio)")
            }
        }

        func testLongStringsTakeNoLineEndCompensation() {
            // CoreText는 10,240 UTF-16 단위를 넘는 문자열의 kern·tracking을 통째로 무시하므로, 그런
            // 문자열에는 적용되지 않은 자간을 빼는 줄 끝 보정을 하지 않는다.
            let font = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 10, nil)
            let limit = HwpLetterSpacing.coreTextSpacingLengthLimit
            for (length, applies) in [(limit, true), (limit + 1, false)] {
                let string = HwpTextRunBuilder.letterSpacedString(
                    String(repeating: "가", count: length), attributes: [Self.fontKey: font],
                    ratio: -0.1
                )
                let range = NSRange(location: 0, length: 40)
                expect(HwpLetterSpacing.lineEndSpacing(in: string, range: range)) < 0
                expect(HwpLetterSpacing.lineEndExcess(in: string, range: range) < 0) == applies
                // CoreText 자체가 그 경계에서 자간을 버린다 — 경계가 바뀌면 이 단언이 먼저 알린다.
                let typesetter = CTTypesetterCreateWithAttributedString(string)
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: 40))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                let unspaced = Self.advance(0xAC00, in: font) * 40
                expect(width < unspaced - 1) == applies
            }
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

        func testSubstitutedGlyphsKeepMixedCarriersEqualToTracking() throws {
            // 커닝 집합은 치환 뒤 글리프를 가리키는데 운반 속성은 치환 전 글리프로 고른다 — NotoNastaliqUrdu의
            // `ل`은 어두 형태로 바뀐 뒤에야 필기체 연결 커버리지에 들어, 치환 입력을 집합에 넣기 전에는 kern으로
            // 실려 글리프 자리가 tracking만 쓴 조판과 11.88pt 갈렸다 (#260 리뷰). macOS·iOS 시스템 글꼴이다.
            let name = "NotoNastaliqUrdu-Bold"
            let font = CTFontCreateWithName(name as CFString, 20, nil)
            try XCTSkipUnless(CTFontCopyPostScriptName(font) as String == name, "\(name) 없음")
            func positions(_ string: NSAttributedString) -> [CGPoint] {
                let line = CTLineCreateWithAttributedString(string)
                var result: [CGPoint] = []
                for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                    var points = [CGPoint](repeating: .zero, count: CTRunGetGlyphCount(run))
                    CTRunGetPositions(run, CFRange(location: 0, length: points.count), &points)
                    result += points
                }
                return result
            }
            let texts = [
                "\u{0644}\u{0645}\u{0652}",
                "\u{0628}\u{0633}\u{0645} \u{0627}\u{0644}\u{0644}\u{0647}",
            ]
            for text in texts {
                let mixed = positions(HwpTextRunBuilder.letterSpacedString(
                    text, attributes: [Self.fontKey: font], ratio: -0.2
                ))
                let tracked = positions(HwpTextRunBuilder.letterSpacedString(
                    text, attributes: [Self.fontKey: font], ratio: -0.2, coverage: { _ in nil }
                ))
                expect(mixed.count) == tracked.count
                for (mixedPoint, trackedPoint) in zip(mixed, tracked) {
                    expect(mixedPoint.x)
                        .to(beCloseTo(trackedPoint.x, within: 1e-6), description: text)
                    expect(mixedPoint.y)
                        .to(beCloseTo(trackedPoint.y, within: 1e-6), description: text)
                }
            }
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
