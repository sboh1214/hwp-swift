import Foundation
import Nimble
import XCTest

final class FieldControlFeatureGateTests: XCTestCase {
    func testFieldControlGateAcceptsCompletePayloadSamples() throws {
        let control = try decodeFieldControl(completeFieldControlJSON)

        expect(fieldControlHasPayloadSamples(control)) == true
    }

    func testFieldControlGateAcceptsZeroUnknownChildrenWithoutSampleArrays() throws {
        let control = try decodeFieldControl("""
        {
          "ctrlId": 628452971,
          "ctrlIdName": "unknown",
          "isRevisionField": false,
          "rawPayloadLength": 99,
          "rawPayloadPrefixBytes": [107, 110, 117, 37],
          "rawPayloadSuffixBytes": [1, 0, 0, 0],
          "rawTrailingLength": 95,
          "rawTrailingPrefixBytes": [1, 128, 0, 0],
          "rawTrailingSuffixBytes": [1, 0, 0, 0],
          "unknownChildCount": 0
        }
        """)

        expect(fieldControlHasPayloadSamples(control)) == true
    }

    func testFieldControlGateRejectsMissingTypedId() throws {
        let control = try decodeFieldControl(
            completeFieldControlJSON.replacingOccurrences(
                of: "\"ctrlIdName\": \"unknown\",",
                with: ""
            )
        )

        expect(fieldControlHasPayloadSamples(control)) == false
    }

    func testFieldControlGateRejectsMissingRevisionFlag() throws {
        let control = try decodeFieldControl(
            completeFieldControlJSON.replacingOccurrences(
                of: "  \"isRevisionField\": false,\n",
                with: ""
            )
        )

        expect(fieldControlHasPayloadSamples(control)) == false
    }

    func testFieldControlGateRejectsUnknownChildWithoutPayloadSamples() throws {
        let control = try decodeFieldControl(
            completeFieldControlJSON.replacingOccurrences(
                of: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [810],
                  "unknownChildPayloadLengths": [4],
                  "unknownChildPayloadPrefixBytes": [[21, 22]],
                  "unknownChildPayloadSuffixBytes": [[23, 24]],
                """,
                with: """
                  "unknownChildCount": 1,
                  "unknownChildTagIds": [810],
                """
            )
        )

        expect(fieldControlHasPayloadSamples(control)) == false
    }

    func testFieldControlGateRejectsNestedChildWithoutPayloadSamples() throws {
        let control = try decodeFieldControl(
            completeFieldControlJSON.replacingOccurrences(
                of: """
                  "unknownChildChildTagIds": [[811]],
                  "unknownChildChildPayloadLengths": [[3]],
                  "unknownChildChildPayloadPrefixBytes": [[[31, 32]]],
                  "unknownChildChildPayloadSuffixBytes": [[[32, 33]]]
                """,
                with: """
                  "unknownChildChildTagIds": [[811]],
                  "unknownChildChildPayloadLengths": [[3]]
                """
            )
        )

        expect(fieldControlHasPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateAcceptsTypedParameterPayloadSamples() throws {
        let control = try decodeFieldControl(completeMemoFieldControlJSON)

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == true
    }

    func testMemoFieldControlGateRejectsMissingParameterTrailingPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"fieldParameterRawTrailingPrefixBytes\": [170],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsMissingParameterHeaderRawPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"fieldParameterHeaderRawPrefixBytes\": [1, 128],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsMissingParameterPayloadPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"fieldParameterRawPayloadPrefixBytes\": [77, 0],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsMissingParameterLengthRawPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"fieldParameterLengthRawPrefixBytes\": [24, 0],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsMissingMemoParameterPayloadPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"rawPayloadPrefixBytes\": [77, 0],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsMissingMemoParameterTrailingPrefix() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"rawTrailingPrefixBytes\": [170],",
                with: ""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }

    func testMemoFieldControlGateRejectsNonMemoSemanticKind() throws {
        let control = try decodeFieldControl(
            completeMemoFieldControlJSON.replacingOccurrences(
                of: "\"semanticKind\": \"memo\"",
                with: "\"semanticKind\": \"field\""
            )
        )

        expect(memoFieldControlHasSemanticPayloadSamples(control)) == false
    }
}

private func decodeFieldControl(_ json: String) throws -> FixtureFieldControlExpectations {
    try JSONDecoder().decode(FixtureFieldControlExpectations.self, from: Data(json.utf8))
}

private let completeFieldControlJSON = """
{
  "ctrlId": 628452971,
  "ctrlIdName": "unknown",
  "semanticKind": "memo",
  "isMemoField": true,
  "isRevisionField": false,
  "rawPayloadLength": 99,
  "rawPayloadPrefixBytes": [107, 110, 117, 37],
  "rawPayloadSuffixBytes": [1, 0, 0, 0],
  "rawTrailingLength": 95,
  "rawTrailingPrefixBytes": [1, 128, 0, 0],
  "rawTrailingSuffixBytes": [1, 0, 0, 0],
  "unknownChildCount": 1,
  "unknownChildTagIds": [810],
  "unknownChildPayloadLengths": [4],
  "unknownChildPayloadPrefixBytes": [[21, 22]],
  "unknownChildPayloadSuffixBytes": [[23, 24]],
  "unknownChildChildTagIds": [[811]],
  "unknownChildChildPayloadLengths": [[3]],
  "unknownChildChildPayloadPrefixBytes": [[[31, 32]]],
  "unknownChildChildPayloadSuffixBytes": [[[32, 33]]]
}
"""

private let completeMemoFieldControlJSON = """
{
  "ctrlId": 628452971,
  "ctrlIdName": "unknown",
  "semanticKind": "memo",
  "isMemoField": true,
  "isRevisionField": false,
  "properties": 32769,
  "propertyInitialState": false,
  "extraProperties": 0,
  "commandCharacterCount": 24,
  "command": "MEMO/1/2/3/4/writer/body",
  "commandLengthRawLength": 2,
  "commandLengthRawPrefixBytes": [24, 0],
  "commandLengthRawSuffixBytes": [24, 0],
  "commandRawPayloadLength": 48,
  "commandRawPayloadPrefixBytes": [77, 0],
  "commandRawPayloadSuffixBytes": [121, 0],
  "commandRawTrailingLength": 8,
  "commandRawTrailingPrefixBytes": [204],
  "commandRawTrailingSuffixBytes": [1, 0, 0, 0],
  "fieldId": 2864434397,
  "memoIndex": 1,
  "fieldParameter": "MEMO/1/2/3/4/writer/body",
  "fieldParameterHeaderRawLength": 4,
  "fieldParameterHeaderRawPrefixBytes": [1, 128],
  "fieldParameterHeaderRawSuffixBytes": [0, 0],
  "fieldParameterCharacterCount": 24,
  "fieldParameterLengthRawLength": 2,
  "fieldParameterLengthRawPrefixBytes": [24, 0],
  "fieldParameterLengthRawSuffixBytes": [24, 0],
  "fieldParameterRawPayloadLength": 48,
  "fieldParameterRawPayloadPrefixBytes": [77, 0],
  "fieldParameterRawPayloadSuffixBytes": [121, 0],
  "fieldParameterRawTrailingLength": 2,
  "fieldParameterRawTrailingPrefixBytes": [170],
  "fieldParameterRawTrailingSuffixBytes": [187],
  "memoParameter": {
    "rawValue": "MEMO/1/2/3/4/writer/body",
    "rawPayloadLength": 48,
    "rawPayloadPrefixBytes": [77, 0],
    "rawPayloadSuffixBytes": [121, 0],
    "marker": "MEMO",
    "components": ["MEMO", "1", "2", "3", "4", "writer", "body"],
    "fields": ["1", "2", "3", "4", "writer", "body"],
    "author": "writer",
    "rawTrailingLength": 2,
    "rawTrailingPrefixBytes": [170],
    "rawTrailingSuffixBytes": [187]
  },
  "rawPayloadLength": 64,
  "rawPayloadPrefixBytes": [107, 110, 117, 37],
  "rawPayloadSuffixBytes": [170, 187],
  "rawTrailingLength": 60,
  "rawTrailingPrefixBytes": [1, 128, 0, 0],
  "rawTrailingSuffixBytes": [170, 187],
  "unknownChildCount": 0
}
"""
