@testable import CoreHwp
import Nimble
import XCTest

/// 번호 형식 문자열 분해 (#152) — 실문서 형식(헌법주석 7수준·빈 문서 기본값)과
/// 합성 입력을 함께 쓴다. 문자 그대로의 `^n`·`^N`과 지원 범위 밖 지시자의
/// 처리 결과를 고정한다.
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

    /// 두 자리 숫자 중 수준 범위 안은 10뿐이다 — 그 밖의 숫자열은 원문째
    /// 미지원으로 남기고 임의의 수준으로 읽지 않는다.
    func testTenIsTheOnlyTwoDigitLevelReference() {
        expect(HwpNumberingFormatPattern.parse("^10)").tokens) == [.level(10), .literal(")")]
        expect(HwpNumberingFormatPattern.parse("^9").tokens) == [.level(9)]

        for format in ["^0", "^11", "^01", "^100", "^010"] {
            let pattern = HwpNumberingFormatPattern.parse(format)
            expect(pattern.tokens).to(equal([.unsupported(format)]), description: format)
            expect(pattern.isSupported).to(beFalse(), description: format)
            expect(pattern.referencedLevels).to(beEmpty(), description: format)
        }
    }

    /// 캐럿 뒤에 숫자·n·N이 아닌 문자가 오거나 캐럿으로 끝나면 그 지시자만
    /// 미지원이고 나머지 문자는 그대로 조각이다.
    func testUnknownDirectivesKeepTheirSourceText() {
        expect(HwpNumberingFormatPattern.parse("^x").tokens) == [.unsupported("^x")]
        expect(HwpNumberingFormatPattern.parse("제^").tokens) == [.literal("제"), .unsupported("^")]
        expect(HwpNumberingFormatPattern.parse("^^1").tokens) == [.unsupported("^^"), .literal("1")]
        // 전각 숫자는 ASCII 숫자가 아니다.
        expect(HwpNumberingFormatPattern.parse("^１").tokens) == [.unsupported("^１")]

        let mixed = HwpNumberingFormatPattern.parse("^1.^x")
        expect(mixed.tokens) == [.level(1), .literal("."), .unsupported("^x")]
        expect(mixed.isSupported) == false
        // 지원하는 참조는 미지원 지시자와 무관하게 셈한다 — 진단이 수준을 적을 수 있게.
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
