import Foundation
import Nimble
import XCTest

final class PageNumberPositionFeatureGateTests: XCTestCase {
    func testPageNumberPositionGateAcceptsCompletePayloadSamples() throws {
        let position = try decodePageNumberPosition(completePageNumberPositionJSON)

        expect(pageNumberPositionHasPayloadSamples(position)) == true
    }

    func testPageNumberPositionGateAcceptsZeroUnknownChildrenWithoutSampleArrays() throws {
        let position = try decodePageNumberPosition("""
        {
          "ctrlId": 1885826672,
          "ctrlIdName": "pageNumberPosition",
          "property": 1280,
          "userSymbol": 0,
          "headDecoration": 0,
          "tailDecoration": 0,
          "unused": 0,
          "unknown": 0,
          "rawPayloadLength": 16,
          "rawPayloadPrefixBytes": [112, 110, 103, 112],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "unknownChildCount": 0
        }
        """)

        expect(pageNumberPositionHasPayloadSamples(position)) == true
    }

    func testPageNumberPositionGateRejectsMissingRawPayloadSamples() throws {
        let position = try decodePageNumberPosition(
            completePageNumberPositionJSON.replacingOccurrences(
                of: "\"rawPayloadSuffixBytes\": [221, 204, 187, 170, 202, 254],",
                with: ""
            )
        )

        expect(pageNumberPositionHasPayloadSamples(position)) == false
    }

    func testPageNumberPositionGateRejectsUnknownChildWithoutPayloadSamples() throws {
        let position = try decodePageNumberPosition(
            completePageNumberPositionJSON.replacingOccurrences(
                of: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [698],
                  "unknownChildPayloadLengths": [4],
                  "unknownChildPayloadPrefixBytes": [[1, 2]],
                  "unknownChildPayloadSuffixBytes": [[3, 4]],
                """,
                with: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [698],
                """
            )
        )

        expect(pageNumberPositionHasPayloadSamples(position)) == false
    }

    func testPageNumberPositionGateRejectsNestedChildWithoutPayloadSamples() throws {
        let position = try decodePageNumberPosition(
            completePageNumberPositionJSON.replacingOccurrences(
                of: """
                  "unknownChildChildTagIds": [[697]],
                  "unknownChildChildPayloadLengths": [[3]],
                  "unknownChildChildPayloadPrefixBytes": [[[5, 6]]],
                  "unknownChildChildPayloadSuffixBytes": [[[6, 7]]]
                """,
                with: """
                  "unknownChildChildTagIds": [[697]],
                  "unknownChildChildPayloadLengths": [[3]]
                """
            )
        )

        expect(pageNumberPositionHasPayloadSamples(position)) == false
    }
}

private func decodePageNumberPosition(_ json: String) throws
    -> FixturePageNumberPositionExpectations
{
    try JSONDecoder().decode(FixturePageNumberPositionExpectations.self, from: Data(json.utf8))
}

private let completePageNumberPositionJSON = """
{
  "ctrlId": 1885826672,
  "ctrlIdName": "pageNumberPosition",
  "property": 16909060,
  "userSymbol": 0,
  "headDecoration": 45,
  "tailDecoration": 45,
  "unused": 45,
  "unknown": 2864434397,
  "rawPayloadLength": 22,
  "rawPayloadPrefixBytes": [112, 110, 103, 112, 4, 3, 2, 1],
  "rawPayloadSuffixBytes": [221, 204, 187, 170, 202, 254],
  "rawTrailingLength": 2,
  "rawTrailingPrefixBytes": [202, 254],
  "rawTrailingSuffixBytes": [202, 254],
  "unknownChildCount": 1,
  "unknownChildTagIds": [698],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[1, 2]],
  "unknownChildPayloadSuffixBytes": [[3, 4]],
  "unknownChildChildTagIds": [[697]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[5, 6]]],
  "unknownChildChildPayloadSuffixBytes": [[[6, 7]]]
}
"""
