import Foundation
import Nimble
import XCTest

final class FixtureDocInfoMemoShapeFeatureGateTests: XCTestCase {
    func testMemoShapeGateRequiresTypedFieldsAndTrailingSamples() throws {
        let missingTypedFields = try decodeMemoShapeFeatureGateManifest(
            memoShapeMissingTypedFieldsJSON
        )
        let missingFixedRaw = try decodeMemoShapeFeatureGateManifest(
            memoShapeJSONRemovingLines(containing: "memoShapeFixedRaw")
        )
        let complete = try decodeMemoShapeFeatureGateManifest(memoShapeCompleteJSON)

        let missingRecord = missingTypedFields.expectations.docInfoRawRecords?
            .memoShapes?.first
        let missingFixedRawRecord = missingFixedRaw.expectations.docInfoRawRecords?
            .memoShapes?.first
        let completeRecord = complete.expectations.docInfoRawRecords?.memoShapes?.first

        expect(missingRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingRecord.map(memoShapeHasTypedFields) ?? true) == false
        expect(missingFixedRawRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(missingFixedRawRecord.map(memoShapeHasTypedFields) ?? true) == false
        expect(completeRecord.map(rawDocInfoRecordHasPayloadSample) ?? false) == true
        expect(completeRecord.map(memoShapeHasTypedFields) ?? false) == true
    }
}

private func decodeMemoShapeFeatureGateManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func memoShapeJSONRemovingLines(containing marker: String) -> String {
    memoShapeCompleteJSON.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { $0.range(of: marker) == nil }
        .joined(separator: "\n")
}

private let memoShapeMissingTypedFieldsJSON = """
{
  "id": "synthetic-memo-shape-missing-typed-fields",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["memo-shape"],
  "expectations": {
    "docInfoRawRecords": {
      "memoShapes": [
        {
          "rawPayloadLength": 22,
          "rawPayloadPrefixBytes": [176, 58, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""

private let memoShapeCompleteJSON = """
{
  "id": "synthetic-memo-shape-typed-fields",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["memo-shape"],
  "expectations": {
    "docInfoRawRecords": {
      "memoShapes": [
        {
          "rawPayloadLength": 22,
          "rawPayloadPrefixBytes": [176, 58, 0, 0],
          "rawPayloadSuffixBytes": [0, 0, 0, 0],
          "memoShapeWidth": 15024,
          "memoShapeLineType": 1,
          "memoShapeLineWidth": 1,
          "memoShapeLineColor": [182, 215, 174],
          "memoShapeFillColor": [240, 255, 233],
          "memoShapeActiveColor": [207, 241, 199],
          "memoShapeFixedRawLength": 18,
          "memoShapeFixedRawPrefixBytes": [176, 58, 0, 0],
          "memoShapeFixedRawSuffixBytes": [207, 241, 199, 0],
          "memoShapeRawTrailingLength": 4,
          "memoShapeRawTrailingPrefixBytes": [0, 0, 0, 0],
          "memoShapeRawTrailingSuffixBytes": [0, 0, 0, 0],
          "unknownChildCount": 0
        }
      ]
    }
  }
}
"""
