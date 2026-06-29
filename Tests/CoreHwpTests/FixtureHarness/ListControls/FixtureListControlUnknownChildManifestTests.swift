@testable import CoreHwp
import Foundation
import XCTest

final class FixtureListControlUnknownTests: XCTestCase {
    func testListControlManifestsCanAssertUnknownChildPayloadSamples() throws {
        let control = try listControlWithUnknownChildren()
        let manifest = try listControlUnknownChildFixtureManifest()

        FixtureAssertions.assertListControls(
            manifest.expectations.listControls ?? [],
            [(kind: "header", control: control)]
        )
    }
}

private func listControlWithUnknownChildren() throws -> HwpListControl {
    let listHeaderPayload = Data([0, 0, 0, 0, 0, 0, 0, 0, 238, 255])
    let listHeader = try HwpListHeader.load(listHeaderPayload)

    return HwpListControl(
        header: HwpCtrlHeader(
            ctrlId: HwpOtherCtrlId.header.rawValue,
            rawPayload: concatenatedData(
                littleEndianData(HwpOtherCtrlId.header.rawValue),
                Data([171, 205])
            ),
            unknownChildren: []
        ),
        listArray: [
            HwpListControlList(
                header: listHeader,
                headerRawPayload: listHeaderPayload,
                headerUnknownChildren: [
                    unknownRecord(
                        tagId: 0x2B1,
                        level: 3,
                        payload: [1, 2, 3, 4],
                        childTagId: 0x2B0,
                        childPayload: [11, 12, 13]
                    ),
                ],
                paragraphArray: []
            ),
        ],
        unknownChildren: [
            unknownRecord(
                tagId: 0x2B2,
                payload: [5, 6, 7, 8],
                childTagId: 0x2B3,
                childPayload: [15, 16, 17]
            ),
        ]
    )
}

private func unknownRecord(
    tagId: UInt32,
    level: UInt32 = 2,
    payload: [UInt8],
    childTagId: UInt32? = nil,
    childPayload: [UInt8] = []
) -> HwpUnknownRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: Data(payload))
    if let childTagId {
        record.children = [
            HwpRecord(tagId: childTagId, level: level + 1, payload: Data(childPayload)),
        ]
    }
    return HwpUnknownRecord(
        record
    )
}

private func listControlUnknownChildFixtureManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(listControlUnknownChildManifestJSON.utf8)
    )
}

private let listControlUnknownChildManifestJSON = """
{
  "id": "synthetic-list-control-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "listControls": [
      {
        "kind": "header",
        "ctrlId": \(HwpOtherCtrlId.header.rawValue),
        "ctrlIdName": "header",
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": [100, 97, 101, 104],
        "rawPayloadSuffixBytes": [171, 205],
        "listCount": 1,
        "listParagraphCounts": [0],
        "listHeaderRawPayloadLengths": [10],
        "listHeaderRawPayloadPrefixBytes": [[0, 0, 0, 0]],
        "listHeaderRawPayloadSuffixBytes": [[238, 255]],
        "listHeaderRawTrailingLengths": [2],
        "listHeaderRawTrailingPrefixBytes": [[238, 255]],
        "listHeaderRawTrailingSuffixBytes": [[238, 255]],
        "listHeaderUnknownChildCounts": [1],
        "listHeaderUnknownChildTagIds": [[689]],
        "listHeaderUnknownChildPayloadLengths": [[4]],
        "listHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]]],
        "listHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]]],
        "listHeaderNestedChildTagIds": [[[688]]],
        "listHeaderNestedChildPayloadLengths": [[[3]]],
        "listHeaderNestedChildPayloadPrefixBytes": [[[[11, 12]]]],
        "listHeaderNestedChildPayloadSuffixBytes": [[[[12, 13]]]],
        "unknownChildCount": 1,
        "unknownChildTagIds": [690],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[5, 6]],
        "unknownChildPayloadSuffixBytes": [[7, 8]],
        "unknownChildChildTagIds": [[691]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[15, 16]]],
        "unknownChildChildPayloadSuffixBytes": [[[16, 17]]]
      }
    ]
  }
}
"""

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
