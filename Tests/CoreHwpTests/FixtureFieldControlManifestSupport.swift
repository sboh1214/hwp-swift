import Foundation

struct FixtureFieldControlExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let semanticKind: String?
    let isMemoField: Bool?
    let isRevisionField: Bool?
    let properties: UInt32?
    let propertyInitialState: Bool?
    let extraProperties: UInt8?
    let commandCharacterCount: Int?
    let command: String?
    let commandLengthRawLength: Int?
    let commandLengthRawPrefixBytes: [UInt8]?
    let commandLengthRawSuffixBytes: [UInt8]?
    let commandRawPayloadLength: Int?
    let commandRawPayloadPrefixBytes: [UInt8]?
    let commandRawPayloadSuffixBytes: [UInt8]?
    let commandRawTrailingLength: Int?
    let commandRawTrailingPrefixBytes: [UInt8]?
    let commandRawTrailingSuffixBytes: [UInt8]?
    let fieldId: UInt32?
    let memoIndex: Int32?
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
