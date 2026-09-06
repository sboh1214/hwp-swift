import CoreHwp
import Foundation

/// 번호 형식 토큰(`HwpNumberingFormatPattern`)과 수준별 번호로 라벨 문자열을
/// 조립한다 (#153). 순수 함수라 문서 순서와 무관하다.
///
/// 라벨은 `HwpParagraphNumber.textUnitCeiling`(UTF-16 단위)에서 끊는다. 형식
/// 문자열은 표 38의 WORD 길이만큼(65,535 단위) 길 수 있어 `^1`을 3만 번 적은
/// 정의 하나로 문단마다 수 MB 라벨이 만들어지고, `HwpPaginator`가 문서를 여는
/// 즉시 전 문단의 라벨을 만들어 보관하므로 시작 번호를 접는 것만으로는 막히지
/// 않는다(실측: 21KB HWPX, 번호 문단 50개가 112MB·9.8초). 그래서 만드는 **도중**에
/// 천장에서 멈춘다 — 다 만든 뒤 자르면 그 순간 이미 메모리를 삼킨다. 자르는
/// 자리는 유니코드 스칼라 경계라 대리 쌍이 쪼개지지 않고, 결과는 언제나 온전한
/// 라벨의 접두다.
enum HwpNumberingLabelFormatter {
    /// 형식을 그 자리에서 분해하는 편의 진입점 — 한 번 부르는 자리(테스트) 전용이다.
    /// 문단마다 부르는 순회는 `HwpNumberingPatternCache`로 분해 결과를 메모해
    /// `text(pattern:definition:level:numbers:)`에 넘긴다.
    static func text(
        definition: CoreHwp.HwpNumbering,
        level: Int,
        numbers: [Int]
    ) -> String {
        text(
            pattern: definition.format(forLevel: level)?.pattern,
            definition: definition, level: level, numbers: numbers
        )
    }

    /// - Parameters:
    ///   - pattern: 이 수준의 형식을 분해한 토큰 — 형식 슬롯이 없으면 nil(빈 라벨).
    ///   - definition: 번호 정의 — 수준별 번호 모양과 시작 번호를 준다.
    ///   - level: 이 문단의 수준 (1-10).
    ///   - numbers: 1수준부터 `level`까지의 번호 (`HwpNumberingCounter.number`).
    ///     참조한 수준이 이 배열 밖(문단 수준보다 깊은 `^9` 등)이면 그 수준의 시작
    ///     번호를 쓴다.
    static func text(
        pattern: HwpNumberingFormatPattern?,
        definition: CoreHwp.HwpNumbering,
        level: Int,
        numbers: [Int]
    ) -> String {
        guard let pattern else { return "" }
        var builder = BoundedBuilder(ceiling: HwpParagraphNumber.textUnitCeiling)
        for token in pattern.tokens {
            let fits = switch token {
            case let .literal(literal):
                builder.append(literal)
            case let .level(referenced):
                builder.append(
                    rendered(level: referenced, definition: definition, numbers: numbers)
                )
            case let .levelPath(trailingPeriod):
                appendLevelPath(
                    to: &builder, level: level, trailingPeriod: trailingPeriod,
                    definition: definition, numbers: numbers
                )
            }
            guard fits else { break }
        }
        return builder.text
    }

    /// `^n`·`^N` — 1수준부터 문단 수준까지를 `.`로 잇고 `^N`은 마침표를 하나 더
    /// 찍는다. 천장에 걸리면 false.
    private static func appendLevelPath(
        to builder: inout BoundedBuilder,
        level: Int,
        trailingPeriod: Bool,
        definition: CoreHwp.HwpNumbering,
        numbers: [Int]
    ) -> Bool {
        for pathLevel in 1 ... max(level, 1) {
            if pathLevel > 1, !builder.append(".") {
                return false
            }
            let piece = rendered(level: pathLevel, definition: definition, numbers: numbers)
            guard builder.append(piece) else { return false }
        }
        return !trailingPeriod || builder.append(".")
    }

    /// 수준 하나의 번호를 그 수준의 번호 모양(표 41 = 표 134의 0-14; 4비트 필드라
    /// 15까지 담기고 그 밖의 표 134 코드는 파서가 접는다)으로 그린다. 문단 머리
    /// 정보가 없는(12바이트 미만) 슬롯은 숫자다.
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

    /// UTF-16 천장까지만 받는 문자열 조립기 — 스칼라 단위로 더하다 천장을 넘기는
    /// 스칼라 앞에서 멈춘다.
    private struct BoundedBuilder {
        let ceiling: Int
        private var scalars = String.UnicodeScalarView()
        private var units = 0

        init(ceiling: Int) {
            self.ceiling = ceiling
        }

        var text: String {
            String(scalars)
        }

        /// 전부 더했으면 true, 천장에 걸려 멈췄으면 false.
        mutating func append(_ piece: String) -> Bool {
            for scalar in piece.unicodeScalars {
                let width = UTF16.width(scalar)
                guard units + width <= ceiling else { return false }
                units += width
                scalars.append(scalar)
            }
            return true
        }
    }
}
