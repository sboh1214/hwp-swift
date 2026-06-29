import Foundation

struct FixturePageNumberPositionExpectations: Decodable {
    let ctrlId: UInt32?
    let ctrlIdName: String?
    let property: UInt32?
    let userSymbol: UInt16?
    let headDecoration: UInt16?
    let tailDecoration: UInt16?
    let unused: UInt16?
    let unknown: UInt32?
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
