@testable import CoreHwp
import Foundation
import XCTest

final class ParagraphUnknownChildManifestTests: XCTestCase {
    func testParagraphManifestCanAssertUnknownChildPayloadSamples() throws {
        let manifest = try decodeParagraphFixtureManifest("""
        {
          "id": "synthetic-paragraph-unknown-child-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.3.2",
          "source": "synthetic",
          "features": ["paragraph-text"],
          "expectations": {
            "paragraphUnknownChildCount": 1,
            "paragraphUnknownChildTagIds": [764],
            "paragraphUnknownChildPayloadLengths": [4],
            "paragraphUnknownChildPayloadPrefixBytes": [[202, 254]],
            "paragraphUnknownChildPayloadSuffixBytes": [[186, 190]],
            "paragraphUnknownNestedTagIds": [[763]],
            "paragraphUnknownNestedPayloadLengths": [[3]],
            "paragraphUnknownNestedPayloadPrefixBytes": [[[170, 187]]],
            "paragraphUnknownNestedPayloadSuffixBytes": [[[187, 204]]]
          }
        }
        """)
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: paragraphManifestDocInfoData(),
            sectionDataArray: [paragraphManifestSectionData()]
        )

        FixtureAssertions.assertParaTextPayloads(manifest.expectations, hwp)
    }
}

private func decodeParagraphFixtureManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func paragraphManifestDocInfoData() -> Data {
    concatenatedData(
        paragraphManifestRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: paragraphManifestDocumentPropertiesPayload()
        ),
        paragraphManifestRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: paragraphManifestIdMappingsPayload()
        )
    )
}

private func paragraphManifestSectionData() -> Data {
    var data = paragraphManifestRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: paragraphManifestParaHeaderPayload()
    )
    data.append(paragraphManifestRecordData(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: paragraphManifestParaCharShapePayload()
    ))
    data.append(paragraphManifestRecordData(
        tagId: 0x2FC,
        level: 1,
        payload: Data([0xCA, 0xFE, 0xBA, 0xBE])
    ))
    data.append(paragraphManifestRecordData(
        tagId: 0x2FB,
        level: 2,
        payload: Data([0xAA, 0xBB, 0xCC])
    ))
    return data
}

private func paragraphManifestDocumentPropertiesPayload() -> Data {
    concatenatedData(paragraphManifestLittleEndianData(UInt16(1)), Data(repeating: 0, count: 24))
}

private func paragraphManifestIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(paragraphManifestLittleEndianData(count))
    }
}

private func paragraphManifestParaHeaderPayload() -> Data {
    concatenatedData(
        paragraphManifestLittleEndianData(UInt32(0x8000_0000)),
        paragraphManifestLittleEndianData(UInt32(0)),
        paragraphManifestLittleEndianData(UInt16(0)),
        Data([0, 0]),
        paragraphManifestLittleEndianData(UInt16(1)),
        paragraphManifestLittleEndianData(UInt16(0)),
        paragraphManifestLittleEndianData(UInt16(0)),
        paragraphManifestLittleEndianData(UInt32(0)),
        paragraphManifestLittleEndianData(UInt16(0))
    )
}

private func paragraphManifestParaCharShapePayload() -> Data {
    concatenatedData(
        paragraphManifestLittleEndianData(UInt32(0)),
        paragraphManifestLittleEndianData(UInt32(0))
    )
}

private func paragraphManifestRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = paragraphManifestLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func paragraphManifestLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
