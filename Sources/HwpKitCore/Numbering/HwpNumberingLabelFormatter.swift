import CoreHwp
import Foundation

/// 번호 형식 토큰(`HwpNumberingFormatPattern`)과 수준별 번호로 라벨 문자열을
/// 조립한다 (#153). 순수 함수라 문서 순서와 무관하다.
enum HwpNumberingLabelFormatter {
    /// - Parameters:
    ///   - definition: 번호 정의 — 수준별 형식(`format(forLevel:)`)과 번호 모양을 준다.
    ///   - level: 이 문단의 수준 (1-10).
    ///   - numbers: 1수준부터 `level`까지의 번호 (`HwpNumberingCounter.number`).
    ///     참조한 수준이 이 배열 밖(문단 수준보다 깊은 `^9` 등)이면 그 수준의 시작
    ///     번호를 쓴다.
    static func text(
        definition: CoreHwp.HwpNumbering,
        level: Int,
        numbers: [Int]
    ) -> String {
        guard let format = definition.format(forLevel: level) else { return "" }
        var text = ""
        for token in format.pattern.tokens {
            switch token {
            case let .literal(literal):
                text += literal
            case let .level(referenced):
                text += rendered(level: referenced, definition: definition, numbers: numbers)
            case let .levelPath(trailingPeriod):
                text += (1 ... max(level, 1)).map {
                    rendered(level: $0, definition: definition, numbers: numbers)
                }.joined(separator: ".")
                if trailingPeriod {
                    text += "."
                }
            }
        }
        return text
    }

    /// 수준 하나의 번호를 그 수준의 번호 모양(표 41 = 표 134의 0-14)으로 그린다.
    /// 문단 머리 정보가 없는(12바이트 미만) 슬롯은 숫자다.
    private static func rendered(
        level: Int,
        definition: CoreHwp.HwpNumbering,
        numbers: [Int]
    ) -> String {
        let number = numbers.indices.contains(level - 1)
            ? numbers[level - 1]
            : definition.startingNumber(forLevel: level)
        let shape = definition.format(forLevel: level)?.paraHeadInfo?.numberFormat ?? 0
        return HwpNumberFormat.string(for: number, shape: shape)
    }
}
