import Foundation

/// 문단 하나에 생성된 문단 번호·개요 번호 (#153).
///
/// `text`가 문단 앞에 붙는 라벨이고(`I.`·`가.`·`(1)`), `numbers`는 그 라벨이
/// 세어진 수준별 번호다 — 1수준부터 이 문단의 수준까지 순서대로이며, 이 문단
/// 뒤로 한 번도 매겨지지 않은 상위 수준은 그 수준의 시작 번호로 채운다
/// (`^1.^2` 같은 다수준 형식과 `^n` 경로가 읽는 값이다).
public struct HwpParagraphNumber: Hashable, Sendable {
    /// 문단 머리 종류 (표 44 bit 23-24) — 카운터는 종류마다 따로 돈다.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// 1 — 개요. 정의는 구역 정의의 `numberParaShapeId`.
        case outline
        /// 2 — 번호 매기기. 정의는 문단 모양의 `numberingOrBulletId`.
        case numbering
    }

    public let kind: Kind
    /// 사람이 읽는 수준 (1-기반).
    public let level: Int
    /// 번호 정의 — `HwpIndex.numbering(id:)`의 0-based 키.
    public let definitionIndex: UInt32
    /// 1수준부터 `level`까지의 번호. 개수는 언제나 `level`이다.
    public let numbers: [Int]
    /// 번호 형식으로 조립한 라벨. 형식 슬롯이 비어 있으면 빈 문자열이다 —
    /// 번호는 세어지되 보일 글자가 없다.
    public let text: String

    public init(kind: Kind, level: Int, definitionIndex: UInt32, numbers: [Int], text: String) {
        self.kind = kind
        self.level = level
        self.definitionIndex = definitionIndex
        self.numbers = numbers
        self.text = text
    }

    /// 이 문단 자신의 수준 번호 — `numbers.last`.
    public var number: Int {
        numbers.last ?? 0
    }
}
