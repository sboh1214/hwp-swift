@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixturePreservedControlManifestTests: XCTestCase {
    func testPreservedControlManifestCanAssertPayloadSamples() throws {
        let manifest = try decodePreservedControlFixtureManifest("""
        {
          "id": "synthetic-preserved-control-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "synthetic",
          "features": ["unknown-control"],
          "expectations": {
            "preservedControls": [
              {
                "kind": "notImplemented",
                "ctrlId": 305419896,
                "rawPayloadLength": 6,
                "rawPayloadPrefixBytes": [120, 86, 52, 18],
                "rawPayloadSuffixBytes": [202, 254],
                "unknownChildCount": 1,
                "unknownChildTagIds": [767],
                "unknownChildPayloadLengths": [4],
                "unknownChildPayloadPrefixBytes": [[222, 173]],
                "unknownChildPayloadSuffixBytes": [[190, 239]],
                "unknownChildChildTagIds": [[765]],
                "unknownChildChildPayloadLengths": [[3]],
                "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
                "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
              }
            ]
          }
        }
        """)
        let unknownChildRecord = HwpRecord(
            tagId: 0x2FF,
            level: 2,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        unknownChildRecord.children = [
            HwpRecord(tagId: 0x2FD, level: 3, payload: Data([1, 2, 3])),
        ]
        let header = HwpCtrlHeader(
            ctrlId: 0x1234_5678,
            rawPayload: preservedControlLittleEndianData(UInt32(0x1234_5678))
                + Data([0xCA, 0xFE]),
            unknownChildren: [
                HwpUnknownRecord(unknownChildRecord),
            ]
        )
        let controls: [PreservedControl] = [("notImplemented", header)]

        FixtureAssertions.assertPreservedControls(
            manifest.expectations.preservedControls ?? [],
            controls
        )
    }

    func testPreservedControlFeatureGateRejectsUnknownChildWithoutPayloadSamples() throws {
        let manifest = try decodePreservedControlFixtureManifest("""
        {
          "id": "synthetic-preserved-control-missing-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "synthetic",
          "features": ["unknown-control"],
          "expectations": {
            "preservedControls": [
              {
                "kind": "notImplemented",
                "ctrlId": 305419896,
                "rawPayloadLength": 6,
                "rawPayloadPrefixBytes": [120, 86, 52, 18],
                "rawPayloadSuffixBytes": [202, 254],
                "unknownChildCount": 1,
                "unknownChildTagIds": [767]
              }
            ]
          }
        }
        """)

        expect(manifest.expectations.preservedControls?.first.map(
            preservedControlHasPayloadSamples
        ) ?? true) == false
    }

    func testPreservedControlFeatureGateAcceptsNestedUnknownChildPayloadSamples() throws {
        let manifest = try decodePreservedControlFixtureManifest("""
        {
          "id": "synthetic-preserved-control-nested-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "synthetic",
          "features": ["unknown-control"],
          "expectations": {
            "preservedControls": [
              {
                "kind": "notImplemented",
                "ctrlId": 305419896,
                "rawPayloadLength": 6,
                "rawPayloadPrefixBytes": [120, 86, 52, 18],
                "rawPayloadSuffixBytes": [202, 254],
                "unknownChildCount": 1,
                "unknownChildTagIds": [767],
                "unknownChildPayloadLengths": [4],
                "unknownChildPayloadPrefixBytes": [[222, 173]],
                "unknownChildPayloadSuffixBytes": [[190, 239]],
                "unknownChildChildTagIds": [[765]],
                "unknownChildChildPayloadLengths": [[3]],
                "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
                "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
              }
            ]
          }
        }
        """)

        expect(manifest.expectations.preservedControls?.first.map(
            preservedControlHasPayloadSamples
        ) ?? false) == true
    }

    func testPreservedControlSamplesCanAssertSpecificOccurrence() throws {
        let manifest = try decodePreservedControlFixtureManifest("""
        {
          "id": "synthetic-preserved-control-sample-occurrence",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "synthetic",
          "features": ["unknown-control"],
          "expectations": {
            "preservedControlSamples": [
              {
                "kind": "unknown",
                "ctrlId": 305419896,
                "occurrenceIndex": 1,
                "rawPayloadLength": 6,
                "rawPayloadPrefixBytes": [120, 86, 52, 18],
                "rawPayloadSuffixBytes": [202, 254],
                "unknownChildCount": 1,
                "unknownChildTagIds": [767],
                "unknownChildPayloadLengths": [4],
                "unknownChildPayloadPrefixBytes": [[222, 173]],
                "unknownChildPayloadSuffixBytes": [[190, 239]]
              }
            ]
          }
        }
        """)
        let controls: [PreservedControl] = [
            ("unknown", preservedHeader(ctrlId: 0x1234_5678, trailing: [0xAA])),
            (
                "unknown",
                preservedHeader(
                    ctrlId: 0x1234_5678,
                    trailing: [0xCA, 0xFE],
                    unknownChildPayload: [0xDE, 0xAD, 0xBE, 0xEF]
                )
            ),
        ]

        FixtureAssertions.assertPreservedControlSamples(
            manifest.expectations.preservedControlSamples ?? [],
            controls
        )
    }
}

private func decodePreservedControlFixtureManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func preservedControlLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func preservedHeader(
    ctrlId: UInt32,
    trailing: [UInt8],
    unknownChildPayload: [UInt8] = []
) -> HwpCtrlHeader {
    var children = [HwpUnknownRecord]()
    if !unknownChildPayload.isEmpty {
        let child = HwpRecord(tagId: 0x2FF, level: 2, payload: Data(unknownChildPayload))
        children = [HwpUnknownRecord(child)]
    }

    return HwpCtrlHeader(
        ctrlId: ctrlId,
        rawPayload: preservedControlLittleEndianData(ctrlId) + Data(trailing),
        unknownChildren: children
    )
}
