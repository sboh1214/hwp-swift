import CoreHwp
import Foundation

/// 문단 번호·개요 번호의 **카운터** — 한 종류(개요 또는 번호 매기기)의 정의별
/// 수준 번호 상태 (#153).
///
/// 규칙은 한글.app 12.30 실측(2026-09-06, `numbering-sequence` 픽스처 쌍)이다.
/// - **정의마다 목록이 하나다.** 같은 정의의 문단은 사이에 본문·다른 정의의
///   목록·구역 경계·표가 끼어도 자기 번호를 잇는다(실측: 정의 3의 목록이
///   구역을 넘어 `4.`·`5.`, 표 셀의 정의 6 목록 `9.`·`10.`을 지나 `6.`, 그 뒤
///   정의 6이 `11.`).
/// - **정의의 첫 문단**에서만 시작 번호 방식을 본다: `continuesPreviousList`
///   (시작 번호 0)면 같은 종류에서 **직전에 쓰인 정의의 번호를 물려받고**
///   (개요 "앞 구역의 개요 번호에 이어서" — 구역 나누기가 만든 정의 4가 앞
///   구역의 `가.`·`1.` 뒤를 `나.`·`2.`로 이었다; 번호 매기기 "앞 번호 목록에
///   이어"), 아니면 수준별 시작 번호에서 새로 센다.
/// - 상위 수준을 매기면 그 아래 수준은 비워지고, **건너뛴 상위 수준은 시작
///   번호로 매겨진 것으로 친다** — 1수준 뒤에 바로 3수준이 오면 2수준은 시작
///   번호가 되고, 다음 2수준 문단은 그다음 번호다(실측: `1.` → 3수준 `1)` →
///   2수준 `나.`).
///
/// 비워진 하위 수준이 형식에 참조되면(문단 수준보다 깊은 `^9` 등) 시작 번호를
/// 보인다 — 한글 대화상자 미리보기 규약이고 실물은 없다.
struct HwpNumberingCounter {
    /// 정의(`HwpIndex.numbering(id:)`의 0-based 키) → 수준(1-10)별 현재 번호.
    /// nil은 마지막 비움 뒤 아직 매겨지지 않은 수준.
    private var states: [UInt32: [Int?]] = [:]
    /// 마지막으로 번호를 낸 정의 — 새 정의가 이어 받을 상대.
    private(set) var definitionIndex: UInt32?

    static let levelCount = 10

    /// 새 구역이 시작한다 — 개요 카운터 전용. 구역 정의가 가리키는 정의를 활성화해
    /// 처음 쓰이는 정의면 시작 번호 방식대로 앞 정의의 번호를 물려받거나 새로 센다.
    mutating func beginSection(definitionIndex: UInt32, definition: CoreHwp.HwpNumbering) {
        activate(definitionIndex, definition)
    }

    /// 수준 `level`의 문단에 번호를 매기고 1수준부터 그 수준까지의 번호를 돌려준다.
    mutating func number(
        level: Int,
        definitionIndex: UInt32,
        definition: CoreHwp.HwpNumbering
    ) -> [Int] {
        activate(definitionIndex, definition)
        let clamped = min(max(level, 1), Self.levelCount)
        var numbers = states[definitionIndex] ?? Self.fresh
        // 건너뛴 상위 수준은 시작 번호로 매겨진 것으로 친다.
        for upper in 0 ..< clamped - 1 where numbers[upper] == nil {
            numbers[upper] = definition.startingNumber(forLevel: upper + 1)
        }
        let slot = clamped - 1
        numbers[slot] = (numbers[slot] ?? definition.startingNumber(forLevel: clamped) - 1) + 1
        for deeper in numbers.indices where deeper > slot {
            numbers[deeper] = nil
        }
        states[definitionIndex] = numbers
        return (1 ... clamped).map { numbers[$0 - 1] ?? definition.startingNumber(forLevel: $0) }
    }

    /// 정의를 현재 정의로 삼는다. 처음 쓰이는 정의는 시작 번호 방식대로 직전
    /// 정의의 번호를 물려받거나(이어 매기기) 빈 상태(새 번호)에서 시작한다.
    private mutating func activate(_ index: UInt32, _ definition: CoreHwp.HwpNumbering) {
        if states[index] == nil {
            let inherited = definition.continuesPreviousList
                ? definitionIndex.flatMap { states[$0] } : nil
            states[index] = inherited ?? Self.fresh
        }
        definitionIndex = index
    }

    private static let fresh: [Int?] = Array(repeating: nil, count: levelCount)
}
