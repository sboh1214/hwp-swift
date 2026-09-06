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
    /// 번호 정의 — `HwpIndex.numbering(id:)`의 0-based 키.
    public let definitionIndex: UInt32
    /// 1수준부터 이 문단의 수준까지의 번호 — 개수가 곧 수준이라 `level`을 따로
    /// 저장하지 않는다 (같은 문단을 나타내는 두 값이 수준만 달라 어긋날 길이 없다).
    public let numbers: [Int]
    /// 번호 형식으로 조립한 라벨. 형식 슬롯이 비어 있으면 빈 문자열이다 —
    /// 번호는 세어지되 보일 글자가 없다. `textUnitCeiling`을 넘는 라벨은 스칼라
    /// 경계에서 잘린 접두다.
    public let text: String

    /// 라벨 하나의 상한 (UTF-16 단위). 실제 라벨은 `^n` 경로가 10수준 로마
    /// 숫자여도 200단위를 넘지 않는다 — 이 값은 표시 상한이 아니라, 형식 문자열
    /// (표 38 WORD 길이, 최대 65,535 단위)에 지시자를 수만 번 적은 조작 문서가
    /// 문단마다 수 MB 라벨을 만들어 문서를 여는 순간 메모리를 삼키지 못하게 하는
    /// 안전판이다. 문서 전체 상한은 `HwpParagraphNumbering.maximumDocumentEntries`.
    public static let textUnitCeiling = 512

    public init(kind: Kind, definitionIndex: UInt32, numbers: [Int], text: String) {
        self.kind = kind
        self.definitionIndex = definitionIndex
        self.numbers = numbers
        self.text = text
    }

    /// 사람이 읽는 수준 (1-기반) — `numbers.count`.
    public var level: Int {
        numbers.count
    }

    /// 이 문단 자신의 수준 번호 — `numbers.last`.
    public var number: Int {
        numbers.last ?? 0
    }
}
