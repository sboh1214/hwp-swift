@testable import CoreHwp
import Foundation
import XCTest

final class PageNumberPositionManifestTests: XCTestCase {
    func testPageNumberPositionManifestCanAssertUnknownChildPayloadSamples() throws {
        let position = try pageNumberPositionWithUnknownChildren()
        let manifest = try pageNumberPositionUnknownChildFixtureManifest()

        FixtureAssertions.assertPageNumberPositions(
            manifest.expectations.pageNumberPositions ?? [],
            [position]
        )
    }
}

private func pageNumberPositionWithUnknownChildren() throws -> HwpPageNumberPosition {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: pageNumberPositionPayload(rawTrailing: Data([0xCA, 0xFE]))
    )
    let child = HwpRecord(tagId: 0x2BA, level: 2, payload: Data([1, 2, 3, 4]))
    child.children = [
        HwpRecord(tagId: 0x2B9, level: 3, payload: Data([5, 6, 7])),
    ]
    record.children = [child]
    return try HwpPageNumberPosition.load(record)
}

private func pageNumberPositionUnknownChildFixtureManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(pageNumberPositionUnknownJSON.utf8)
    )
}

private let pageNumberPositionUnknownJSON = """
{
  "id": "synthetic-page-number-position-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "pageNumberPositions": [
      {
        "ctrlId": \(HwpOtherCtrlId.pageNumberPosition.rawValue),
        "ctrlIdName": "pageNumberPosition",
        "property": \(UInt32(0x0102_0304)),
        "userSymbol": 0,
        "headDecoration": 45,
        "tailDecoration": 45,
        "unused": 45,
        "unknown": \(UInt32(0xAABB_CCDD)),
        "rawPayloadLength": 22,
        "rawPayloadPrefixBytes": [112, 110, 103, 112, 4, 3, 2, 1],
        "rawPayloadSuffixBytes": [221, 204, 187, 170, 202, 254],
        "rawTrailingLength": 2,
        "rawTrailingPrefixBytes": [202, 254],
        "rawTrailingSuffixBytes": [202, 254],
        "unknownChildCount": 1,
        "unknownChildTagIds": [698],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[1, 2]],
        "unknownChildPayloadSuffixBytes": [[3, 4]],
        "unknownChildChildTagIds": [[697]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[5, 6]]],
        "unknownChildChildPayloadSuffixBytes": [[[6, 7]]]
      }
    ]
  }
}
"""

private func pageNumberPositionPayload(rawTrailing: Data) -> Data {
    var data = Data()
    data.append(littleEndianData(HwpOtherCtrlId.pageNumberPosition.rawValue))
    data.append(littleEndianData(UInt32(0x0102_0304)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(WCHAR(45)))
    data.append(littleEndianData(UInt32(0xAABB_CCDD)))
    data.append(rawTrailing)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
