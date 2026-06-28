import Foundation

struct FixtureDocInfoIdMappingsExpectations: Decodable {
    let binDataCount: Int?
    let faceNameKoreanCount: Int?
    let faceNameEnglishCount: Int?
    let faceNameChineseCount: Int?
    let faceNameJapaneseCount: Int?
    let faceNameEtcCount: Int?
    let faceNameSymbolCount: Int?
    let faceNameUserCount: Int?
    let faceNameRawPayloadTotalByteCount: Int?
    let borderFillCount: Int?
    let borderFillRawPayloadTotalByteCount: Int?
    let charShapeCount: Int?
    let charShapeRawPayloadTotalByteCount: Int?
    let charShapePropertyRawValues: [UInt32]?
    let tabDefCount: Int?
    let tabDefRawPayloadTotalByteCount: Int?
    let tabInfoRawPayloadTotalByteCount: Int?
    let numberingCount: Int?
    let bulletCount: Int?
    let paraShapeCount: Int?
    let paraShapeRawPayloadTotalByteCount: Int?
    let styleCount: Int?
    let memoShapeCount: Int?
    let memoShapeRawPayloadTotalByteCount: Int?
    let trackChangeCount: Int?
    let trackChangeRawPayloadTotalByteCount: Int?
    let trackChangeContentCount: Int?
    let trackChangeContentRawPayloadBytes: Int?
    let trackChangeAuthorCount: Int?
    let trackChangeAuthorRawPayloadBytes: Int?
    let forbiddenCharCount: Int?
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
