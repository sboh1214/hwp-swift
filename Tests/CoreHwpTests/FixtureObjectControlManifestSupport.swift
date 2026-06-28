import Foundation

struct FixtureHyperlinkExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let url: String?
    let urlLengthRawPayloadLength: Int?
    let urlLengthRawPayloadPrefixBytes: [UInt8]?
    let urlLengthRawPayloadSuffixBytes: [UInt8]?
    let urlRawPayloadLength: Int?
    let urlRawPayloadPrefixBytes: [UInt8]?
    let urlRawPayloadSuffixBytes: [UInt8]?
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

struct FixtureTableExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let rowCount: UInt16?
    let columnCount: UInt16?
    let commonCtrlPropertyRawPayloadLength: Int?
    let commonCtrlPropertyRawPayloadPrefixBytes: [UInt8]?
    let commonCtrlPropertyRawPayloadSuffixBytes: [UInt8]?
    let rawPayloadLength: Int?
    let rawTrailingLength: Int?
    let rawTrailingPrefixBytes: [UInt8]?
    let rawTrailingSuffixBytes: [UInt8]?
    let tablePropertyRawPayloadLength: Int?
    let tablePropertyRawPayloadPrefixBytes: [UInt8]?
    let tablePropertyRawPayloadSuffixBytes: [UInt8]?
    let tablePropertyRawTrailingLength: Int?
    let tablePropertyRawTrailingPrefixBytes: [UInt8]?
    let tablePropertyRawTrailingSuffixBytes: [UInt8]?
    let cellCount: Int?
    let paragraphCount: Int?
    let cellParagraphCounts: [Int]?
    let cellHeaderRawPayloadLengths: [Int]?
    let cellHeaderRawPayloadPrefixBytes: [[UInt8]]?
    let cellHeaderRawPayloadSuffixBytes: [[UInt8]]?
    let cellHeaderRawTrailingLengths: [Int]?
    let cellHeaderRawTrailingPrefixBytes: [[UInt8]]?
    let cellHeaderRawTrailingSuffixBytes: [[UInt8]]?
    let cellHeaderUnknownChildCounts: [Int]?
    let cellHeaderUnknownChildTagIds: [[UInt32]]?
    let cellHeaderUnknownChildPayloadLengths: [[Int]]?
    let cellHeaderUnknownChildPayloadPrefixBytes: [[[UInt8]]]?
    let cellHeaderUnknownChildPayloadSuffixBytes: [[[UInt8]]]?
    let cellHeaderNestedChildTagIds: [[[UInt32]]]?
    let cellHeaderNestedChildPayloadLengths: [[[Int]]]?
    let cellHeaderNestedChildPayloadPrefixBytes: [[[[UInt8]]]]?
    let cellHeaderNestedChildPayloadSuffixBytes: [[[[UInt8]]]]?
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

struct FixtureColumnExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let propertyRawValue: UInt16?
    let propertyCount: Int?
    let isSameWidth: Bool?
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

struct FixtureListControlExpectations: Decodable {
    let kind: String
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let rawPayloadLength: Int?
    let rawPayloadPrefixBytes: [UInt8]?
    let rawPayloadSuffixBytes: [UInt8]?
    let listCount: Int?
    let listParagraphCounts: [Int]?
    let listHeaderRawPayloadLengths: [Int]?
    let listHeaderRawPayloadPrefixBytes: [[UInt8]]?
    let listHeaderRawPayloadSuffixBytes: [[UInt8]]?
    let listHeaderRawTrailingLengths: [Int]?
    let listHeaderRawTrailingPrefixBytes: [[UInt8]]?
    let listHeaderRawTrailingSuffixBytes: [[UInt8]]?
    let listHeaderUnknownChildCounts: [Int]?
    let listHeaderUnknownChildTagIds: [[UInt32]]?
    let listHeaderUnknownChildPayloadLengths: [[Int]]?
    let listHeaderUnknownChildPayloadPrefixBytes: [[[UInt8]]]?
    let listHeaderUnknownChildPayloadSuffixBytes: [[[UInt8]]]?
    let listHeaderNestedChildTagIds: [[[UInt32]]]?
    let listHeaderNestedChildPayloadLengths: [[[Int]]]?
    let listHeaderNestedChildPayloadPrefixBytes: [[[[UInt8]]]]?
    let listHeaderNestedChildPayloadSuffixBytes: [[[[UInt8]]]]?
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
