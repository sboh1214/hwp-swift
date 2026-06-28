import Foundation
import Nimble
import XCTest

final class HyperlinkFeatureGateTests: XCTestCase {
    func testHyperlinkGateAcceptsCompletePayloadSamples() throws {
        let hyperlink = try decodeHyperlink(completeHyperlinkJSON)

        expect(hyperlinkHasPayloadSamples(hyperlink)) == true
    }

    func testHyperlinkGateRejectsMissingURLPayloadSamples() throws {
        let hyperlink = try decodeHyperlink(
            completeHyperlinkJSON.replacingOccurrences(
                of: "\"urlRawPayloadSuffixBytes\": [46, 0, 111, 0],",
                with: ""
            )
        )

        expect(hyperlinkHasPayloadSamples(hyperlink)) == false
    }

    func testHyperlinkGateRejectsMissingURLLengthPayloadSamples() throws {
        let hyperlink = try decodeHyperlink(
            completeHyperlinkJSON.replacingOccurrences(
                of: "\"urlLengthRawPayloadSuffixBytes\": [19, 0],",
                with: ""
            )
        )

        expect(hyperlinkHasPayloadSamples(hyperlink)) == false
    }

    func testHyperlinkGateRejectsUnknownChildWithoutPayloadSamples() throws {
        let hyperlink = try decodeHyperlink(
            completeHyperlinkJSON.replacingOccurrences(
                of: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [737],
                  "unknownChildPayloadLengths": [4],
                  "unknownChildPayloadPrefixBytes": [[13, 14]],
                  "unknownChildPayloadSuffixBytes": [[15, 16]],
                """,
                with: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [737],
                """
            )
        )

        expect(hyperlinkHasPayloadSamples(hyperlink)) == false
    }

    func testHyperlinkGateRejectsNestedChildWithoutPayloadSamples() throws {
        let hyperlink = try decodeHyperlink(
            completeHyperlinkJSON.replacingOccurrences(
                of: """
                  "unknownChildChildTagIds": [[736]],
                  "unknownChildChildPayloadLengths": [[3]],
                  "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
                  "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
                """,
                with: """
                  "unknownChildChildTagIds": [[736]],
                  "unknownChildChildPayloadLengths": [[3]]
                """
            )
        )

        expect(hyperlinkHasPayloadSamples(hyperlink)) == false
    }
}

private func decodeHyperlink(_ json: String) throws -> FixtureHyperlinkExpectations {
    try JSONDecoder().decode(FixtureHyperlinkExpectations.self, from: Data(json.utf8))
}

private let completeHyperlinkJSON = """
{
  "ctrlId": 627600491,
  "ctrlIdName": "hyperLink",
  "url": "https://example.org",
  "urlLengthRawPayloadLength": 2,
  "urlLengthRawPayloadPrefixBytes": [19, 0],
  "urlLengthRawPayloadSuffixBytes": [19, 0],
  "urlRawPayloadLength": 38,
  "urlRawPayloadPrefixBytes": [104, 0, 116, 0],
  "urlRawPayloadSuffixBytes": [46, 0, 111, 0],
  "rawPayloadLength": 48,
  "rawPayloadPrefixBytes": [107, 108, 104, 37],
  "rawPayloadSuffixBytes": [222, 173],
  "rawTrailingLength": 2,
  "rawTrailingPrefixBytes": [222, 173],
  "rawTrailingSuffixBytes": [222, 173],
  "unknownChildCount": 1,
  "unknownChildTagIds": [737],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[13, 14]],
  "unknownChildPayloadSuffixBytes": [[15, 16]],
  "unknownChildChildTagIds": [[736]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
  "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
}
"""
