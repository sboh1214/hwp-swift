import Foundation
import Nimble
import XCTest

final class FixtureTextBodyFeatureGateTests: XCTestCase {
    func testTrackChangesBodyGateAcceptsAlignedInlineControlSamples() throws {
        let manifest = try decodeTextBodyFeatureGateManifest("""
        {
          "id": "synthetic-track-changes-body-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["track-changes"],
          "expectations": {
            "paraTextControlIds": [1936024420, 1668246628],
            "paraTextControlIdNames": ["section", "column"],
            "paraTextControlPayloadLengths": [14, 14],
            "paraTextControlPayloadPrefixBytes": [[100, 99], [100, 108]],
            "paraTextControlPayloadSuffixBytes": [[2, 0], [2, 0]],
            "paraTextControlTrailingLengths": [10, 10],
            "paraTextControlTrailingPrefixBytes": [[0, 0], [0, 0]],
            "paraTextControlTrailingSuffixBytes": [[2, 0], [2, 0]]
          }
        }
        """)

        expect(trackChangesBodyHasPayloadSamples(manifest.expectations)) == true
    }

    func testTrackChangesBodyGateRequiresControlNamesToMatchIds() throws {
        let manifest = try decodeTextBodyFeatureGateManifest("""
        {
          "id": "synthetic-track-changes-body-name-mismatch",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["track-changes"],
          "expectations": {
            "paraTextControlIds": [1936024420, 1668246628],
            "paraTextControlIdNames": ["column", "section"],
            "paraTextControlPayloadLengths": [14, 14],
            "paraTextControlPayloadPrefixBytes": [[100, 99], [100, 108]],
            "paraTextControlPayloadSuffixBytes": [[2, 0], [2, 0]],
            "paraTextControlTrailingLengths": [10, 10],
            "paraTextControlTrailingPrefixBytes": [[0, 0], [0, 0]],
            "paraTextControlTrailingSuffixBytes": [[2, 0], [2, 0]]
          }
        }
        """)

        expect(trackChangesBodyHasPayloadSamples(manifest.expectations)) == false
    }

    func testTrackChangesBodyGateRequiresPayloadSamplesToMatchControlIds() throws {
        let manifest = try decodeTextBodyFeatureGateManifest("""
        {
          "id": "synthetic-track-changes-body-payload-sample-mismatch",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["track-changes"],
          "expectations": {
            "paraTextControlIds": [1936024420, 1668246628],
            "paraTextControlIdNames": ["section", "column"],
            "paraTextControlPayloadLengths": [14, 14],
            "paraTextControlPayloadPrefixBytes": [[100, 99]],
            "paraTextControlPayloadSuffixBytes": [[2, 0], [2, 0]],
            "paraTextControlTrailingLengths": [10, 10],
            "paraTextControlTrailingPrefixBytes": [[0, 0], [0, 0]],
            "paraTextControlTrailingSuffixBytes": [[2, 0], [2, 0]]
          }
        }
        """)

        expect(trackChangesBodyHasPayloadSamples(manifest.expectations)) == false
    }

    func testTrackChangesBodyGateRequiresTrailingSamplesToMatchControlIds() throws {
        let manifest = try decodeTextBodyFeatureGateManifest("""
        {
          "id": "synthetic-track-changes-body-trailing-sample-mismatch",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["track-changes"],
          "expectations": {
            "paraTextControlIds": [1936024420, 1668246628],
            "paraTextControlIdNames": ["section", "column"],
            "paraTextControlPayloadLengths": [14, 14],
            "paraTextControlPayloadPrefixBytes": [[100, 99], [100, 108]],
            "paraTextControlPayloadSuffixBytes": [[2, 0], [2, 0]],
            "paraTextControlTrailingLengths": [10],
            "paraTextControlTrailingPrefixBytes": [[0, 0], [0, 0]],
            "paraTextControlTrailingSuffixBytes": [[2, 0], [2, 0]]
          }
        }
        """)

        expect(trackChangesBodyHasPayloadSamples(manifest.expectations)) == false
    }
}

private func decodeTextBodyFeatureGateManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}
