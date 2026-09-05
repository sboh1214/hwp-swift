@testable import CoreHwp
import Nimble
import XCTest

/// 번호 형식 문자열 분해 (#152) — 실문서 형식(헌법주석 7수준·빈 문서 기본값·
/// 한글.app으로 만든 `outline-numbering`의 9·10수준)과 합성 입력을 함께 쓴다.
/// 문자 그대로의 `^n`·`^N`과 지시자가 아닌 캐럿의 처리 결과를 고정한다.
final class NumberingFormatPatternTests: XCTestCase {
    private typealias Token = HwpNumberingFormatPattern.Token

    // MARK: - 실문서

    /// 헌법주석 개요 번호 정의 — 수준 N의 형식이 수준 N 하나만 참조하고 마침표·
    /// 괄호는 문자 조각이다.
    func testLegacyOutlineFormatsSplitIntoLevelReferencesAndLiterals() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let numbering = try XCTUnwrap(hwp.docInfo.idMappings.numberingArray.first)

        expect(numbering.formatArray.map(\.format)) == [
            "^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)",
        ]
        let patterns = (1 ... 7).map { level in
            try? XCTUnwrap(numbering.format(forLevel: level)).pattern
        }
        expect(patterns.map { $0?.tokens }) == [
            [.level(1), .literal(".")],
            [.level(2), .literal(".")],
            [.level(3), .literal(".")],
            [.literal("("), .level(4), .literal(")")],
            [.literal("("), .level(5), .literal(")")],
            [.level(6), .literal(")")],
            [.level(7), .literal(")")],
        ]
        expect(patterns.map { $0?.referencedLevels }) == (1 ... 7).map { [$0] }
        expect(patterns.allSatisfy { $0?.isSupported == true }) == true
        // 5.0.2.2 저장본은 확장 수준 배열이 없어 8-10수준 형식이 없다.
        expect((8 ... 10).map { numbering.format(forLevel: $0) }.allSatisfy { $0 == nil })
            == true
        expect(numbering.format(forLevel: 0)).to(beNil())
        expect(numbering.format(forLevel: 11)).to(beNil())
    }

    /// 한글.app이 저장한 `outline-numbering` 쌍의 사용자 정의 — 9수준 `^n)`은 레벨
    /// 경로, 10수준 `^9.^10)`은 캐럿이 한 자리만 먹어 `^1` + `0`이다 (미리보기 실측
    /// `ㄱ.I0)`). 두 포맷의 형식 문자열이 같다.
    func testOutlineNumberingFixturePinsLevelPathAndSingleDigitDirectives() throws {
        for hwp in [
            try openHwp(#file, "outline-numbering"), try openHwpx(#file, "outline-numbering"),
        ] {
            let custom = try XCTUnwrap(hwp.docInfo.idMappings.numberingArray.last)
            let ninth = try XCTUnwrap(custom.format(forLevel: 9))
            expect(ninth.format) == "^n)"
            expect(ninth.pattern.tokens) == [.levelPath(trailingPeriod: false), .literal(")")]
            expect(ninth.pattern.isSupported) == false

            let tenth = try XCTUnwrap(custom.format(forLevel: 10))
            expect(tenth.format) == "^9.^10)"
            expect(tenth.pattern.tokens) == [
                .level(9), .literal("."), .level(1), .literal("0)"),
            ]
            expect(tenth.pattern.referencedLevels) == [9, 1]
            expect(tenth.pattern.isSupported) == true
        }
    }

    /// 한글 2020 빈 문서(`blank-win2020`)의 기본 정의 — 확장 수준 8은 `^8`,
    /// 9·10은 빈 형식(토큰 없음·지원). `HwpIdMappings()`의 템플릿은 8-10이 전부
    /// 빈 형식이라 `^8`은 실저장본으로 본다.
    func testBlankDocumentDefaultsCoverExtendedLevels() throws {
        let hwp = try openHwp(#file, "blank-win2020")
        let numbering = try XCTUnwrap(hwp.docInfo.idMappings.numberingArray.first)

        expect(numbering.formatArray.map(\.format)) == [
            "^1.", "^2.", "^3)", "^4)", "(^5)", "(^6)", "^7",
        ]
        expect(try XCTUnwrap(numbering.format(forLevel: 7)).pattern.tokens) == [.level(7)]
        expect(try XCTUnwrap(numbering.format(forLevel: 8)).pattern.tokens) == [.level(8)]
        let tenth = try XCTUnwrap(numbering.format(forLevel: 10)).pattern
        expect(tenth.tokens).to(beEmpty())
        expect(tenth.isSupported) == true
        expect(tenth.referencedLevels).to(beEmpty())

        let template = try XCTUnwrap(HwpIdMappings().numberingArray.first)
        expect(template.extendedFormatArray?.map(\.format)) == ["", "", ""]
        expect(try XCTUnwrap(template.format(forLevel: 8)).pattern.tokens).to(beEmpty())
    }

    // MARK: - 합성

    /// 상위 수준을 함께 적는 형식 — 숫자는 문단의 수준이 아니라 참조할 수준이다.
    func testMultiLevelFormatReferencesEachLevelInOrder() {
        let pattern = HwpNumberingFormatPattern.parse("^1.^2.^3")
        expect(pattern.tokens) == [
            .level(1), .literal("."), .level(2), .literal("."), .level(3),
        ]
        expect(pattern.referencedLevels) == [1, 2, 3]
        expect(pattern.isSupported) == true

        let wrapped = HwpNumberingFormatPattern.parse("제^1장 ^1.^1")
        expect(wrapped.tokens) == [
            .literal("제"), .level(1), .literal("장 "), .level(1), .literal("."), .level(1),
        ]
        expect(wrapped.referencedLevels) == [1, 1, 1]
    }

    /// `^n`·`^N`은 레벨 경로 토큰이다 — 숫자 참조와 구분하고 아직 지원하지 않는다.
    func testLevelPathDirectivesAreDistinctAndUnsupported() {
        let path = HwpNumberingFormatPattern.parse("^n.")
        expect(path.tokens) == [.levelPath(trailingPeriod: false), .literal(".")]
        expect(path.isSupported) == false
        expect(path.referencedLevels).to(beEmpty())

        let dotted = HwpNumberingFormatPattern.parse("(^N)")
        expect(dotted.tokens) == [.literal("("), .levelPath(trailingPeriod: true), .literal(")")]
        expect(dotted.isSupported) == false
    }

    /// 캐럿은 숫자 한 자리만 먹는다 — 한글.app 실측(2026-09-05, 12.30): 10수준 정의의
    /// `^9.^10)`이 `ㄱ.I0)`로 그려진다(`^1` = 로마 대문자 I + 문자 `0`). 그래서 두
    /// 자리 숫자는 첫 자리 참조 + 나머지 문자이고, `^0`은 지시자가 아니라 문자다.
    func testCaretConsumesOneDigitOnly() {
        expect(HwpNumberingFormatPattern.parse("^9.^10)").tokens) == [
            .level(9), .literal("."), .level(1), .literal("0)"),
        ]
        expect(HwpNumberingFormatPattern.parse("^11").tokens) == [.level(1), .literal("1")]
        expect(HwpNumberingFormatPattern.parse("^100").tokens) == [.level(1), .literal("00")]
        expect(HwpNumberingFormatPattern.parse("^9").tokens) == [.level(9)]
        expect(HwpNumberingFormatPattern.parse("^0)").tokens) == [.literal("^0)")]
        expect(HwpNumberingFormatPattern.parse("^01").tokens) == [.literal("^01")]
        expect(HwpNumberingFormatPattern.referenceLevelRange) == 1 ... 9
    }

    /// 지시자가 아닌 캐럿은 다음 글자와 함께 문자 그대로다 — 한글.app 실측
    /// (2026-09-05, 10수준 미리보기): `^0)`→`^0)`, `^x^^)`→`^x^^)`, `^^1)`→`^^1)`,
    /// `^^^1)`→`^^I)`, `^a^1)`→`^aI)`. 둘째 캐럿이 첫 캐럿과 짝지어 소비되므로
    /// `^^1`은 1수준 참조가 아니고, 홀수 번째 캐럿만 지시자가 될 수 있다.
    /// 별도 미지원 토큰을 두지 않고 문자 조각에 합친다.
    func testNonDirectiveCaretsAreLiteralText() {
        expect(HwpNumberingFormatPattern.parse("^x").tokens) == [.literal("^x")]
        expect(HwpNumberingFormatPattern.parse("제^").tokens) == [.literal("제^")]
        expect(HwpNumberingFormatPattern.parse("^x^^)").tokens) == [.literal("^x^^)")]
        expect(HwpNumberingFormatPattern.parse("^^1)").tokens) == [.literal("^^1)")]
        expect(HwpNumberingFormatPattern.parse("^^^1)").tokens) == [
            .literal("^^"), .level(1), .literal(")"),
        ]
        expect(HwpNumberingFormatPattern.parse("^a^1)").tokens) == [
            .literal("^a"), .level(1), .literal(")"),
        ]
        // 전각 숫자는 ASCII 숫자가 아니다.
        expect(HwpNumberingFormatPattern.parse("^１").tokens) == [.literal("^１")]
        // `^^n)`은 한글이 특이하게 그리지만(`^^` 뒤에 경로) 실문서에 없는 형식이라
        // 모델링하지 않는다 — 짝 규칙대로 문자 그대로다.
        expect(HwpNumberingFormatPattern.parse("^^n)").tokens) == [.literal("^^n)")]

        let mixed = HwpNumberingFormatPattern.parse("^1.^x")
        expect(mixed.tokens) == [.level(1), .literal(".^x")]
        expect(mixed.isSupported) == true
        expect(mixed.referencedLevels) == [1]
    }

    /// 인접한 문자는 하나의 조각으로 합치고 빈 형식은 빈 토큰이다.
    func testLiteralsMergeAndEmptyFormatHasNoTokens() {
        expect(HwpNumberingFormatPattern.parse("가나다").tokens) == [.literal("가나다")]
        let empty = HwpNumberingFormatPattern.parse("")
        expect(empty.tokens).to(beEmpty())
        expect(empty.isSupported) == true
        // 형식 문자열은 결합 문자·서러게이트 쌍을 그대로 돌려준다.
        let surrogates = HwpNumberingFormatPattern.parse("😀^1\u{0301}")
        expect(surrogates.tokens) == [.literal("😀"), .level(1), .literal("\u{0301}")]
    }

    /// `HwpNumberingFormat.pattern`은 `format`의 분해다.
    func testFormatPatternAccessorParsesTheFormatText() {
        let format = HwpNumberingFormat(property: [], formatLength: 4, format: "(^4)")
        expect(format.pattern.tokens) == [.literal("("), .level(4), .literal(")")]
    }
}
