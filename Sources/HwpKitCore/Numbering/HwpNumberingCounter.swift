import CoreHwp
import Foundation

/// 문단 번호·개요 번호의 **카운터** — 한 종류(개요 또는 번호 매기기)의
/// 수준별 현재 번호와 그 값이 어느 정의로 세어졌는지를 든다 (#153).
///
/// 규칙은 한컴 도움말의 두 대화상자를 따른다 (`HwpNumbering.continuesPreviousList`
/// 참조). 상위 수준을 매기면 그 아래 수준은 비워지고(다음에 그 수준이 나오면
/// 시작 번호부터), 같은 수준은 1씩 는다. 정의가 바뀌는 자리는 종류마다 다르다 —
/// 개요는 **구역 시작**(`beginSection`), 번호 매기기는 **정의가 다른 번호 문단**
/// (`number(level:definition:)`이 스스로 감지) — 이고 그때 새 정의의 시작 번호
/// 방식이 새 번호(전부 비움)인지 이어 매기기(그대로 둠)인지를 정한다.
///
/// 비워진 수준이 다수준 형식·`^n` 경로에 참조되면 시작 번호를 보인다 —
/// 한글.app 개요 번호 모양 대화상자의 미리보기가 모든 수준을 시작 번호로
/// 그리는 것에 맞췄다(2수준 없이 3수준이 오는 실물은 없어 한글.app 실측은
/// 아직이다).
struct HwpNumberingCounter {
    /// 수준(1-10)별 현재 번호. nil은 마지막 비움 뒤 아직 매겨지지 않은 수준.
    private var numbers: [Int?] = Array(repeating: nil, count: HwpNumberingCounter.levelCount)
    /// 마지막으로 번호를 낸 정의 — 번호 매기기의 정의 교체 감지용.
    private(set) var definitionIndex: UInt32?

    static let levelCount = 10

    /// 새 구역이 시작한다 — 개요 카운터 전용. 구역 정의가 가리키는 정의가 새
    /// 번호로 시작하면 전부 비우고, 이어 매기기면 앞 구역의 번호를 그대로 둔다.
    mutating func beginSection(definitionIndex: UInt32, definition: CoreHwp.HwpNumbering) {
        if !definition.continuesPreviousList {
            reset()
        }
        self.definitionIndex = definitionIndex
    }

    /// 수준 `level`의 문단에 번호를 매기고 1수준부터 그 수준까지의 번호를 돌려준다.
    ///
    /// 정의가 마지막 번호의 정의와 다르면 정의 교체다 — 새 정의가 새 번호로
    /// 시작하면 먼저 전부 비운다(번호 매기기의 "새 번호 목록 시작"). 개요는
    /// 한 구역 안에서 정의가 바뀌지 않으므로 이 분기는 `beginSection`과 같은
    /// 결과를 낸다.
    mutating func number(
        level: Int,
        definitionIndex: UInt32,
        definition: CoreHwp.HwpNumbering
    ) -> [Int] {
        let clamped = min(max(level, 1), Self.levelCount)
        if definitionIndex != self.definitionIndex, !definition.continuesPreviousList {
            reset()
        }
        self.definitionIndex = definitionIndex
        let slot = clamped - 1
        numbers[slot] = (numbers[slot] ?? definition.startingNumber(forLevel: clamped) - 1) + 1
        for deeper in numbers.indices where deeper > slot {
            numbers[deeper] = nil
        }
        return (1 ... clamped).map { numbers[$0 - 1] ?? definition.startingNumber(forLevel: $0) }
    }

    private mutating func reset() {
        numbers = Array(repeating: nil, count: Self.levelCount)
    }
}
