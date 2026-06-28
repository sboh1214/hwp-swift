@testable import CoreHwp
import Foundation
import XCTest

final class FixtureSectionUnknownRecordManifestTests: XCTestCase {
    func testSectionManifestCanAssertUnknownRecordPayloadSamples() throws {
        let manifest = try decodeSectionFixtureManifest("""
        {
          "id": "synthetic-section-unknown-record-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "synthetic",
          "features": ["unknown-section-record"],
          "expectations": {
            "sectionUnknownRecordCount": 1,
            "sectionUnknownRecordTagIds": [766],
            "sectionUnknownRecordPayloadLengths": [4],
            "sectionUnknownRecordPayloadPrefixBytes": [[202, 254]],
            "sectionUnknownRecordPayloadSuffixBytes": [[186, 190]],
            "sectionUnknownChildTagIds": [[765]],
            "sectionUnknownChildPayloadLengths": [[3]],
            "sectionUnknownChildPayloadPrefixBytes": [[[170, 187]]],
            "sectionUnknownChildPayloadSuffixBytes": [[[187, 204]]]
          }
        }
        """)
        let section = try HwpSection.load(
            syntheticSectionData(unknownPayload: Data([0xCA, 0xFE, 0xBA, 0xBE])),
            HwpVersion(5, 0, 1, 1)
        )

        FixtureAssertions.assertSectionUnknownRecords(manifest.expectations, [section])
    }
}

private func decodeSectionFixtureManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func syntheticSectionData(unknownPayload: Data) -> Data {
    var data = sectionRecordData(tagId: 0x2FE, level: 0, payload: unknownPayload)
    data.append(sectionRecordData(tagId: 0x2FD, level: 1, payload: Data([0xAA, 0xBB, 0xCC])))
    data.append(sectionRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: sectionParagraphHeaderPayload()
    ))
    data.append(sectionRecordData(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: Data()
    ))
    data.append(sectionRecordData(
        tagId: HwpSectionTag.paraLineSeg.rawValue,
        level: 1,
        payload: Data()
    ))
    return data
}

private func sectionParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(sectionLittleEndianData(UInt32(0x8000_0000)))
    data.append(sectionLittleEndianData(UInt32(0)))
    data.append(sectionLittleEndianData(UInt16(0)))
    data.append(sectionLittleEndianData(UInt8(0)))
    data.append(sectionLittleEndianData(UInt8(0)))
    data.append(sectionLittleEndianData(UInt16(0)))
    data.append(sectionLittleEndianData(UInt16(0)))
    data.append(sectionLittleEndianData(UInt16(0)))
    data.append(sectionLittleEndianData(UInt32(1)))
    return data
}

private func sectionRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = sectionLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func sectionLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
