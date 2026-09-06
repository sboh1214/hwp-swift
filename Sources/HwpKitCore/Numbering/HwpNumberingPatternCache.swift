import CoreHwp
import Foundation

/// 정의·수준별 번호 형식 분해 결과의 메모 (#153).
///
/// `HwpNumberingFormat.pattern`은 부를 때마다 형식 문자열 전체를 다시 분해한다.
/// 형식은 표 38의 WORD 길이(65,535 단위)까지 길 수 있고 한 정의를 수만 문단이
/// 참조할 수 있으므로, 문단마다 분해하면 라벨 출력 상한(`HwpParagraphNumber.
/// textUnitCeiling`)이 걸리기도 전에 입력 길이 × 문단 수의 일이 든다 — 20,000
/// 항목이면 약 13억 스칼라다. 정의 하나의 수준 하나는 한 번만 분해한다: 정의 수 ×
/// 10수준이 상한이고, 그 뒤 문단은 이미 분해된 토큰 배열을 출력 상한까지만 읽는다.
struct HwpNumberingPatternCache {
    private var patterns: [Key: HwpNumberingFormatPattern?] = [:]
    /// 실제로 분해한 횟수 — 테스트 전용 관측점.
    private(set) var parseCount = 0

    private struct Key: Hashable {
        let definitionIndex: UInt32
        let level: Int
    }

    /// 정의의 수준 형식을 분해한 결과. 형식 슬롯이 없으면 nil이고 그 사실도 메모한다.
    mutating func pattern(
        definitionIndex: UInt32,
        level: Int,
        definition: CoreHwp.HwpNumbering
    ) -> HwpNumberingFormatPattern? {
        let key = Key(definitionIndex: definitionIndex, level: level)
        if let cached = patterns[key] {
            return cached
        }
        parseCount += 1
        let pattern = definition.format(forLevel: level)?.pattern
        patterns[key] = .some(pattern)
        return pattern
    }
}
