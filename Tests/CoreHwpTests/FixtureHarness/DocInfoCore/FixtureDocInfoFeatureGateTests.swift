// swiftlint:disable file_length
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class FixtureDocInfoFeatureGateTests: XCTestCase {
    func testLayoutCompatibilityFeatureGateRequiresUnknownChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-layout-compatibility-missing-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "layoutCompatibility": {
              "rawPayloadLength": 20,
              "rawPayloadPrefixBytes": [1, 0, 0, 0],
              "rawPayloadSuffixBytes": [5, 0, 0, 0],
              "fixedFieldsRawLength": 20,
              "fixedFieldsRawPrefixBytes": [1, 0, 0, 0],
              "fixedFieldsRawSuffixBytes": [5, 0, 0, 0],
              "unknownChildCount": 1,
              "unknownChildTagIds": [519]
            }
          }
        }
        """)

        guard let layoutCompatibility = manifest.expectations.layoutCompatibility else {
            return fail("Expected layoutCompatibility expectations")
        }
        expect(layoutCompatibilityHasPayloadSample(layoutCompatibility)) == false
    }

    func testLayoutCompatibilityFeatureGateRequiresFixedFieldPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-layout-compatibility-missing-fixed-field-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "layoutCompatibility": {
              "rawPayloadLength": 20,
              "rawPayloadPrefixBytes": [1, 0, 0, 0],
              "rawPayloadSuffixBytes": [5, 0, 0, 0],
              "unknownChildCount": 0
            }
          }
        }
        """)

        guard let layoutCompatibility = manifest.expectations.layoutCompatibility else {
            return fail("Expected layoutCompatibility expectations")
        }
        expect(layoutCompatibilityHasPayloadSample(layoutCompatibility)) == false
    }

    func testRawDocInfoFeatureGateRequiresUnknownChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-raw-record-missing-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-data"],
          "expectations": {
            "docInfoRawRecords": {
              "docData": {
                "rawPayloadLength": 2,
                "rawPayloadPrefixBytes": [1],
                "rawPayloadSuffixBytes": [2],
                "unknownChildCount": 1,
                "unknownChildTagIds": [520]
              }
            }
          }
        }
        """)

        guard let docData = manifest.expectations.docInfoRawRecords?.docData else {
            return fail("Expected docData raw record expectations")
        }
        expect(rawDocInfoRecordHasPayloadSample(docData)) == false
    }

    func testRawDocInfoFeatureGateRequiresNestedUnknownChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-raw-record-missing-nested-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-data"],
          "expectations": {
            "docInfoRawRecords": {
              "docData": {
                "rawPayloadLength": 2,
                "rawPayloadPrefixBytes": [1],
                "rawPayloadSuffixBytes": [2],
                "unknownChildCount": 1,
                "unknownChildTagIds": [520],
                "unknownChildPayloadLengths": [4],
                "unknownChildPayloadPrefixBytes": [[1, 2]],
                "unknownChildPayloadSuffixBytes": [[3, 4]],
                "unknownChildChildPayloadLengths": [[2]]
              }
            }
          }
        }
        """)

        guard let docData = manifest.expectations.docInfoRawRecords?.docData else {
            return fail("Expected docData raw record expectations")
        }
        expect(rawDocInfoRecordHasPayloadSample(docData)) == false
    }

    func testRawDocInfoRecordCountRequiresPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-raw-record-count-only",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-info"],
          "expectations": {
            "docInfoRawRecordCount": 1
          }
        }
        """)

        expect(docInfoRawRecordsHavePayloadSamples(manifest.expectations.docInfoRawRecords)) ==
            false
    }

    func testRawDocInfoRecordCountAcceptsDistributeDocDataPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-distribute-doc-data-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["distribute-doc-data"],
          "expectations": {
            "docInfoRawRecordCount": 1,
            "docInfoRawRecords": {
              "distributeDocData": {
                "rawPayloadLength": 4,
                "rawPayloadPrefixBytes": [16, 17],
                "rawPayloadSuffixBytes": [18, 19],
                "distributeDocDataValues": [319951120],
                "distributeDocDataValuesRawLength": 4,
                "distributeDocDataValuesRawPrefixBytes": [16, 17],
                "distributeDocDataValuesRawSuffixBytes": [18, 19],
                "distributeDocDataRawTrailingLength": 0,
                "distributeDocDataRawTrailingPrefixBytes": [],
                "distributeDocDataRawTrailingSuffixBytes": [],
                "unknownChildCount": 0
              }
            }
          }
        }
        """)

        expect(docInfoRawRecordsHavePayloadSamples(manifest.expectations.docInfoRawRecords)) ==
            true
    }

    func testDocDataGateRequiresValueRawPayloadSamples() throws {
        try assertTypedWordGate(
            missingJSON: docDataMissingValueRawJSON,
            completeJSON: docDataCompleteValueRawJSON,
            record: { $0.expectations.docInfoRawRecords?.docData },
            satisfies: docDataHasTypedWords
        )
    }

    func testDistributeDocDataGateRequiresValueRawPayloadSamples() throws {
        try assertTypedWordGate(
            missingJSON: distributeDocDataMissingValueRawJSON,
            completeJSON: distributeDocDataCompleteValueRawJSON,
            record: { $0.expectations.docInfoRawRecords?.distributeDocData },
            satisfies: distributeDocDataHasTypedWords
        )
    }

    func testRawDocInfoRecordCountAcceptsMemoShapePayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-memo-shape-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["memo-shape"],
          "expectations": {
            "docInfoRawRecordCount": 1,
            "docInfoRawRecords": {
              "memoShapes": [
                {
                  "rawPayloadLength": 2,
                  "rawPayloadPrefixBytes": [1],
                  "rawPayloadSuffixBytes": [2],
                  "unknownChildCount": 0
                }
              ]
            }
          }
        }
        """)

        expect(docInfoRawRecordsHavePayloadSamples(manifest.expectations.docInfoRawRecords)) ==
            true
    }

    func testRawDocInfoRecordCountAcceptsForbiddenCharPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-forbidden-char-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["forbidden-char"],
          "expectations": {
            "docInfoRawRecordCount": 1,
            "docInfoRawRecords": {
              "forbiddenChars": [
                {
                  "rawPayloadLength": 4,
                  "rawPayloadPrefixBytes": [1, 2],
                  "rawPayloadSuffixBytes": [3, 4],
                  "unknownChildCount": 0
                }
              ]
            }
          }
        }
        """)

        expect(docInfoRawRecordsHavePayloadSamples(manifest.expectations.docInfoRawRecords)) ==
            true
    }

    func testTrackChangeAuthorGateRequiresTypedNameAndTrailingSamples() throws {
        let missingTypedName = try decodeFeatureGateManifest(
            trackChangeAuthorMissingTypedNameJSON
        )
        let missingLengthRaw = try decodeFeatureGateManifest(
            jsonRemovingLines(
                containing: ["authorNameLengthRaw"],
                from: trackChangeAuthorCompleteJSON
            )
        )
        let complete = try decodeFeatureGateManifest(trackChangeAuthorCompleteJSON)

        let missingRecord = missingTypedName.expectations.docInfoRawRecords?
            .trackChangeAuthors?.first
        let missingRawRecord = missingLengthRaw.expectations.docInfoRawRecords?
            .trackChangeAuthors?.first
        let completeRecord = complete.expectations.docInfoRawRecords?.trackChangeAuthors?.first

        expect(missingRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingRecord.map(trackChangeAuthorHasTypedName) ?? true) == false
        expect(missingRawRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingRawRecord.map(trackChangeAuthorHasTypedName) ?? true) == false
        expect(completeRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(completeRecord.map(trackChangeAuthorHasTypedName) ?? false) == true
    }

    func testTrackChangeContentGateRequiresTypedTimestampAndRawSamples() throws {
        let missingTimestamp = try decodeFeatureGateManifest(
            contentMissingTimestampJSON
        )
        let missingTimestampRawPayload = try decodeFeatureGateManifest(
            contentMissingTimestampRawPayloadJSON
        )
        let missingKindRawPayload = try decodeFeatureGateManifest(
            jsonRemovingLines(containing: ["trackChangeContentKindRaw"], from: contentCompleteJSON)
        )
        let complete = try decodeFeatureGateManifest(contentCompleteJSON)

        let missingRecord = missingTimestamp.expectations.docInfoRawRecords?
            .trackChangeContents?.first
        let missingRawRecord = missingTimestampRawPayload.expectations.docInfoRawRecords?
            .trackChangeContents?.first
        let missingKindRawRecord = missingKindRawPayload.expectations.docInfoRawRecords?
            .trackChangeContents?.first
        let completeRecord = complete.expectations.docInfoRawRecords?.trackChangeContents?.first

        expect(missingRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingRecord.map(trackChangeContentHasTypedTimestamp) ?? true) == false
        expect(missingRawRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingRawRecord.map(trackChangeContentHasTypedTimestamp) ?? true) == false
        expect(missingKindRawRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingKindRawRecord.map(trackChangeContentHasTypedTimestamp) ?? true) == false
        expect(completeRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(completeRecord.map(trackChangeContentHasTypedTimestamp) ?? false) == true
    }

    func testCompatibleDocumentFeatureGateRequiresUnknownChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-compatible-document-missing-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "compatibleDocument": {
              "targetDocument": 0,
              "targetDocumentRawLength": 4,
              "targetDocumentRawPrefixBytes": [0, 0],
              "targetDocumentRawSuffixBytes": [0, 0],
              "rawPayloadLength": 4,
              "rawPayloadPrefixBytes": [0, 0],
              "rawPayloadSuffixBytes": [0, 0],
              "unknownChildCount": 1,
              "unknownChildTagIds": [521],
              "layoutCompatibility": {
                "rawPayloadLength": 20,
                "rawPayloadPrefixBytes": [1, 0, 0, 0],
                "rawPayloadSuffixBytes": [5, 0, 0, 0],
                "fixedFieldsRawLength": 20,
                "fixedFieldsRawPrefixBytes": [1, 0, 0, 0],
                "fixedFieldsRawSuffixBytes": [5, 0, 0, 0],
                "unknownChildCount": 0
              }
            }
          }
        }
        """)

        guard let compatibleDocument = manifest.expectations.compatibleDocument else {
            return fail("Expected compatibleDocument expectations")
        }
        expect(compatibleDocumentHasPayloadSamples(compatibleDocument)) == false
    }

    func testCompatibleDocumentGateRequiresTargetDocumentPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-compatible-document-missing-target-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "compatibleDocument": {
              "targetDocument": 0,
              "rawPayloadLength": 4,
              "rawPayloadPrefixBytes": [0, 0],
              "rawPayloadSuffixBytes": [0, 0],
              "unknownChildCount": 0
            }
          }
        }
        """)

        guard let compatibleDocument = manifest.expectations.compatibleDocument else {
            return fail("Expected compatibleDocument expectations")
        }
        expect(compatibleDocumentHasPayloadSamples(compatibleDocument)) == false
    }

    func testCompatibleDocumentGateRequiresNestedChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-compatible-document-missing-nested-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "compatibleDocument": {
              "targetDocument": 0,
              "targetDocumentRawLength": 4,
              "targetDocumentRawPrefixBytes": [0, 0],
              "targetDocumentRawSuffixBytes": [0, 0],
              "rawPayloadLength": 4,
              "rawPayloadPrefixBytes": [0, 0],
              "rawPayloadSuffixBytes": [0, 0],
              "unknownChildCount": 1,
              "unknownChildTagIds": [521],
              "unknownChildPayloadLengths": [4],
              "unknownChildPayloadPrefixBytes": [[1, 2]],
              "unknownChildPayloadSuffixBytes": [[3, 4]],
              "unknownChildChildPayloadLengths": [[2]]
            }
          }
        }
        """)

        guard let compatibleDocument = manifest.expectations.compatibleDocument else {
            return fail("Expected compatibleDocument expectations")
        }
        expect(compatibleDocumentHasPayloadSamples(compatibleDocument)) == false
    }

    func testLayoutCompatibilityGateRequiresNestedChildPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-layout-compatibility-missing-nested-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["layout-compatibility"],
          "expectations": {
            "layoutCompatibility": {
              "rawPayloadLength": 20,
              "rawPayloadPrefixBytes": [1, 0, 0, 0],
              "rawPayloadSuffixBytes": [5, 0, 0, 0],
              "fixedFieldsRawLength": 20,
              "fixedFieldsRawPrefixBytes": [1, 0, 0, 0],
              "fixedFieldsRawSuffixBytes": [5, 0, 0, 0],
              "unknownChildCount": 1,
              "unknownChildTagIds": [519],
              "unknownChildPayloadLengths": [4],
              "unknownChildPayloadPrefixBytes": [[1, 2]],
              "unknownChildPayloadSuffixBytes": [[3, 4]],
              "unknownChildChildPayloadLengths": [[2]]
            }
          }
        }
        """)

        guard let layoutCompatibility = manifest.expectations.layoutCompatibility else {
            return fail("Expected layoutCompatibility expectations")
        }
        expect(layoutCompatibilityHasPayloadSample(layoutCompatibility)) == false
    }

    func testTrackChangeRecordGatesDistinguishTopLevelAndCompatibleDocumentRecords() throws {
        let topLevelManifest = try decodeFeatureGateManifest(topLevelTrackChangeJSON)
        let compatibleManifest = try decodeFeatureGateManifest(compatibleTrackChangeJSON)

        expect(topLevelTrackChangeRecordsHavePayloadSamples(topLevelManifest.expectations)) ==
            true
        expect(compatibleTrackChangeRecordsHavePayloadSamples(topLevelManifest.expectations)) ==
            false
        expect(topLevelTrackChangeRecordsHavePayloadSamples(compatibleManifest.expectations)) ==
            false
        expect(compatibleTrackChangeRecordsHavePayloadSamples(compatibleManifest.expectations)) ==
            true
    }

    func testTopLevelTrackChangeRecordGateRequiresPayloadSamples() throws {
        let manifest = try decodeFeatureGateManifest("""
        {
          "id": "synthetic-top-level-track-change-missing-payload-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["top-level-track-change-records"],
          "expectations": {
            "docInfoRawRecords": {
              "trackChanges": [
                {
                  "rawPayloadLength": 4,
                  "unknownChildCount": 0
                }
              ]
            }
          }
        }
        """)
        let missingHeaderRaw = try decodeFeatureGateManifest(
            jsonRemovingLines(containing: ["trackChangeHeaderRaw"], from: topLevelTrackChangeJSON)
        )

        expect(topLevelTrackChangeRecordsHavePayloadSamples(manifest.expectations)) == false
        expect(topLevelTrackChangeRecordsHavePayloadSamples(missingHeaderRaw.expectations)) ==
            false
    }
}

private func decodeFeatureGateManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func assertTypedWordGate(
    missingJSON: String,
    completeJSON: String,
    record: (FixtureManifest) -> FixtureRawRecordExpectations?,
    satisfies: (FixtureRawRecordExpectations) -> Bool
) throws {
    let missingRecord = try record(decodeFeatureGateManifest(missingJSON))
    let completeRecord = try record(decodeFeatureGateManifest(completeJSON))
    let missingHasPayloadSample = missingRecord.map(rawDocInfoRecordHasPayloadSample) ?? false
    let missingSatisfies = missingRecord.map(satisfies) ?? true
    let completeHasPayloadSample = completeRecord.map(rawDocInfoRecordHasPayloadSample) ?? false
    let completeSatisfies = completeRecord.map(satisfies) ?? false

    expect(missingHasPayloadSample) == true
    expect(missingSatisfies) == false
    expect(completeHasPayloadSample) == true
    expect(completeSatisfies) == true
}

private func jsonRemovingLines(containing markers: [String], from json: String) -> String {
    json.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            !markers.contains { marker in
                line.range(of: marker) != nil
            }
        }
        .joined(separator: "\n")
}

private let docDataMissingValueRawJSON = """
{
  "id": "synthetic-doc-info-doc-data-missing-value-raw-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["doc-data"],
  "expectations": {
    "docInfoRawRecords": {
      "docData": {
        "rawPayloadLength": 4,
        "rawPayloadPrefixBytes": [16, 17],
        "rawPayloadSuffixBytes": [18, 19],
        "docDataValues": [319951120],
        "docDataRawTrailingLength": 0,
        "unknownChildCount": 0
      }
    }
  }
}
"""

private let docDataCompleteValueRawJSON = """
{
  "id": "synthetic-doc-info-doc-data-complete-value-raw-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["doc-data"],
  "expectations": {
    "docInfoRawRecords": {
      "docData": {
        "rawPayloadLength": 4,
        "rawPayloadPrefixBytes": [16, 17],
        "rawPayloadSuffixBytes": [18, 19],
        "docDataValues": [319951120],
        "docDataValuesRawLength": 4,
        "docDataValuesRawPrefixBytes": [16, 17],
        "docDataValuesRawSuffixBytes": [18, 19],
        "docDataRawTrailingLength": 0,
        "unknownChildCount": 0
      }
    }
  }
}
"""

private let distributeDocDataMissingValueRawJSON = """
{
  "id": "synthetic-doc-info-distribute-doc-data-missing-value-raw-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["distribute-doc-data"],
  "expectations": {
    "docInfoRawRecords": {
      "distributeDocData": {
        "rawPayloadLength": 4,
        "rawPayloadPrefixBytes": [16, 17],
        "rawPayloadSuffixBytes": [18, 19],
        "distributeDocDataValues": [319951120],
        "distributeDocDataRawTrailingLength": 0,
        "unknownChildCount": 0
      }
    }
  }
}
"""

private let distributeDocDataCompleteValueRawJSON = """
{
  "id": "synthetic-doc-info-distribute-doc-data-complete-value-raw-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["distribute-doc-data"],
  "expectations": {
    "docInfoRawRecords": {
      "distributeDocData": {
        "rawPayloadLength": 4,
        "rawPayloadPrefixBytes": [16, 17],
        "rawPayloadSuffixBytes": [18, 19],
        "distributeDocDataValues": [319951120],
        "distributeDocDataValuesRawLength": 4,
        "distributeDocDataValuesRawPrefixBytes": [16, 17],
        "distributeDocDataValuesRawSuffixBytes": [18, 19],
        "distributeDocDataRawTrailingLength": 0,
        "unknownChildCount": 0
      }
    }
  }
}
"""

private let topLevelTrackChangeJSON = """
{
  "id": "synthetic-top-level-track-change-record-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["top-level-track-change-records"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChanges": [
        {
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [80, 81],
          "rawPayloadSuffixBytes": [82, 83],
          "trackChangeHeaderValue": 1397903696,
          "trackChangeHeaderRawLength": 4,
          "trackChangeHeaderRawPrefixBytes": [80, 81, 82, 83],
          "trackChangeHeaderRawSuffixBytes": [80, 81, 82, 83],
          "trackChangeRawTrailingLength": 0,
          "trackChangeRawTrailingPrefixBytes": [],
          "trackChangeRawTrailingSuffixBytes": [],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let trackChangeAuthorMissingTypedNameJSON = """
{
  "id": "synthetic-track-change-author-missing-typed-name",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-author"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChangeAuthors": [
        {
          "rawPayloadLength": 42,
          "rawPayloadPrefixBytes": [15, 0, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let trackChangeAuthorCompleteJSON = """
{
  "id": "synthetic-track-change-author-typed-name",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-author"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChangeAuthors": [
        {
          "rawPayloadLength": 42,
          "rawPayloadPrefixBytes": [15, 0, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "authorName": "CoreHwp Fixture",
          "authorNameLengthRawLength": 4,
          "authorNameLengthRawPrefixBytes": [15, 0, 0, 0],
          "authorNameLengthRawSuffixBytes": [15, 0, 0, 0],
          "authorNameRawPayloadLength": 30,
          "authorNameRawPayloadPrefixBytes": [67, 0, 111, 0],
          "authorNameRawPayloadSuffixBytes": [114, 0, 101, 0],
          "authorRawTrailingLength": 8,
          "authorRawTrailingPrefixBytes": [1, 0, 0, 0],
          "authorRawTrailingSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let contentMissingTimestampJSON = """
{
  "id": "synthetic-track-change-content-missing-typed-timestamp",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-content"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChangeContents": [
        {
          "rawPayloadLength": 26,
          "rawPayloadPrefixBytes": [17, 0, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let contentCompleteJSON = """
{
  "id": "synthetic-track-change-content-typed-timestamp",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-content"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChangeContents": [
        {
          "rawPayloadLength": 26,
          "rawPayloadPrefixBytes": [17, 0, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "trackChangeContentKind": 17,
          "trackChangeContentKindRawLength": 4,
          "trackChangeContentKindRawPrefixBytes": [17, 0, 0, 0],
          "trackChangeContentKindRawSuffixBytes": [17, 0, 0, 0],
          "trackChangeContentYear": 2026,
          "trackChangeContentMonth": 6,
          "trackChangeContentDay": 15,
          "trackChangeContentHour": 4,
          "trackChangeContentMinute": 30,
          "trackChangeTimestampRawLength": 10,
          "trackChangeTimestampRawPrefixBytes": [234, 7, 6, 0],
          "trackChangeTimestampRawSuffixBytes": [4, 0, 30, 0],
          "trackChangeContentRawTrailingLength": 12,
          "trackChangeContentRawTrailingPrefixBytes": [1, 0, 0, 0],
          "trackChangeContentRawTrailingSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let contentMissingTimestampRawPayloadJSON = """
{
  "id": "synthetic-track-change-content-missing-timestamp-raw-payload",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-content"],
  "expectations": {
    "docInfoRawRecords": {
      "trackChangeContents": [
        {
          "rawPayloadLength": 26,
          "rawPayloadPrefixBytes": [17, 0, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "trackChangeContentKind": 17,
          "trackChangeContentKindRawLength": 4,
          "trackChangeContentKindRawPrefixBytes": [17, 0, 0, 0],
          "trackChangeContentKindRawSuffixBytes": [17, 0, 0, 0],
          "trackChangeContentYear": 2026,
          "trackChangeContentMonth": 6,
          "trackChangeContentDay": 15,
          "trackChangeContentHour": 4,
          "trackChangeContentMinute": 30,
          "trackChangeContentRawTrailingLength": 12,
          "trackChangeContentRawTrailingPrefixBytes": [1, 0, 0, 0],
          "trackChangeContentRawTrailingSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let compatibleTrackChangeJSON = """
{
  "id": "synthetic-compatible-track-change-record-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["compatible-track-change-records"],
  "expectations": {
    "compatibleDocument": {
      "targetDocument": 0,
      "targetDocumentRawLength": 4,
      "targetDocumentRawPrefixBytes": [0, 0],
      "targetDocumentRawSuffixBytes": [0, 0],
      "rawPayloadLength": 4,
      "rawPayloadPrefixBytes": [0, 0],
      "rawPayloadSuffixBytes": [0, 0],
      "unknownChildCount": 0,
      "unknownChildTagIds": [],
      "trackChanges": [
        {
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [80, 81],
          "rawPayloadSuffixBytes": [82, 83],
          "trackChangeHeaderValue": 1397903696,
          "trackChangeHeaderRawLength": 4,
          "trackChangeHeaderRawPrefixBytes": [80, 81, 82, 83],
          "trackChangeHeaderRawSuffixBytes": [80, 81, 82, 83],
          "trackChangeRawTrailingLength": 0,
          "trackChangeRawTrailingPrefixBytes": [],
          "trackChangeRawTrailingSuffixBytes": [],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""
