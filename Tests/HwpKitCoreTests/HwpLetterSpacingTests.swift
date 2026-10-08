import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 글자 자간 (#260) — 글자마다 그 글자 전진량(장평 적용 뒤)의 %를 싣는다. 음수 자간이고 글리프가 글꼴의
    /// 커닝·치환 집합(`HwpKerningCoverage`)에 들지 않으면 kern, 나머지(양수·커닝 관여 글리프·결합 부호
    /// 묶음)는 kern 0 + tracking이다. 수치의 근거는 `HwpTextRunBuilderLetterSpacing.swift`의 doc-comment
    /// (한글 12.30.0 build 6523 실측)이고, 실물 대조는 `HwpKitTests/FixtureLetterSpacingTests`다.
    final class HwpLetterSpacingTests: XCTestCase {
        private typealias Key = NSAttributedString.Key
        private static let tracking = kCTTrackingAttributeName as Key
        private static let kern = kCTKernAttributeName as Key
        private static let fontKey = kCTFontAttributeName as Key
        private static let gothicName = "AppleSDGothicNeo-Regular"

        private static func font(_ name: String, size: CGFloat = 20) -> CTFont {
            CTFontCreateWithName(name as CFString, size, nil)
        }

        private static func glyphAdvance(_ character: UniChar, in font: CTFont) -> CGFloat {
            var character = character
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width
        }

        private static func number(
            _ key: Key, at index: Int, in string: NSAttributedString
        ) -> Double? {
            (string.attribute(key, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue
        }

        /// `string`의 `[location, location + length)` 줄의 줄 끝 자간.
        private static func lineEnd(
            _ string: NSAttributedString, _ location: Int, _ length: Int
        ) -> CGFloat {
            let range = NSRange(location: location, length: length)
            return HwpLetterSpacing.lineEndSpacing(in: string, range: range)
        }

        /// `text`를 `font`·자간 `ratio`로 실은 조판 문자열.
        private static func spaced(
            _ text: String, _ font: CTFont, _ ratio: CGFloat,
            coverage: ((CTFont) -> HwpKerningCoverage.GlyphSet?)? = nil
        ) -> NSAttributedString {
            HwpTextRunBuilder.letterSpacedString(
                text, attributes: [fontKey: font], ratio: ratio, coverage: coverage
            )
        }

        /// UTF-16 단위마다의 운반 속성.
        private static func carriers(
            _ text: String, font name: String, ratio: CGFloat
        ) -> [HwpLetterSpacing.Carrier] {
            HwpLetterSpacing.segments(of: text as NSString, font: font(name), ratio: ratio)
                .flatMap { Array(repeating: $0.carrier, count: $0.range.length) }
        }

        func testSegmentsAreTheGlyphAdvanceTimesTheRatio() {
            // 라틴 글자는 글자마다 전진량이 달라 값이 갈리고, 같은 값이 이어지면 한 범위다.
            let helvetica = Self.font("Helvetica")
            let segments = HwpLetterSpacing.segments(
                of: "aaW" as NSString, font: helvetica, ratio: 0.2
            )
            expect(segments.map(\.range))
                == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1)]
            expect(segments[0].spacing)
                .to(beCloseTo(Self.glyphAdvance(0x61, in: helvetica) * 0.2, within: 1e-9))
            expect(segments[1].spacing)
                .to(beCloseTo(Self.glyphAdvance(0x57, in: helvetica) * 0.2, within: 1e-9))
        }

        func testSegmentsUseTheScaledAdvance() {
            // 장평은 글꼴 행렬이라 `CTFontGetAdvancesForGlyphs`가 이미 품는다 — 장평 적용 뒤 전진량의 %.
            var matrix = CGAffineTransform(scaleX: 0.5, y: 1)
            let half = CTFontCreateWithName("Menlo-Regular" as CFString, 20, &matrix)
            let segment = HwpLetterSpacing.segments(of: "a" as NSString, font: half, ratio: 0.2)[0]
            let expected = Self.glyphAdvance(0x61, in: Self.font("Menlo-Regular")) * 0.5 * 0.2
            expect(segment.spacing).to(beCloseTo(expected, within: 1e-9))
        }

        func testSurrogatePairsAndCombiningMarksStayInOneSegment() {
            // 대리 쌍·결합 부호를 가르면 CoreText가 글리프를 깨거나 부호를 떼어 놓는다.
            let text = "a\u{1D400}x\u{301}b" as NSString
            let segments = HwpLetterSpacing.segments(
                of: text, font: Self.font("Menlo-Regular"), ratio: 0.2
            )
            let boundaries = Set(segments.map(\.range.location))
            expect(boundaries.contains(2)) == false // 대리 쌍 안
            expect(boundaries.contains(4)) == false // x와 결합 부호 사이
            expect(segments.reduce(0) { $0 + $1.range.length }) == text.length
        }

        func testMissingGlyphsUseTheFallbackFontAdvance() {
            // Menlo에 없는 한글은 CoreText가 고르는 대체 글꼴(`CTFontCreateForString`)의 전진량.
            let menlo = Self.font("Menlo-Regular")
            let text = "가" as NSString
            let range = CFRange(location: 0, length: 1)
            let fallback = CTFontCreateForString(menlo, text as CFString, range)
            let segment = HwpLetterSpacing.segments(of: text, font: menlo, ratio: -0.1)[0]
            expect(segment.spacing)
                .to(beCloseTo(Self.glyphAdvance(0xAC00, in: fallback) * -0.1, within: 1e-9))
            expect(segment.fallbackFont).toNot(beNil())
            // 대체 글꼴(한글 글꼴)의 커닝 집합에 한글 음절이 없으므로 kern이다.
            expect(segment.carrier) == .kern
        }

        func testNegativeSpacingUsesKernOnlyOutsideTheKerningSet() {
            // Apple SD 산돌고딕 Neo는 라틴 일부(`A`·`V` 등)만 짝 커닝한다 — 한글 음절은 kern, 그 라틴은
            // tracking(kern 0). 양수 자간은 줄 끝 규칙 때문에 늘 tracking이다.
            expect(Self.carriers("가나A", font: Self.gothicName, ratio: -0.2))
                == [.kern, .kern, .tracking]
            expect(Self.carriers("가나", font: Self.gothicName, ratio: 0.2)) == [.tracking, .tracking]
            // 결합 부호 묶음은 kern 기능의 문맥 룩업이 부호 자리를 다시 잡는 글꼴이 있어 늘 tracking이다.
            expect(Self.carriers("bx\u{301}", font: Self.gothicName, ratio: -0.2))
                == [.kern, .tracking, .tracking]
            // 커닝 집합을 알 수 없는 글꼴(AAT `morx` — Menlo)은 tracking이다.
            expect(Self.carriers("ab", font: "Menlo-Regular", ratio: -0.2))
                == [.tracking, .tracking]
        }

        func testGlyphAfterAKerningSpaceUsesTracking() {
            // Times New Roman의 빈칸은 짝 커닝의 첫 글리프다 — 빈칸 폭 패스가 빈칸에 kern을 주므로, 뒤
            // 글자가 kern을 지니면 그 사이에 짝 커닝이 걸린다. Apple SD 산돌고딕 Neo의 빈칸은 집합 밖이다.
            expect(Self.carriers("b b", font: "TimesNewRomanPSMT", ratio: -0.2)[2]) == .tracking
            expect(Self.carriers("b b", font: Self.gothicName, ratio: -0.2)[2]) == .kern
            // chunk 첫 글자도 앞 글자(`preceding`)가 같은 글꼴의 커닝 집합 빈칸이면 tracking이다.
            let times = Self.font("TimesNewRomanPSMT")
            let preceding = HwpLetterSpacing.Preceding(
                endOf: NSAttributedString(string: " ", attributes: [Self.fontKey: times])
            )
            let first = HwpLetterSpacing.segments(
                of: "b" as NSString, font: times, ratio: -0.2, preceding: { preceding }
            )
            expect(first[0].carrier) == .tracking
        }

        func testSpacesAndZeroWidthCharactersCarryNoTracking() {
            // tracking이 붙은 글자는 CoreText가 kern을 무시하므로 빈칸에는 tracking을 달지 않는다.
            let spaced = HwpTextRunBuilder.letterSpacedString(
                "a b\u{200B}c",
                attributes: [
                    Self.fontKey: Self.font("Menlo-Regular"), Self.kern: NSNumber(value: 4),
                ],
                ratio: 0.2
            )
            expect(Self.number(Self.tracking, at: 0, in: spaced)).toNot(beNil())
            expect(Self.number(Self.tracking, at: 1, in: spaced)).to(beNil())
            expect(Self.number(Self.tracking, at: 3, in: spaced)).to(beNil())
            // kern은 0 — 0이 아니면 CoreText가 짝 커닝을 다시 켠다.
            expect(Self.number(Self.kern, at: 0, in: spaced)) == 0
            // 자간 표식은 chunk 전체에 자간 비율로 붙는다.
            expect(Self.number(HwpAttributedStringKey.letterSpacing, at: 1, in: spaced))
                .to(beCloseTo(0.2, within: 1e-9))
        }

        func testKernCarriedSpacingIsAPercentOfTheAdvance() {
            // 한글 음절 kern 운반 — kern = 전진량 × 비율, tracking 없음.
            let gothic = Self.font(Self.gothicName)
            let spaced = Self.spaced("가나", gothic, -0.2)
            expect(Self.number(Self.kern, at: 1, in: spaced))
                .to(beCloseTo(Double(Self.glyphAdvance(0xB098, in: gothic) * -0.2), within: 1e-9))
            expect(Self.number(Self.tracking, at: 1, in: spaced)).to(beNil())
        }

        func testKernZeroKeepsPairKerningOff() {
            // Times New Roman `AV`는 짝 커닝(−2.58pt)이 있다 — 커닝 집합 글리프는 tracking + kern 0이라
            // 커닝 없는 전진량 + 자간이다 (kern에 실으면 짝 커닝이 섞인다). 양수·음수 모두.
            let times = Self.font("TimesNewRomanPSMT")
            let nominal = Self.glyphAdvance(0x41, in: times) + Self.glyphAdvance(0x56, in: times)
            for ratio: CGFloat in [0.2, -0.2] {
                let line = CTLineCreateWithAttributedString(Self.spaced("AV", times, ratio))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                expect(width)
                    .to(beCloseTo(nominal * (1 + ratio), within: 0.001), description: "\(ratio)")
            }
        }

        /// 빈칸 폭 패스처럼 빈칸에 kern을 준 조판의 글리프 x 원점들과 줄 폭.
        private static func glyphOrigins(_ spaced: NSAttributedString) -> [CGFloat] {
            let string = NSMutableAttributedString(attributedString: spaced)
            let text = string.string as NSString
            for index in 0 ..< text.length where text.character(at: index) == 0x20 {
                let range = NSRange(location: index, length: 1)
                string.addAttribute(kern, value: NSNumber(value: 3.3), range: range)
            }
            let line = CTLineCreateWithAttributedString(string)
            var origins: [CGFloat] = []
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                var positions = [CGPoint](repeating: .zero, count: CTRunGetGlyphCount(run))
                CTRunGetPositions(run, CFRange(location: 0, length: positions.count), &positions)
                origins += positions.map(\.x)
            }
            return origins + [CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))]
        }

        func testMixedCarriersMatchAllTrackingLayout() {
            // 운반 속성을 섞어도 글자 자리는 전부 tracking으로 실은 것과 같다 — macOS·iOS 공통 글꼴의
            // 커닝 쌍·합자 후보·한글·한자·결합 부호·대리 쌍·빈칸을 섞은 문자열.
            let fonts = [
                "TimesNewRomanPSMT", "Helvetica", Self.gothicName, "Georgia", "Menlo-Regular",
            ]
            let texts = [
                "AVAWaw To. office", "헌법 재판소는 AV ‘가’ fi",
                "Ta 漢字 x\u{301} \u{1D400} 1960.", "We y. \"A\" P, LT",
            ]
            for name in fonts {
                for text in texts {
                    for ratio: CGFloat in [-0.05, -0.2, -0.5] {
                        let font = Self.font(name)
                        let mixed = Self.glyphOrigins(Self.spaced(text, font, ratio))
                        let tracked = Self.glyphOrigins(Self.spaced(text, font, ratio) { _ in nil })
                        expect(mixed.count) == tracked.count
                        let label = "\(name) \(ratio) \(text)"
                        for (mixedX, trackedX) in zip(mixed, tracked) {
                            expect(mixedX).to(beCloseTo(trackedX, within: 1e-6), description: label)
                        }
                    }
                }
            }
        }

        func testLineEndSpacingReadsEitherCarrierAndSkipsTrailingWhitespace() {
            let menlo = Self.font("Menlo-Regular")
            let tracked = Self.spaced("ab  ", menlo, -0.2)
            expect(Self.number(Self.tracking, at: 1, in: tracked)).toNot(beNil())
            expect(Self.lineEnd(tracked, 0, 4))
                .to(beCloseTo(Self.glyphAdvance(0x62, in: menlo) * -0.2, within: 1e-9))
            expect(Self.lineEnd(tracked, 2, 2)) == 0
            let gothic = Self.font(Self.gothicName)
            let kerned = Self.spaced("가나 ", gothic, -0.2)
            expect(Self.number(Self.tracking, at: 1, in: kerned)).to(beNil())
            expect(Self.lineEnd(kerned, 0, 3))
                .to(beCloseTo(Self.glyphAdvance(0xB098, in: gothic) * -0.2, within: 1e-9))
            // 자간 표식이 없는 글자의 kern(빈칸 폭·컨트롤 치환)은 자간이 아니다.
            let plain = NSAttributedString(
                string: "ab", attributes: [Self.fontKey: gothic, Self.kern: NSNumber(value: -2)]
            )
            expect(Self.lineEnd(plain, 0, 2)) == 0
        }

        func testRemovingTheLastCharacterSpacingClearsBothCarriers() {
            let gothic = Self.font(Self.gothicName)
            let kerned = NSMutableAttributedString(
                attributedString: Self.spaced("가나", gothic, -0.2)
            )
            HwpLetterSpacing.removeLastCharacterSpacing(in: kerned)
            expect(Self.number(Self.kern, at: 0, in: kerned)).toNot(equal(0))
            expect(Self.number(Self.kern, at: 1, in: kerned)) == 0
            expect(Self.lineEnd(kerned, 0, 2)) == 0
            let tracked = NSMutableAttributedString(
                attributedString: Self.spaced("가나", gothic, 0.2)
            )
            HwpLetterSpacing.removeLastCharacterSpacing(in: tracked)
            expect(Self.number(Self.tracking, at: 0, in: tracked)).toNot(beNil())
            expect(Self.number(Self.tracking, at: 1, in: tracked)).to(beNil())
        }

        func testDocumentCacheResolvesFallbacksAndCoverageOnce() {
            let cache = HwpTextAttributeCache()
            var calls = 0
            for _ in 0 ..< 3 {
                _ = cache.fallback(for: [0xAC00], in: Self.font("Menlo-Regular")) {
                    calls += 1
                    return nil
                }
            }
            // 같은 값의 다른 인스턴스도 한 항목이다 (열쇠는 글꼴 값).
            expect(calls) == 1
            let gothic = Self.font(Self.gothicName)
            expect(cache.kerningCoverage(of: gothic)) == HwpKerningCoverage.glyphs(of: gothic)
            expect(cache.coverageMissCount) == 1
            // 커닝 집합은 chunk마다가 아니라 글꼴마다 한 번 푼다 — 집합이 nil(전체 글리프)인 Menlo도
            // 문서 캐시가 그 nil을 담아, 전역 캐시(`HwpKerningCoverage.glyphs`)를 다시 타지 않는다.
            let menlo = Self.font("Menlo-Regular")
            let lookups = HwpKerningCoverage.lookupCount
            for _ in 0 ..< 3 {
                _ = HwpTextRunBuilder.letterSpacedString(
                    "ab", attributes: [Self.fontKey: menlo], ratio: -0.2, cache: cache
                )
            }
            expect(cache.coverageMissCount) == 2
            expect(HwpKerningCoverage.lookupCount - lookups) == 1
        }
    }

    /// 조판 경로 — 결정론 resolver라 모든 슬롯이 Menlo(한글은 대체 글꼴)다. 글자 모양 헬퍼는 12pt.
    extension HwpTextRunBuilderTests {
        private static let trackingKey = kCTTrackingAttributeName as NSAttributedString.Key
        private static let kernKey = kCTKernAttributeName as NSAttributedString.Key

        private static func value(_ key: NSAttributedString.Key, _ index: Int,
                                  _ string: NSAttributedString) -> Double?
        {
            (string.attribute(key, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue
        }

        private var menloEm: CGFloat {
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 100, nil)
            var character: UniChar = 0x61
            var glyph = CGGlyph()
            _ = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width / 100
        }

        func testBuildPutsTheSpacingOnTrackingAsAPercentOfTheAdvance() throws {
            // 라틴 자간 +20%: 글자 kern 0, tracking = Menlo 0.6em × 12pt × 0.2. 자간 0이면 kern 0만.
            let spaced = HwpTextRunBuilder(
                index: index(shapes: [0: try charShape(faceSpacing: [0, 20, 0, 0, 0, 0, 0])]),
                fontResolver: .testDeterministic
            ).build(paragraph: paragraph(text: "ab", runs: [(0, 0)]))
            expect(Self.value(Self.kernKey, 0, spaced)) == 0
            expect(Self.value(Self.trackingKey, 0, spaced))
                .to(beCloseTo(Double(menloEm * 12 * 0.2), within: 1e-6))
            let plain = HwpTextRunBuilder(
                index: index(shapes: [0: try charShape()]), fontResolver: .testDeterministic
            ).build(paragraph: paragraph(text: "ab", runs: [(0, 0)]))
            expect(Self.value(Self.kernKey, 0, plain)) == 0
            expect(Self.value(Self.trackingKey, 0, plain)).to(beNil())
        }

        func testBuildScalesTheSpacingWithTheScaleX() throws {
            // 장평 50%·자간 +20%: 장평 적용 뒤 전진량(0.5 × 0.6em × 12pt)의 20%.
            let spaced = HwpTextRunBuilder(
                index: index(shapes: [0: try charShape(
                    faceScaleX: [100, 50, 100, 100, 100, 100, 100],
                    faceSpacing: [0, 20, 0, 0, 0, 0, 0]
                )]),
                fontResolver: .testDeterministic
            ).build(paragraph: paragraph(text: "ab", runs: [(0, 0)]))
            expect(Self.value(Self.trackingKey, 0, spaced))
                .to(beCloseTo(Double(menloEm * 12 * 0.5 * 0.2), within: 1e-6))
        }

        func testNoteNumbersCarryNoSpacing() throws {
            // 각주 참조 번호는 자간을 받지 않는다 (한글 실측) — kern 0, tracking 없음.
            var paragraph = paragraph(text: "ab", runs: [(0, 0)])
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [
                CoreHwp.HwpChar(type: .char, value: 0x61),
                CoreHwp.HwpChar(type: .extended, value: 17),
                CoreHwp.HwpChar(type: .char, value: 0x62),
            ]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [])),
            ]
            expect(HwpTextRunBuilder.isNoteNumber(controlIndex: 0, in: paragraph)) == true
            let built = HwpTextRunBuilder(
                index: index(shapes: [0: try charShape(faceSpacing: [20, 20, 20, 20, 20, 20, 20])]),
                fontResolver: .testDeterministic
            ).build(
                paragraph: paragraph,
                controlReplacements: [
                    0: HwpControlMarkerReplacement(text: "12)", isSuperscript: true),
                ]
            )
            expect(built.string) == "a12)b"
            for index in 1 ... 3 {
                expect(Self.value(Self.kernKey, index, built)) == 0
                expect(Self.value(Self.trackingKey, index, built)).to(beNil())
            }
            expect(Self.value(Self.trackingKey, 0, built)).toNot(beNil())
        }

        func testAutoNumbersWithoutTheirInfoAreNoteNumbers() {
            // 표 142를 못 읽은 자동 번호는 각주·미주 번호로 치환된다(`autoNumberReplacements`) — 자간도 없다.
            var paragraph = paragraph(text: "a", runs: [(0, 0)])
            paragraph.ctrlHeaderArray = [
                .autoNumber(CoreHwp.HwpOtherControl(
                    ctrlId: .autoNumber, rawTrailing: Data(), rawPayload: Data(),
                    ctrlDataRecords: [], unknownChildren: []
                )),
                HwpSynthetic.autoNumberControl(kind: 0, number: 1),
            ]
            expect(HwpTextRunBuilder.isNoteNumber(controlIndex: 0, in: paragraph)) == true
            // 쪽 번호(종류 0)는 각주 번호가 아니다.
            expect(HwpTextRunBuilder.isNoteNumber(controlIndex: 1, in: paragraph)) == false
        }

        func testNumberingLabelLastCharacterIsUnspaced() throws {
            // 라벨 `10.`의 숫자는 자간을 받고 마지막 `.`은 받지 않는다 (한글 실측).
            let shape = try charShape(faceSpacing: [20, 20, 20, 20, 20, 20, 20])
            let index = HwpIndex(
                charShapes: [0: shape],
                paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:],
                numberings: [0: HwpNumberingHeadingRenderTests.definition()], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic).build(
                paragraph: try HwpNumberingHeadingRenderTests.paragraph("가", runs: [(0, 0)]),
                number: HwpParagraphNumber(
                    kind: .outline, definitionIndex: 0, numbers: [10], text: "10."
                )
            )
            expect(built.string.hasPrefix("10.")) == true
            expect(Self.value(Self.trackingKey, 0, built)).toNot(beNil())
            expect(Self.value(Self.trackingKey, 1, built)).toNot(beNil())
            expect(Self.value(Self.trackingKey, 2, built)).to(beNil())
        }

        func testNumberingLabelLastCharacterIsUnspacedWithNegativeSpacing() throws {
            // 음수 자간 라벨 — 운반 속성이 kern이어도 마지막 글자는 kern 0이다. 결정론 resolver의 라틴
            // 글꼴 Menlo는 `morx`라 모든 글리프가 tracking이므로, 마지막 글자를 한글(대체 글꼴 Apple SD
            // 산돌고딕 Neo — 음절이 커닝 집합 밖이라 kern)로 둬야 kern 운반 속성의 제거를 잰다.
            let shape = try charShape(faceSpacing: [-20, -20, -20, -20, -20, -20, -20])
            let index = HwpIndex(
                charShapes: [0: shape],
                paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:],
                numberings: [0: HwpNumberingHeadingRenderTests.definition()], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic).build(
                paragraph: try HwpNumberingHeadingRenderTests.paragraph("가", runs: [(0, 0)]),
                number: HwpParagraphNumber(
                    kind: .outline, definitionIndex: 0, numbers: [10], text: "제10장"
                )
            )
            expect(built.string.hasPrefix("제10장")) == true
            // 첫 글자 `제`는 kern으로 자간을 받는다 — 같은 운반 속성의 마지막 글자 `장`만 0이다.
            expect(Self.value(Self.kernKey, 0, built)) < 0
            expect(Self.value(Self.trackingKey, 0, built)).to(beNil())
            let label = NSRange(location: 0, length: 4)
            expect(HwpLetterSpacing.lineEndSpacing(in: built, range: label)) == 0
            expect(Self.value(Self.trackingKey, 3, built)).to(beNil())
            expect(Self.value(Self.kernKey, 3, built)) == 0
        }

        func testBulletHeadingCarriesNoSpacing() throws {
            // 글머리표 기호는 자간을 받지 않는다 (한글 실측) — 종전의 글자 크기 × 자간 kern도 없다.
            let bullet = CoreHwp.HwpBullet(
                hwpxInfo: [UInt8](repeating: 0, count: 8), headCharShapeId: -1,
                char: "□", checkChar: ""
            )
            let index = HwpIndex(
                charShapes: [0: try charShape(faceSpacing: [-20, -20, -20, -20, -20, -20, -20])],
                paraShapes: [1: CoreHwp.HwpParaShape(
                    property1: 3 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 1
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [0: bullet],
                numberings: [:], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic).build(
                paragraph: try HwpNumberingHeadingRenderTests.paragraph("가", runs: [(0, 0)]),
                number: nil
            )
            expect(built.string.hasPrefix("□")) == true
            expect(Self.value(Self.kernKey, 0, built)) == 0
            expect(Self.value(Self.trackingKey, 0, built)).to(beNil())
        }
    }
#endif
