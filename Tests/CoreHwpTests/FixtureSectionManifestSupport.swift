import Foundation

struct FixtureSectionExpectations: Decodable {
    let rawPayloadLength: Int?
    let propertyRawValue: UInt32?
    /// 표 130 bits 20-21 — 구역 나눔으로 새 쪽이 생길 때의 쪽 번호 적용 방식
    /// (0 이어서 · 1 짝수 · 2 홀수). `propertyRawValue`가 원시 값을 잠그더라도
    /// 파생 필드의 비트 자리까지 함께 잠가야 리더가 다른 비트를 읽는 회귀를
    /// 잡는다 (#173).
    let newPageNumberApplyRawValue: Int?
    /// 사용자 지정 시작 쪽 번호 (0 = 앞 구역에 이어).
    let pageStartNumber: UInt16?
    let pageDefPropertyRawValue: UInt32?
    let pageDefRawPayloadLength: Int?
    let pageDefRawPayloadPrefixBytes: [UInt8]?
    let pageDefRawPayloadSuffixBytes: [UInt8]?
    let pageDefRawTrailingLength: Int?
    let pageDefRawTrailingPrefixBytes: [UInt8]?
    let pageDefRawTrailingSuffixBytes: [UInt8]?
    let footNoteShapePropertyRawValue: UInt32?
    let footNoteShapeRawPayloadLength: Int?
    let footNoteShapeRawPayloadPrefixBytes: [UInt8]?
    let footNoteShapeRawPayloadSuffixBytes: [UInt8]?
    let footNoteShapeRawTrailingLength: Int?
    let footNoteShapeRawTrailingPrefixBytes: [UInt8]?
    let footNoteShapeRawTrailingSuffixBytes: [UInt8]?
    let footNoteShapeSymbolRawValues: [UInt16]?
    let footNoteShapeSymbolRawPayloadLengths: [Int]?
    let footNoteShapeSymbolRawPayloadPrefixBytes: [[UInt8]]?
    let footNoteShapeSymbolRawPayloadSuffixBytes: [[UInt8]]?
    let endNoteShapePropertyRawValue: UInt32?
    let endNoteShapeRawPayloadLength: Int?
    let endNoteShapeRawPayloadPrefixBytes: [UInt8]?
    let endNoteShapeRawPayloadSuffixBytes: [UInt8]?
    let endNoteShapeRawTrailingLength: Int?
    let endNoteShapeRawTrailingPrefixBytes: [UInt8]?
    let endNoteShapeRawTrailingSuffixBytes: [UInt8]?
    let endNoteShapeSymbolRawValues: [UInt16]?
    let endNoteShapeSymbolRawPayloadLengths: [Int]?
    let endNoteShapeSymbolRawPayloadPrefixBytes: [[UInt8]]?
    let endNoteShapeSymbolRawPayloadSuffixBytes: [[UInt8]]?
    let pageBorderFillPropertyRawValues: [UInt32]?
    let pageBorderFillRawPayloadLengths: [Int]?
    let pageBorderFillRawPayloadPrefixBytes: [[UInt8]]?
    let pageBorderFillRawPayloadSuffixBytes: [[UInt8]]?
    let pageBorderFillRawTrailingLengths: [Int]?
    let pageBorderFillRawTrailingPrefixBytes: [[UInt8]]?
    let pageBorderFillRawTrailingSuffixBytes: [[UInt8]]?
    let unknownChildCount: Int?
    let unknownChildTagIds: [UInt32]?
    let unknownChildPayloadLengths: [Int]?
    let unknownChildPayloadPrefixBytes: [[UInt8]]?
    let unknownChildPayloadSuffixBytes: [[UInt8]]?
    let unknownChildChildTagIds: [[UInt32]]?
    let unknownChildChildPayloadLengths: [[Int]]?
    let unknownChildChildPayloadPrefixBytes: [[[UInt8]]]?
    let unknownChildChildPayloadSuffixBytes: [[[UInt8]]]?
}
