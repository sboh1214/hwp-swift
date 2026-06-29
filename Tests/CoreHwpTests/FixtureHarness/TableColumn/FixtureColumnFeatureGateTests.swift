import Foundation
import Nimble
import XCTest

final class ColumnFeatureGateTests: XCTestCase {
    func testColumnGateAcceptsCompletePayloadSamples() throws {
        let column = try decodeColumn(completeColumnJSON)

        expect(columnHasPayloadSamples(column)) == true
    }

    func testColumnGateAcceptsZeroUnknownChildrenWithoutSampleArrays() throws {
        let column = try decodeColumn("""
        {
          "ctrlId": 1668246628,
          "ctrlIdName": "column",
          "rawPayloadLength": 16,
          "rawPayloadPrefixBytes": [100, 108, 111, 99],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "rawTrailingLength": 0,
          "rawTrailingPrefixBytes": [],
          "rawTrailingSuffixBytes": [],
          "unknownChildCount": 0
        }
        """)

        expect(columnHasPayloadSamples(column)) == true
    }

    func testColumnGateRejectsMissingRawPayloadSamples() throws {
        let column = try decodeColumn(
            completeColumnJSON.replacingOccurrences(
                of: "\"rawPayloadSuffixBytes\": [202, 254],",
                with: ""
            )
        )

        expect(columnHasPayloadSamples(column)) == false
    }

    func testColumnGateRejectsUnknownChildWithoutPayloadSamples() throws {
        let column = try decodeColumn(
            completeColumnJSON.replacingOccurrences(
                of: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [721],
                  "unknownChildPayloadLengths": [4],
                  "unknownChildPayloadPrefixBytes": [[9, 10]],
                  "unknownChildPayloadSuffixBytes": [[11, 12]],
                """,
                with: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [721],
                """
            )
        )

        expect(columnHasPayloadSamples(column)) == false
    }

    func testColumnGateRejectsNestedChildWithoutPayloadSamples() throws {
        let column = try decodeColumn(
            completeColumnJSON.replacingOccurrences(
                of: """
                  "unknownChildChildTagIds": [[720]],
                  "unknownChildChildPayloadLengths": [[3]],
                  "unknownChildChildPayloadPrefixBytes": [[[4, 5]]],
                  "unknownChildChildPayloadSuffixBytes": [[[5, 6]]]
                """,
                with: """
                  "unknownChildChildTagIds": [[720]],
                  "unknownChildChildPayloadLengths": [[3]]
                """
            )
        )

        expect(columnHasPayloadSamples(column)) == false
    }
}

private func decodeColumn(_ json: String) throws -> FixtureColumnExpectations {
    try JSONDecoder().decode(FixtureColumnExpectations.self, from: Data(json.utf8))
}

private let completeColumnJSON = """
{
  "ctrlId": 1668246628,
  "ctrlIdName": "column",
  "propertyRawValue": 0,
  "propertyCount": 1,
  "isSameWidth": true,
  "rawPayloadLength": 6,
  "rawPayloadPrefixBytes": [100, 108, 111, 99],
  "rawPayloadSuffixBytes": [202, 254],
  "rawTrailingLength": 2,
  "rawTrailingPrefixBytes": [202, 254],
  "rawTrailingSuffixBytes": [202, 254],
  "unknownChildCount": 1,
  "unknownChildTagIds": [721],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[9, 10]],
  "unknownChildPayloadSuffixBytes": [[11, 12]],
  "unknownChildChildTagIds": [[720]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[4, 5]]],
  "unknownChildChildPayloadSuffixBytes": [[[5, 6]]]
}
"""
