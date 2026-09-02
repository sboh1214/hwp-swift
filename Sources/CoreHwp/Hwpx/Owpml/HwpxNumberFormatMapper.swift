import Foundation

/// OWPML `NumberType1`(번호 모양 이름) → HWP 5.0 표 134 번호 모양 코드.
///
/// 쪽 번호 위치(`hp:pageNum formatType`)·각주/미주 번호 모양
/// (`hp:autoNumFormat type`)·번호 문단 머리(`hh:paraHead numFormat`)가 같은
/// 열거를 쓴다. 코드는 `HwpNumberFormat`(HwpKitCore)이 소비하는 표 134 값이며,
/// 이름 순서가 표 134 코드 순서와 같다. 실측: `DIGIT`↔0(noori 쌍),
/// `CIRCLED_DIGIT`↔1·`ROMAN_CAPITAL`↔2·`HANGUL_SYLLABLE`↔8·
/// `DECAGON_CIRCLE_HANJA`↔16(2026-09-02 한글.app 12.30.0 .hwp/.hwpx 쌍) —
/// 나머지는 같은 규칙(KS X 6101 스키마 나열 순서)으로 채웠다
/// (`Sources/CoreHwp/Hwpx/AGENTS.md` "실파일 검증 대기 항목").
enum HwpxNumberFormatMapper {
    static let codes: [String: Int] = [
        "DIGIT": 0, // 1, 2, 3
        "CIRCLED_DIGIT": 1, // ①, ②, ③
        "ROMAN_CAPITAL": 2, // I, II, III
        "ROMAN_SMALL": 3, // i, ii, iii
        "LATIN_CAPITAL": 4, // A, B, C
        "LATIN_SMALL": 5, // a, b, c
        "CIRCLED_LATIN_CAPITAL": 6, // Ⓐ, Ⓑ, Ⓒ
        "CIRCLED_LATIN_SMALL": 7, // ⓐ, ⓑ, ⓒ
        "HANGUL_SYLLABLE": 8, // 가, 나, 다
        "CIRCLED_HANGUL_SYLLABLE": 9, // ㉮, ㉯, ㉰
        "HANGUL_JAMO": 10, // ㄱ, ㄴ, ㄷ
        "CIRCLED_HANGUL_JAMO": 11, // ㉠, ㉡, ㉢
        "HANGUL_PHONETIC": 12, // 일, 이, 삼
        "IDEOGRAPH": 13, // 一, 二, 三
        "CIRCLED_IDEOGRAPH": 14, // ㊀, ㊁, ㊂
        "DECAGON_CIRCLE": 15, // 갑, 을, 병
        "DECAGON_CIRCLE_HANJA": 16, // 甲, 乙, 丙
        "SYMBOL": 0x80, // 4가지 문자 반복
        "USER_CHAR": 0x81, // 사용자 지정 문자
    ]

    /// 누락·미지 이름은 0(숫자)으로 폴백한다 — 뷰어(`HwpNumberFormat`)도 범위
    /// 밖 코드를 아라비아 숫자로 그리므로 두 폴백이 같은 결과를 낸다.
    static func code(for name: String?) -> Int {
        codes[name ?? "DIGIT"] ?? 0
    }
}
