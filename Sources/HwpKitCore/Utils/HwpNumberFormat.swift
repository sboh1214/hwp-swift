import Foundation

/// 표 134 번호 모양 코드 → 번호 문자열 변환.
///
/// 각주/미주 번호 (표 133/134), 자동 번호 (표 143 bit 4-11),
/// 쪽 번호 위치 (표 148 bit 0-7)가 같은 코드를 공유한다.
/// 0x80(4가지 문자 반복)/0x81(사용자 지정 문자)과 범위를 벗어난 코드는
/// 아라비아 숫자로 폴백한다.
public enum HwpNumberFormat {
    /// 순환 문자 집합 (개수를 넘으면 처음부터 반복 — 한글의 동작)
    private static let hangulSyllables = [
        "가", "나", "다", "라", "마", "바", "사", "아", "자", "차", "카", "타", "파", "하",
    ]
    private static let hangulJamo = [
        "ㄱ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]
    private static let hangulNumbers = ["일", "이", "삼", "사", "오", "육", "칠", "팔", "구", "십"]
    private static let hanjaNumbers = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    private static let hanjaGapja = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let hangulGapja = ["갑", "을", "병", "정", "무", "기", "경", "신", "임", "계"]

    /// 문자 집합 순환 코드 (표 134): 코드 → 순환 문자 집합
    private static let cycleSets: [Int: [String]] = [
        8: hangulSyllables, 10: hangulJamo, 12: hangulNumbers,
        13: hanjaNumbers, 15: hangulGapja, 16: hanjaGapja,
    ]

    /// 연속 코드포인트 원문자 코드 (표 134): 코드 → (시작 코드포인트, 개수)
    private static let circledRanges: [Int: (first: Int, count: Int)] = [
        1: (0x2460, 20), // ①
        6: (0x24B6, 26), // Ⓐ
        7: (0x24D0, 26), // ⓐ
        9: (0x326E, 14), // ㉮
        11: (0x3260, 14), // ㉠
        14: (0x3280, 10), // ㊀
    ]

    /// number(1-based)를 표 134 번호 모양 코드 shape로 렌더한 문자열
    public static func string(for number: Int, shape: Int) -> String {
        guard number > 0 else { return String(number) }
        if let set = cycleSets[shape] {
            return cycled(number, in: set)
        }
        if let range = circledRanges[shape] {
            return circled(number, first: range.first, count: range.count)
        }
        switch shape {
        case 2: return roman(number)
        case 3: return roman(number).lowercased()
        case 4: return latin(number, base: "A")
        case 5: return latin(number, base: "a")
        default: return String(number)
        }
    }

    /// first부터 count개의 연속 코드포인트 집합에서 순환 선택
    private static func circled(_ number: Int, first: Int, count: Int) -> String {
        let index = (number - 1) % count
        guard let scalar = Unicode.Scalar(first + index) else { return String(number) }
        return String(Character(scalar))
    }

    private static func cycled(_ number: Int, in set: [String]) -> String {
        set[(number - 1) % set.count]
    }

    /// A, B, ..., Z, AA, AB, ... (엑셀식 자릿수 확장)
    private static func latin(_ number: Int, base: Character) -> String {
        var result = ""
        var value = number
        let baseValue = Int(base.asciiValue ?? 65)
        while value > 0 {
            let digit = (value - 1) % 26
            result = String(Character(UnicodeScalar(UInt8(baseValue + digit)))) + result
            value = (value - 1) / 26
        }
        return result
    }

    /// 로마 숫자 (대문자)
    private static func roman(_ number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let symbols = [
            "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I",
        ]
        var result = ""
        var remaining = number
        for (value, symbol) in zip(values, symbols) {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}
