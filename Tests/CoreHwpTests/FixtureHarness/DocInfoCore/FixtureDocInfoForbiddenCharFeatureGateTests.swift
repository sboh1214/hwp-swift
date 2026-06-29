import Foundation
import Nimble
import XCTest

final class DocInfoForbiddenCharGateTests: XCTestCase {
    func testRawDocInfoFeatureGateRejectsForbiddenCharCountWithoutPayloadSamples() throws {
        let manifest = try decodeForbiddenCharFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-forbidden-char-missing-payload-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-data", "forbidden-char"],
          "expectations": {
            "docInfoRawRecords": {
              "docData": {
                "rawPayloadLength": 4,
                "rawPayloadPrefixBytes": [1, 2],
                "rawPayloadSuffixBytes": [3, 4],
                "forbiddenCharCount": 1,
                "unknownChildCount": 0
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

    func testRawDocInfoFeatureGateAcceptsForbiddenCharPayloadSamples() throws {
        let manifest = try decodeForbiddenCharFeatureGateManifest("""
        {
          "id": "synthetic-doc-info-forbidden-char-payload-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-data", "forbidden-char"],
          "expectations": {
            "docInfoRawRecords": {
              "docData": {
                "rawPayloadLength": 4,
                "rawPayloadPrefixBytes": [1, 2],
                "rawPayloadSuffixBytes": [3, 4],
                "forbiddenCharCount": 1,
                "forbiddenCharPayloadLengths": [4],
                "forbiddenCharPayloadPrefixBytes": [[10, 11]],
                "forbiddenCharPayloadSuffixBytes": [[12, 13]],
                "unknownChildCount": 0
              }
            }
          }
        }
        """)

        guard let docData = manifest.expectations.docInfoRawRecords?.docData else {
            return fail("Expected docData raw record expectations")
        }
        expect(rawDocInfoRecordHasPayloadSample(docData)) == true
    }
}

private func decodeForbiddenCharFeatureGateManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}
