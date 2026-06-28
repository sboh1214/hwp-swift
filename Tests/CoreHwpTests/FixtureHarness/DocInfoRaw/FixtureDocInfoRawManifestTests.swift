@testable import CoreHwp
import Foundation
import XCTest

final class FixtureDocInfoRawManifestTests: XCTestCase {
    func testDocInfoManifestCanAssertUnknownRecordPayloadSamples() throws {
        let manifest = try decodeFixtureManifest("""
        {
          "id": "synthetic-doc-info-unknown-record-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-info"],
          "expectations": {
            "docInfoUnknownRecordCount": 1,
            "docInfoUnknownRecordTagIds": [750],
            "docInfoUnknownRecordPayloadLengths": [4],
            "docInfoUnknownRecordPayloadPrefixBytes": [[222, 173]],
            "docInfoUnknownRecordPayloadSuffixBytes": [[190, 239]],
            "docInfoUnknownChildTagIds": [[749]],
            "docInfoUnknownChildPayloadLengths": [[3]],
            "docInfoUnknownChildPayloadPrefixBytes": [[[202, 254]]],
            "docInfoUnknownChildPayloadSuffixBytes": [[[254, 186]]]
          }
        }
        """)
        let docInfo = try HwpDocInfo.load(
            syntheticDocInfoData(
                docDataPayload: Data(),
                docDataUnknownChildPayload: Data(),
                unknownRecordPayload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                unknownRecordChildPayload: Data([0xCA, 0xFE, 0xBA])
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertDocInfo(manifest.expectations, docInfo)
    }

    func testDocInfoRawRecordManifestCanAssertUnknownChildPayloadSamples() throws {
        let manifest = try decodeFixtureManifest("""
        {
          "id": "synthetic-doc-info-raw-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["doc-info"],
          "expectations": {
            "docInfoRawRecords": {
              "docData": {
                "rawPayloadLength": 2,
                "rawPayloadPrefixBytes": [1],
                "rawPayloadSuffixBytes": [2],
                "unknownChildCount": 1,
                "unknownChildTagIds": [513],
                "unknownChildPayloadLengths": [4],
                "unknownChildPayloadPrefixBytes": [[170, 187]],
                "unknownChildPayloadSuffixBytes": [[204, 221]],
                "unknownChildChildTagIds": [[512]],
                "unknownChildChildPayloadLengths": [[3]],
                "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
                "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
              }
            }
          }
        }
        """)
        let docInfo = try HwpDocInfo.load(
            syntheticDocInfoData(
                docDataPayload: Data([0x01, 0x02]),
                docDataUnknownChildPayload: Data([0xAA, 0xBB, 0xCC, 0xDD]),
                docDataUnknownGrandchildPayload: Data([1, 2, 3]),
                unknownRecordPayload: nil
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertDocInfoRawRecords(manifest.expectations, docInfo)
    }

    func testDocInfoRawRecordManifestCanAssertDistributeAndTrackChangeSamples() throws {
        let manifest = try distributeAndTrackChangeManifest()
        let docInfo = try HwpDocInfo.load(
            syntheticDocInfoData(
                docDataPayload: Data(),
                docDataUnknownChildPayload: Data(),
                unknownRecordPayload: nil,
                distributeDocDataPayload: Data([0x10, 0x11, 0x12, 0x13]),
                distributeDocDataUnknownChildPayload: Data([0x20, 0x21]),
                distributeGrandchildPayload: Data([0x22, 0x23, 0x24]),
                trackChangePayload: Data([0x30, 0x31, 0x32]),
                trackChangeUnknownChildPayload: Data([0x40, 0x41, 0x42]),
                trackChangeGrandchildPayload: Data([0x43, 0x44]),
                forbiddenCharPayload: Data([0x50, 0x51, 0x52, 0x53]),
                forbiddenCharUnknownChildPayload: Data([0x60, 0x61]),
                forbiddenCharGrandchildPayload: Data([0x62, 0x63, 0x64])
            ),
            HwpVersion(5, 0, 3, 2)
        )

        FixtureAssertions.assertDocInfoRawRecords(manifest.expectations, docInfo)
    }
}

private func decodeFixtureManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func distributeAndTrackChangeManifest() throws -> FixtureManifest {
    try decodeFixtureManifest(distributeAndTrackChangeManifestJSON)
}

private func syntheticDocInfoData(
    docDataPayload: Data,
    docDataUnknownChildPayload: Data,
    docDataUnknownGrandchildPayload: Data? = nil,
    unknownRecordPayload: Data?,
    unknownRecordChildPayload: Data? = nil,
    distributeDocDataPayload: Data? = nil,
    distributeDocDataUnknownChildPayload: Data? = nil,
    distributeGrandchildPayload: Data? = nil,
    trackChangePayload: Data? = nil,
    trackChangeUnknownChildPayload: Data? = nil,
    trackChangeGrandchildPayload: Data? = nil,
    forbiddenCharPayload: Data? = nil,
    forbiddenCharUnknownChildPayload: Data? = nil,
    forbiddenCharGrandchildPayload: Data? = nil
) -> Data {
    var data = Data()
    appendSyntheticDocInfoRequiredRecords(
        to: &data,
        docDataPayload: docDataPayload,
        docDataUnknownChildPayload: docDataUnknownChildPayload,
        docDataUnknownGrandchildPayload: docDataUnknownGrandchildPayload
    )
    appendSyntheticDocInfoOptionalRecords(
        to: &data,
        records: SyntheticDocInfoOptionalRecords(
            distributeDocDataPayload: distributeDocDataPayload,
            distributeDocDataUnknownChildPayload: distributeDocDataUnknownChildPayload,
            distributeGrandchildPayload: distributeGrandchildPayload,
            trackChangePayload: trackChangePayload,
            trackChangeUnknownChildPayload: trackChangeUnknownChildPayload,
            trackChangeGrandchildPayload: trackChangeGrandchildPayload,
            forbiddenCharPayload: forbiddenCharPayload,
            forbiddenCharUnknownChildPayload: forbiddenCharUnknownChildPayload,
            forbiddenCharGrandchildPayload: forbiddenCharGrandchildPayload,
            unknownRecordPayload: unknownRecordPayload,
            unknownRecordChildPayload: unknownRecordChildPayload
        )
    )
    return data
}

private struct SyntheticDocInfoOptionalRecords {
    let distributeDocDataPayload: Data?
    let distributeDocDataUnknownChildPayload: Data?
    let distributeGrandchildPayload: Data?
    let trackChangePayload: Data?
    let trackChangeUnknownChildPayload: Data?
    let trackChangeGrandchildPayload: Data?
    let forbiddenCharPayload: Data?
    let forbiddenCharUnknownChildPayload: Data?
    let forbiddenCharGrandchildPayload: Data?
    let unknownRecordPayload: Data?
    let unknownRecordChildPayload: Data?
}

private func appendSyntheticDocInfoRequiredRecords(
    to data: inout Data,
    docDataPayload: Data,
    docDataUnknownChildPayload: Data,
    docDataUnknownGrandchildPayload: Data?
) {
    appendFixtureRecord(
        to: &data,
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        payload: fixtureDocumentPropertiesPayload()
    )
    appendFixtureRecord(
        to: &data,
        tagId: HwpDocInfoTag.idMappings.rawValue,
        payload: fixtureIdMappingsPayload()
    )
    appendFixtureRecord(
        to: &data,
        tagId: HwpDocInfoTag.docData.rawValue,
        payload: docDataPayload,
        childTagId: 0x201,
        childPayload: docDataUnknownChildPayload,
        childChildTagId: 0x200,
        childChildPayload: docDataUnknownGrandchildPayload
    )
}

private func appendSyntheticDocInfoOptionalRecords(
    to data: inout Data,
    records: SyntheticDocInfoOptionalRecords
) {
    if let distributeDocDataPayload = records.distributeDocDataPayload {
        appendFixtureRecord(
            to: &data,
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            payload: distributeDocDataPayload,
            childTagId: 0x202,
            childPayload: records.distributeDocDataUnknownChildPayload,
            childChildTagId: 0x212,
            childChildPayload: records.distributeGrandchildPayload
        )
    }
    if let trackChangePayload = records.trackChangePayload {
        appendFixtureRecord(
            to: &data,
            tagId: HwpDocInfoTag.trackChange.rawValue,
            payload: trackChangePayload,
            childTagId: 0x203,
            childPayload: records.trackChangeUnknownChildPayload,
            childChildTagId: 0x213,
            childChildPayload: records.trackChangeGrandchildPayload
        )
    }
    if let forbiddenCharPayload = records.forbiddenCharPayload {
        appendFixtureRecord(
            to: &data,
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            payload: forbiddenCharPayload,
            childTagId: 0x204,
            childPayload: records.forbiddenCharUnknownChildPayload,
            childChildTagId: 0x214,
            childChildPayload: records.forbiddenCharGrandchildPayload
        )
    }
    if let unknownRecordPayload = records.unknownRecordPayload {
        appendFixtureRecord(
            to: &data,
            tagId: 0x2EE,
            payload: unknownRecordPayload,
            childTagId: 0x2ED,
            childPayload: records.unknownRecordChildPayload
        )
    }
}

private let distributeAndTrackChangeManifestJSON = """
{
  "id": "synthetic-doc-info-distribute-track-change-samples",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.3.2",
  "source": "synthetic",
  "features": ["doc-info"],
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
        "distributeDocDataRawTrailingPrefixBytes": [],
        "distributeDocDataRawTrailingSuffixBytes": [],
        "unknownChildCount": 1,
        "unknownChildTagIds": [514],
        "unknownChildPayloadLengths": [2],
        "unknownChildPayloadPrefixBytes": [[32]],
        "unknownChildPayloadSuffixBytes": [[33]],
        "unknownChildChildTagIds": [[530]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[34, 35]]],
        "unknownChildChildPayloadSuffixBytes": [[[36]]]
      },
      "trackChanges": [
        {
          "rawPayloadLength": 3,
          "rawPayloadPrefixBytes": [48],
          "rawPayloadSuffixBytes": [49, 50],
          "unknownChildCount": 1,
          "unknownChildTagIds": [515],
          "unknownChildPayloadLengths": [3],
          "unknownChildPayloadPrefixBytes": [[64, 65]],
          "unknownChildPayloadSuffixBytes": [[66]],
          "unknownChildChildTagIds": [[531]],
          "unknownChildChildPayloadLengths": [[2]],
          "unknownChildChildPayloadPrefixBytes": [[[67]]],
          "unknownChildChildPayloadSuffixBytes": [[[68]]]
        }
      ],
      "forbiddenChars": [
        {
          "rawPayloadLength": 4,
          "rawPayloadPrefixBytes": [80, 81],
          "rawPayloadSuffixBytes": [82, 83],
          "unknownChildCount": 1,
          "unknownChildTagIds": [516],
          "unknownChildPayloadLengths": [2],
          "unknownChildPayloadPrefixBytes": [[96]],
          "unknownChildPayloadSuffixBytes": [[97]],
          "unknownChildChildTagIds": [[532]],
          "unknownChildChildPayloadLengths": [[3]],
          "unknownChildChildPayloadPrefixBytes": [[[98]]],
          "unknownChildChildPayloadSuffixBytes": [[[99, 100]]]
        }
      ]
    }
  }
}
"""

private func appendFixtureRecord(
    to data: inout Data,
    tagId: UInt32,
    payload: Data,
    childTagId: UInt32? = nil,
    childPayload: Data? = nil,
    childChildTagId: UInt32? = nil,
    childChildPayload: Data? = nil
) {
    data.append(fixtureRecordData(tagId: tagId, level: 0, payload: payload))
    guard let childTagId, let childPayload, !childPayload.isEmpty else {
        return
    }
    data.append(fixtureRecordData(tagId: childTagId, level: 1, payload: childPayload))
    guard let childChildTagId, let childChildPayload, !childChildPayload.isEmpty else {
        return
    }
    data.append(fixtureRecordData(tagId: childChildTagId, level: 2, payload: childChildPayload))
}

private func fixtureDocumentPropertiesPayload() -> Data {
    fixtureLittleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func fixtureIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(fixtureLittleEndianData(count))
    }
}

private func fixtureRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = fixtureLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func fixtureLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
