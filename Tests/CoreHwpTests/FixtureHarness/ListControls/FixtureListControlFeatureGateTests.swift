import Foundation
import Nimble
import XCTest

final class FixtureListControlFeatureGateTests: XCTestCase {
    func testListControlGateAcceptsAlignedPayloadSamples() throws {
        let control = try decodeListControlExpectation(completeListControlJSON)

        expect(listControlHasPayloadSamples(control)) == true
    }

    func testListControlGateRequiresParagraphCountsToMatchListCount() throws {
        let control = try decodeListControlExpectation(
            completeListControlJSON.replacingOccurrences(
                of: "\"listParagraphCounts\": [1, 0]",
                with: "\"listParagraphCounts\": [1]"
            )
        )

        expect(listControlHasPayloadSamples(control)) == false
    }

    func testListControlGateRequiresHeaderPayloadSamplesToMatchListCount() throws {
        let control = try decodeListControlExpectation(
            completeListControlJSON.replacingOccurrences(
                of: "\"listHeaderRawPayloadPrefixBytes\": [[1], [2]]",
                with: "\"listHeaderRawPayloadPrefixBytes\": [[1]]"
            )
        )

        expect(listControlHasPayloadSamples(control)) == false
    }

    func testListControlGateRequiresTopLevelUnknownChildPayloadSamples() throws {
        let control = try decodeListControlExpectation(
            completeListControlJSON.replacingOccurrences(
                of: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [690],
                  "unknownChildPayloadLengths": [4],
                  "unknownChildPayloadPrefixBytes": [[5, 6]],
                  "unknownChildPayloadSuffixBytes": [[7, 8]],
                """,
                with: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [690],
                """
            )
        )

        expect(listControlHasPayloadSamples(control)) == false
    }

    func testListControlGateRequiresHeaderUnknownChildPayloadSamples() throws {
        let control = try decodeListControlExpectation(
            completeListControlJSON.replacingOccurrences(
                of: """
                  "listHeaderUnknownChildCounts": [1, 0],
                  "listHeaderUnknownChildTagIds": [[689], []],
                  "listHeaderUnknownChildPayloadLengths": [[4], []],
                  "listHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]], []],
                  "listHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]], []],
                """,
                with: """
                  "listHeaderUnknownChildCounts": [1, 0],
                  "listHeaderUnknownChildTagIds": [[689], []],
                """
            )
        )

        expect(listControlHasPayloadSamples(control)) == false
    }
}

private func decodeListControlExpectation(_ json: String) throws
    -> FixtureListControlExpectations
{
    try JSONDecoder().decode(FixtureListControlExpectations.self, from: Data(json.utf8))
}

private let completeListControlJSON = """
{
  "kind": "header",
  "ctrlId": 1751474532,
  "ctrlIdName": "header",
  "rawPayloadLength": 6,
  "rawPayloadPrefixBytes": [100, 97, 101, 104],
  "rawPayloadSuffixBytes": [171, 205],
  "listCount": 2,
  "listParagraphCounts": [1, 0],
  "listHeaderRawPayloadLengths": [10, 10],
  "listHeaderRawPayloadPrefixBytes": [[1], [2]],
  "listHeaderRawPayloadSuffixBytes": [[3], [4]],
  "listHeaderRawTrailingLengths": [2, 2],
  "listHeaderRawTrailingPrefixBytes": [[5], [6]],
  "listHeaderRawTrailingSuffixBytes": [[7], [8]],
  "listHeaderUnknownChildCounts": [1, 0],
  "listHeaderUnknownChildTagIds": [[689], []],
  "listHeaderUnknownChildPayloadLengths": [[4], []],
  "listHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]], []],
  "listHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]], []],
  "listHeaderNestedChildTagIds": [[[688]], []],
  "listHeaderNestedChildPayloadLengths": [[[3]], []],
  "listHeaderNestedChildPayloadPrefixBytes": [[[[11, 12]]], []],
  "listHeaderNestedChildPayloadSuffixBytes": [[[[12, 13]]], []],
  "unknownChildCount": 1,
  "unknownChildTagIds": [690],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[5, 6]],
  "unknownChildPayloadSuffixBytes": [[7, 8]],
  "unknownChildChildTagIds": [[691]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[15, 16]]],
  "unknownChildChildPayloadSuffixBytes": [[[16, 17]]]
}
"""
