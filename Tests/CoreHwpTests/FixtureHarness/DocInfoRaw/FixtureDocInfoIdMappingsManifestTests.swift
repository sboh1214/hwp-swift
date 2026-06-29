@testable import CoreHwp
import Foundation
import XCTest

final class DocInfoIdMappingsManifestTests: XCTestCase {
    func testIdMappingsManifestCanAssertUnknownChildPayloadSamples() throws {
        let mappings = try idMappingsWithUnknownChildren()
        let manifest = try idMappingsUnknownChildFixtureManifest()

        FixtureAssertions.assertDocInfoIdMappings(
            try XCTUnwrap(manifest.expectations.docInfoIdMappings),
            mappings
        )
    }
}

private func idMappingsWithUnknownChildren() throws -> HwpIdMappings {
    let record = HwpRecord(
        tagId: HwpDocInfoTag.idMappings.rawValue,
        level: 0,
        payload: idMappingsCountPayload()
    )
    let child = HwpRecord(tagId: 0x2BC, level: 1, payload: Data([1, 2, 3, 4]))
    child.children = [
        HwpRecord(tagId: 0x2BB, level: 2, payload: Data([5, 6, 7])),
    ]
    record.children = [child]
    return try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
}

private func idMappingsUnknownChildFixtureManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(idMappingsUnknownJSON.utf8)
    )
}

private let idMappingsUnknownJSON = """
{
  "id": "synthetic-id-mappings-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "docInfoIdMappings": {
      "binDataCount": 0,
      "faceNameKoreanCount": 0,
      "faceNameEnglishCount": 0,
      "faceNameChineseCount": 0,
      "faceNameJapaneseCount": 0,
      "faceNameEtcCount": 0,
      "faceNameSymbolCount": 0,
      "faceNameUserCount": 0,
      "borderFillCount": 0,
      "charShapeCount": 0,
      "tabDefCount": 0,
      "numberingCount": 0,
      "bulletCount": 0,
      "paraShapeCount": 0,
      "styleCount": 0,
      "unknownChildCount": 1,
      "unknownChildTagIds": [700],
      "unknownChildPayloadLengths": [4],
      "unknownChildPayloadPrefixBytes": [[1, 2]],
      "unknownChildPayloadSuffixBytes": [[3, 4]],
      "unknownChildChildTagIds": [[699]],
      "unknownChildChildPayloadLengths": [[3]],
      "unknownChildChildPayloadPrefixBytes": [[[5, 6]]],
      "unknownChildChildPayloadSuffixBytes": [[[6, 7]]]
    }
  }
}
"""

private func idMappingsCountPayload() -> Data {
    Array(repeating: Int32(0), count: 15).reduce(into: Data()) { data, count in
        data.append(littleEndianData(count))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
