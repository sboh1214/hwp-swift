import Foundation
import Nimble
import XCTest

final class FixtureTableFeatureGateTests: XCTestCase {
    func testTableGateAcceptsAlignedPayloadSamples() throws {
        let table = try decodeTableExpectation(completeTableJSON)

        expect(tableHasPayloadSamples(table)) == true
    }

    func testTableGateRequiresCellParagraphCountsToMatchParagraphCount() throws {
        let table = try decodeTableExpectation(completeTableJSON.replacingOccurrences(
            of: "\"cellParagraphCounts\": [1, 2]",
            with: "\"cellParagraphCounts\": [1, 1]"
        ))

        expect(tableHasPayloadSamples(table)) == false
    }

    func testTableGateRequiresCellPayloadSamplesToMatchCellCount() throws {
        let table = try decodeTableExpectation(completeTableJSON.replacingOccurrences(
            of: "\"cellHeaderRawPayloadPrefixBytes\": [[1], [2]]",
            with: "\"cellHeaderRawPayloadPrefixBytes\": [[1]]"
        ))

        expect(tableHasPayloadSamples(table)) == false
    }

    func testTableGateRequiresTopLevelUnknownChildPayloadSamples() throws {
        let table = try decodeTableExpectation(completeTableJSON.replacingOccurrences(
            of: """
              "unknownChildCount": 1,
              "unknownChildTagIds": [706],
              "unknownChildPayloadLengths": [4],
              "unknownChildPayloadPrefixBytes": [[5, 6]],
              "unknownChildPayloadSuffixBytes": [[7, 8]],
            """,
            with: """
              "unknownChildCount": 1,
              "unknownChildTagIds": [706],
            """
        ))

        expect(tableHasPayloadSamples(table)) == false
    }

    func testTableGateRequiresCellHeaderUnknownChildPayloadSamples() throws {
        let table = try decodeTableExpectation(completeTableJSON.replacingOccurrences(
            of: """
              "cellHeaderUnknownChildCounts": [1, 0],
              "cellHeaderUnknownChildTagIds": [[705], []],
              "cellHeaderUnknownChildPayloadLengths": [[4], []],
              "cellHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]], []],
              "cellHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]], []],
            """,
            with: """
              "cellHeaderUnknownChildCounts": [1, 0],
              "cellHeaderUnknownChildTagIds": [[705], []],
            """
        ))

        expect(tableHasPayloadSamples(table)) == false
    }
}

private func decodeTableExpectation(_ json: String) throws -> FixtureTableExpectations {
    try JSONDecoder().decode(FixtureTableExpectations.self, from: Data(json.utf8))
}

private let completeTableJSON = """
{
  "ctrlId": 1952607264,
  "ctrlIdName": "table",
  "rowCount": 1,
  "columnCount": 2,
  "commonCtrlPropertyRawPayloadLength": 4,
  "commonCtrlPropertyRawPayloadPrefixBytes": [1, 2],
  "commonCtrlPropertyRawPayloadSuffixBytes": [3, 4],
  "rawPayloadLength": 6,
  "rawTrailingLength": 2,
  "rawTrailingPrefixBytes": [170],
  "rawTrailingSuffixBytes": [187],
  "tablePropertyRawPayloadLength": 4,
  "tablePropertyRawPayloadPrefixBytes": [9, 8],
  "tablePropertyRawPayloadSuffixBytes": [7, 6],
  "tablePropertyRawTrailingLength": 0,
  "tablePropertyRawTrailingPrefixBytes": [],
  "tablePropertyRawTrailingSuffixBytes": [],
  "cellCount": 2,
  "paragraphCount": 3,
  "cellParagraphCounts": [1, 2],
  "cellHeaderRawPayloadLengths": [4, 4],
  "cellHeaderRawPayloadPrefixBytes": [[1], [2]],
  "cellHeaderRawPayloadSuffixBytes": [[3], [4]],
  "cellHeaderRawTrailingLengths": [1, 1],
  "cellHeaderRawTrailingPrefixBytes": [[5], [6]],
  "cellHeaderRawTrailingSuffixBytes": [[7], [8]],
  "cellHeaderUnknownChildCounts": [1, 0],
  "cellHeaderUnknownChildTagIds": [[705], []],
  "cellHeaderUnknownChildPayloadLengths": [[4], []],
  "cellHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]], []],
  "cellHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]], []],
  "cellHeaderNestedChildTagIds": [[[704]], []],
  "cellHeaderNestedChildPayloadLengths": [[[3]], []],
  "cellHeaderNestedChildPayloadPrefixBytes": [[[[21, 22]]], []],
  "cellHeaderNestedChildPayloadSuffixBytes": [[[[22, 23]]], []],
  "unknownChildCount": 1,
  "unknownChildTagIds": [706],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[5, 6]],
  "unknownChildPayloadSuffixBytes": [[7, 8]],
  "unknownChildChildTagIds": [[708]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[31, 32]]],
  "unknownChildChildPayloadSuffixBytes": [[[32, 33]]]
}
"""
