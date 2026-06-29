@testable import CoreHwp
import Foundation
import XCTest

final class CompatibleDocumentManifestTests: XCTestCase {
    func testCompatibleDocumentManifestCanAssertTrackChangePayloadSamples() throws {
        let manifest = try compatibleManifest(compatibleTrackChangeJSON)
        let docInfo = try HwpDocInfo.load(
            compatibleDocumentData(
                trackChangePayload: Data([0x50, 0x51, 0x52, 0x53]),
                trackChangeUnknownChildPayload: Data([0x60, 0x61, 0x62]),
                trackChangeUnknownGrandchildPayload: Data([0x63, 0x64])
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertCompatibleDocument(manifest.expectations, docInfo)
    }

    func testCompatibleDocumentManifestCanAssertLayoutCompatibilityUnknownChildSamples() throws {
        let manifest = try compatibleManifest(compatibleLayoutJSON)
        let docInfo = try HwpDocInfo.load(
            compatibleDocumentData(
                layoutCompatibilityPayload: compatibleLayoutPayload(),
                layoutUnknownChildPayload: Data([0x70, 0x71, 0x72, 0x73]),
                layoutUnknownGrandchildPayload: Data([0x74, 0x75])
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertCompatibleDocument(manifest.expectations, docInfo)
    }

    func testDocInfoManifestCanAssertTopLevelLayoutCompatibilityUnknownChildSamples() throws {
        let manifest = try compatibleManifest(topLevelLayoutJSON)
        let docInfo = try HwpDocInfo.load(
            topLevelLayoutCompatibilityData(
                layoutCompatibilityPayload: compatibleLayoutPayload(),
                layoutUnknownChildPayload: Data([0x80, 0x81, 0x82, 0x83]),
                layoutUnknownGrandchildPayload: Data([0x84, 0x85])
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertLayoutCompatibility(manifest.expectations, docInfo)
    }
}

private func compatibleManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private let compatibleTrackChangeJSON = """
{
  "id": "synthetic-compatible-document-track-change-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["track-change-records", "compatible-track-change-records"],
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
          "trackChangeRawTrailingLength": 0,
          "trackChangeRawTrailingPrefixBytes": [],
          "trackChangeRawTrailingSuffixBytes": [],
          "unknownChildCount": 1,
          "unknownChildTagIds": [516],
          "unknownChildPayloadLengths": [3],
          "unknownChildPayloadPrefixBytes": [[96, 97]],
          "unknownChildPayloadSuffixBytes": [[98]],
          "unknownChildChildTagIds": [[532]],
          "unknownChildChildPayloadLengths": [[2]],
          "unknownChildChildPayloadPrefixBytes": [[[99]]],
          "unknownChildChildPayloadSuffixBytes": [[[100]]]
        }
      ]
    }
  }
}
"""

private let compatibleLayoutJSON = """
{
  "id": "synthetic-compatible-document-layout-compatibility-samples",
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
      "unknownChildCount": 0,
      "unknownChildTagIds": [],
      "layoutCompatibility": {
        "char": 1,
        "paragraph": 2,
        "section": 3,
        "object": 4,
        "field": 5,
        "rawPayloadLength": 20,
        "rawPayloadPrefixBytes": [1, 0, 0, 0, 2, 0, 0, 0],
        "rawPayloadSuffixBytes": [4, 0, 0, 0, 5, 0, 0, 0],
        "fixedFieldsRawLength": 20,
        "fixedFieldsRawPrefixBytes": [1, 0, 0, 0, 2, 0, 0, 0],
        "fixedFieldsRawSuffixBytes": [4, 0, 0, 0, 5, 0, 0, 0],
        "unknownChildCount": 1,
        "unknownChildTagIds": [517],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[112, 113]],
        "unknownChildPayloadSuffixBytes": [[114, 115]],
        "unknownChildChildTagIds": [[533]],
        "unknownChildChildPayloadLengths": [[2]],
        "unknownChildChildPayloadPrefixBytes": [[[116]]],
        "unknownChildChildPayloadSuffixBytes": [[[117]]]
      }
    }
  }
}
"""

private let topLevelLayoutJSON = """
{
  "id": "synthetic-doc-info-top-level-layout-compatibility-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["layout-compatibility"],
  "expectations": {
    "layoutCompatibility": {
      "char": 1,
      "paragraph": 2,
      "section": 3,
      "object": 4,
      "field": 5,
      "rawPayloadLength": 20,
      "rawPayloadPrefixBytes": [1, 0, 0, 0, 2, 0, 0, 0],
      "rawPayloadSuffixBytes": [4, 0, 0, 0, 5, 0, 0, 0],
      "fixedFieldsRawLength": 20,
      "fixedFieldsRawPrefixBytes": [1, 0, 0, 0, 2, 0, 0, 0],
      "fixedFieldsRawSuffixBytes": [4, 0, 0, 0, 5, 0, 0, 0],
      "unknownChildCount": 1,
      "unknownChildTagIds": [518],
      "unknownChildPayloadLengths": [4],
      "unknownChildPayloadPrefixBytes": [[128, 129]],
      "unknownChildPayloadSuffixBytes": [[130, 131]],
      "unknownChildChildTagIds": [[534]],
      "unknownChildChildPayloadLengths": [[2]],
      "unknownChildChildPayloadPrefixBytes": [[[132]]],
      "unknownChildChildPayloadSuffixBytes": [[[133]]]
    }
  }
}
"""

private func topLevelLayoutCompatibilityData(
    layoutCompatibilityPayload: Data,
    layoutUnknownChildPayload: Data,
    layoutUnknownGrandchildPayload: Data? = nil
) -> Data {
    var data = compatibleDocInfoPrefix()
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
        level: 0,
        payload: layoutCompatibilityPayload
    ))
    data.append(compatibleRecordData(
        tagId: 0x206,
        level: 1,
        payload: layoutUnknownChildPayload
    ))
    if let layoutUnknownGrandchildPayload {
        data.append(compatibleRecordData(
            tagId: 0x216,
            level: 2,
            payload: layoutUnknownGrandchildPayload
        ))
    }
    return data
}

private func compatibleDocumentData(
    trackChangePayload: Data,
    trackChangeUnknownChildPayload: Data,
    trackChangeUnknownGrandchildPayload: Data? = nil
) -> Data {
    var data = compatibleDocumentPrefix()
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.trackChange.rawValue,
        level: 1,
        payload: trackChangePayload
    ))
    data.append(compatibleRecordData(
        tagId: 0x204,
        level: 2,
        payload: trackChangeUnknownChildPayload
    ))
    if let trackChangeUnknownGrandchildPayload {
        data.append(compatibleRecordData(
            tagId: 0x214,
            level: 3,
            payload: trackChangeUnknownGrandchildPayload
        ))
    }
    return data
}

private func compatibleDocumentData(
    layoutCompatibilityPayload: Data,
    layoutUnknownChildPayload: Data,
    layoutUnknownGrandchildPayload: Data? = nil
) -> Data {
    var data = compatibleDocumentPrefix()
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
        level: 1,
        payload: layoutCompatibilityPayload
    ))
    data.append(compatibleRecordData(
        tagId: 0x205,
        level: 2,
        payload: layoutUnknownChildPayload
    ))
    if let layoutUnknownGrandchildPayload {
        data.append(compatibleRecordData(
            tagId: 0x215,
            level: 3,
            payload: layoutUnknownGrandchildPayload
        ))
    }
    return data
}

private func compatibleDocumentPrefix() -> Data {
    var data = compatibleDocInfoPrefix()
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.compatibleDocument.rawValue,
        level: 0,
        payload: compatibleLittleEndianData(UInt32(0))
    ))
    return data
}

private func compatibleDocInfoPrefix() -> Data {
    var data = Data()
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: compatibleDocPropertiesPayload()
    ))
    data.append(compatibleRecordData(
        tagId: HwpDocInfoTag.idMappings.rawValue,
        level: 0,
        payload: compatibleIdMappingsPayload()
    ))
    return data
}

private func compatibleLayoutPayload() -> Data {
    [
        UInt32(1),
        UInt32(2),
        UInt32(3),
        UInt32(4),
        UInt32(5),
    ].reduce(into: Data()) { data, value in
        data.append(compatibleLittleEndianData(value))
    }
}

private func compatibleDocPropertiesPayload() -> Data {
    concatenatedData(compatibleLittleEndianData(UInt16(1)), Data(repeating: 0, count: 24))
}

private func compatibleIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(compatibleLittleEndianData(count))
    }
}

private func compatibleRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = compatibleLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func compatibleLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
