import Foundation

struct FixtureFieldControlExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let semanticKind: String?
    let isMemoField: Bool?
    let isRevisionField: Bool?
    let fieldParameter: String?
    let fieldParameterHeaderRawLength: Int?
    let fieldParameterHeaderRawPrefixBytes: [UInt8]?
    let fieldParameterHeaderRawSuffixBytes: [UInt8]?
    let fieldParameterCharacterCount: Int?
    let fieldParameterLengthRawLength: Int?
    let fieldParameterLengthRawPrefixBytes: [UInt8]?
    let fieldParameterLengthRawSuffixBytes: [UInt8]?
    let fieldParameterRawPayloadLength: Int?
    let fieldParameterRawPayloadPrefixBytes: [UInt8]?
    let fieldParameterRawPayloadSuffixBytes: [UInt8]?
    let fieldParameterRawTrailingLength: Int?
    let fieldParameterRawTrailingPrefixBytes: [UInt8]?
    let fieldParameterRawTrailingSuffixBytes: [UInt8]?
    let memoParameter: FixtureMemoFieldParameterExpectations?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
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

struct FixtureMemoFieldParameterExpectations: Decodable {
    let rawValue: String?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let marker: String?
    let components: [String]?
    let fields: [String]?
    let author: String?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
}
