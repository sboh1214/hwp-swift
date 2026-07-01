@testable import CoreHwp
import Foundation
import XCTest

final class SectionDefManifestTests: XCTestCase {
    func testSectionDefManifestCanAssertUnknownChildPayloadSamples() throws {
        let sectionDef = try sectionDefWithUnknownChildren()
        let manifest = try sectionDefUnknownChildFixtureManifest()

        FixtureAssertions.assertSectionDefinitions(
            manifest.expectations.sections ?? [],
            [sectionDef]
        )
    }
}

private func sectionDefWithUnknownChildren() throws -> HwpSectionDef {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: sectionDefManifestPayload()
    )
    let unknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: Data([1, 2, 3, 4]))
    unknownChild.children = [
        HwpRecord(tagId: 0x2FD, level: 3, payload: Data([5, 6, 7])),
    ]
    record.children = sectionDefManifestRequiredChildren() + [unknownChild]
    return try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
}

private func sectionDefUnknownChildFixtureManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(sectionDefUnknownJSON.utf8)
    )
}

private let sectionDefUnknownJSON = """
{
  "id": "synthetic-section-def-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "sections": [
      {
        "propertyRawValue": 4,
        "pageDefPropertyRawValue": 0,
        "footNoteShapePropertyRawValue": 0,
        "endNoteShapePropertyRawValue": 0,
        "pageBorderFillPropertyRawValues": [0, 0, 0],
        "unknownChildCount": 1,
        "unknownChildTagIds": [766],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[1, 2]],
        "unknownChildPayloadSuffixBytes": [[3, 4]],
        "unknownChildChildTagIds": [[765]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[5, 6]]],
        "unknownChildChildPayloadSuffixBytes": [[[6, 7]]]
      }
    ]
  }
}
"""

private func sectionDefManifestRequiredChildren() -> [HwpRecord] {
    [
        sectionDefManifestChild(.pageDef, sectionDefPagePayload()),
        sectionDefManifestChild(.footnoteShape, sectionDefFootnotePayload()),
        sectionDefManifestChild(.footnoteShape, sectionDefFootnotePayload()),
        sectionDefManifestChild(.pageBorderFill, sectionDefBorderPayload()),
        sectionDefManifestChild(.pageBorderFill, sectionDefBorderPayload()),
        sectionDefManifestChild(.pageBorderFill, sectionDefBorderPayload()),
    ]
}

private func sectionDefManifestChild(_ tag: HwpSectionTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

private func sectionDefManifestPayload() -> Data {
    var data = Data()
    data.append(sectionDefManifestLittleEndianData(HwpOtherCtrlId.section.rawValue))
    data.append(sectionDefManifestLittleEndianData(UInt32(0x0000_0004)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    return data
}

private func sectionDefPagePayload() -> Data {
    var data = Data()
    for _ in 0 ..< 9 {
        data.append(sectionDefManifestLittleEndianData(HWPUNIT(0)))
    }
    data.append(sectionDefManifestLittleEndianData(UInt32(0)))
    return data
}

private func sectionDefFootnotePayload() -> Data {
    var data = Data()
    data.append(sectionDefManifestLittleEndianData(UInt32(0)))
    data.append(sectionDefManifestLittleEndianData(WCHAR(0)))
    data.append(sectionDefManifestLittleEndianData(WCHAR(0)))
    data.append(sectionDefManifestLittleEndianData(WCHAR(0)))
    data.append(sectionDefManifestLittleEndianData(UInt16(1)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefManifestLittleEndianData(UInt8(0)))
    data.append(sectionDefManifestLittleEndianData(UInt8(0)))
    data.append(sectionDefManifestLittleEndianData(COLORREF(0)))
    data.append(Data([0, 0]))
    return data
}

private func sectionDefBorderPayload() -> Data {
    var data = Data()
    data.append(sectionDefManifestLittleEndianData(UInt32(0)))
    for _ in 0 ..< 5 {
        data.append(sectionDefManifestLittleEndianData(UInt16(0)))
    }
    return data
}

private func sectionDefManifestLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
