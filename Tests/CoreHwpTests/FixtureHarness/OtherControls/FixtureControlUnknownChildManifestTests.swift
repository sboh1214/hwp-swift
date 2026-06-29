@testable import CoreHwp
import Foundation
import XCTest

final class FixtureControlUnknownChildManifestTests: XCTestCase {
    func testTypedControlManifestsCanAssertUnknownChildPayloadSamples() throws {
        let controls = try typedControlsWithUnknownChildren()
        let manifest = try controlUnknownChildFixtureManifest()

        FixtureAssertions.assertFieldControls(
            manifest.expectations.fieldControls ?? [],
            [controls.field]
        )
        FixtureAssertions.assertOtherControls(
            manifest.expectations.otherControls ?? [],
            [controls.other]
        )
        FixtureAssertions.assertShapeControls(
            manifest.expectations.shapeControls ?? [],
            [controls.shape]
        )
        let genShapeExpectations = manifest.expectations.genShapeObjects ?? []
        FixtureAssertions.assertGenShapeObjectChildren(
            try XCTUnwrap(genShapeExpectations.first),
            controls.genShape
        )
        FixtureAssertions.assertShapeComponents(
            try XCTUnwrap(genShapeExpectations.first?.shapeComponents),
            controls.genShape
        )
    }

    func testOtherControlSamplesCanAssertSpecificOccurrence() throws {
        let manifest = try decodeControlUnknownChildFixtureManifest("""
        {
          "id": "synthetic-other-control-samples",
          "generationTool": "synthetic",
          "hwpVersion": "5.0.1.1",
          "source": "unit-test",
          "features": ["synthetic"],
          "expectations": {
            "otherControlSamples": [
              {
                "ctrlIdName": "bookmark",
                "occurrenceIndex": 1,
                "rawPayloadLength": 5,
                "rawPayloadPrefixBytes": [109, 107, 111, 98, 2],
                "rawPayloadSuffixBytes": [109, 107, 111, 98, 2],
                "rawTrailingLength": 1,
                "rawTrailingPrefixBytes": [2],
                "rawTrailingSuffixBytes": [2],
                "ctrlDataCount": 0,
                "unknownChildCount": 0
              }
            ]
          }
        }
        """)
        let controls = [
            try otherControl(.bookmark, rawTrailing: [1]),
            try otherControl(.bookmark, rawTrailing: [2]),
        ]

        FixtureAssertions.assertOtherControlSamples(
            manifest.expectations.otherControlSamples ?? [],
            controls
        )
    }
}

private func typedControlsWithUnknownChildren() throws -> UnknownChildControls {
    let fieldPayload = concatenatedData(littleEndianData(HwpFieldCtrlId.memo.rawValue), Data([0xCA, 0xFE]))
    let otherPayload = concatenatedData(littleEndianData(HwpOtherCtrlId.bookmark.rawValue), Data([0xBA, 0xAD]))
    let shapePayload = concatenatedData(littleEndianData(HwpCommonCtrlId.equation.rawValue), Data([0xFA, 0xCE]))

    return UnknownChildControls(
        field: try HwpFieldControl.load(
            controlRecord(
                payload: fieldPayload,
                childTagId: 0x2A1,
                childPayload: [1, 2, 3, 4],
                childChildTagId: 0x2A0,
                childChildPayload: [21, 22, 23]
            )
        ),
        other: try HwpOtherControl.load(
            controlRecord(
                payload: otherPayload,
                childTagId: 0x2A2,
                childPayload: [5, 6, 7, 8],
                childChildTagId: 0x2A6,
                childChildPayload: [24, 25, 26]
            )
        ),
        shape: try HwpShapeControl.load(
            controlRecord(
                payload: shapePayload,
                childTagId: 0x2A3,
                childPayload: [9, 10, 11, 12],
                childChildTagId: 0x2A7,
                childChildPayload: [31, 32, 33]
            )
        ),
        genShape: try genShapeObjectWithUnknownChildren()
    )
}

private struct UnknownChildControls {
    let field: HwpFieldControl
    let other: HwpOtherControl
    let shape: HwpShapeControl
    let genShape: HwpGenShapeObject
}

private func genShapeObjectWithUnknownChildren() throws -> HwpGenShapeObject {
    let shapeComponent = HwpShapeComponent(
        rawPayload: Data([0x01]),
        pictureArray: [],
        oleArray: [],
        oleRecords: [],
        chartDataArray: [
            chartDataRawChildWithUnknownChild(),
        ],
        shapeComponentUnknownArray: [
            shapeComponentUnknownRawChildWithUnknownChild(),
        ],
        ctrlDataRecords: [],
        unknownChildren: [
            unknownRecord(
                tagId: 0x2A5,
                level: 3,
                payload: [17, 18, 19, 20],
                childTagId: 0x2A9,
                childPayload: [51, 52, 53]
            ),
        ]
    )
    return HwpGenShapeObject(
        commonCtrlProperty: try commonCtrlProperty(),
        rawPayload: Data(),
        rawTrailing: Data(),
        shapeComponentArray: [shapeComponent],
        ctrlDataRecords: [],
        unknownChildren: [
            unknownRecord(
                tagId: 0x2A4,
                payload: [13, 14, 15, 16],
                childTagId: 0x2A8,
                childPayload: [41, 42, 43]
            ),
        ]
    )
}

private func chartDataRawChildWithUnknownChild() -> HwpShapeComponentChartData {
    HwpShapeComponentChartData(
        rawPayload: Data([0xCA, 0xFE, 0xBA, 0xBE]),
        unknownChildren: [
            unknownRecord(
                tagId: 0x2AB,
                level: 4,
                payload: [71, 72, 73, 74]
            ),
        ]
    )
}

private func shapeComponentUnknownRawChildWithUnknownChild() -> HwpShapeComponentUnknown {
    HwpShapeComponentUnknown(
        rawPayload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
        unknownChildren: [
            unknownRecord(
                tagId: 0x2AA,
                level: 4,
                payload: [61, 62, 63, 64]
            ),
        ]
    )
}

private func controlRecord(
    payload: Data,
    childTagId: UInt32,
    childPayload: [UInt8],
    childChildTagId: UInt32? = nil,
    childChildPayload: [UInt8] = []
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: payload
    )
    let child = HwpRecord(tagId: childTagId, level: 2, payload: Data(childPayload))
    if let childChildTagId {
        child.children = [
            HwpRecord(tagId: childChildTagId, level: 3, payload: Data(childChildPayload)),
        ]
    }
    record.children = [child]
    return record
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

private func otherControl(
    _ ctrlId: HwpOtherCtrlId,
    rawTrailing: [UInt8]
) throws -> HwpOtherControl {
    let payload = concatenatedData(littleEndianData(ctrlId.rawValue), Data(rawTrailing))
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: payload
    )
    return try HwpOtherControl.load(record)
}

private func decodeControlUnknownChildFixtureManifest(_ json: String) throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self, from: Data(json.utf8))
}

private func controlUnknownChildFixtureManifest() throws -> FixtureManifest {
    try decodeControlUnknownChildFixtureManifest(controlUnknownChildManifestJSON)
}

private let controlUnknownChildManifestJSON = """
{
  "id": "synthetic-control-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "fieldControls": [
      {
        "ctrlId": \(HwpFieldCtrlId.memo.rawValue),
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": [101, 109, 37, 37],
        "rawPayloadSuffixBytes": [202, 254],
        "unknownChildCount": 1,
        "unknownChildTagIds": [673],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[1, 2]],
        "unknownChildPayloadSuffixBytes": [[3, 4]],
        "unknownChildChildTagIds": [[672]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[21, 22]]],
        "unknownChildChildPayloadSuffixBytes": [[[22, 23]]]
      }
    ],
    "otherControls": [
      {
        "ctrlId": \(HwpOtherCtrlId.bookmark.rawValue),
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": [109, 107, 111, 98],
        "rawPayloadSuffixBytes": [186, 173],
        "unknownChildCount": 1,
        "unknownChildTagIds": [674],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[5, 6]],
        "unknownChildPayloadSuffixBytes": [[7, 8]],
        "unknownChildChildTagIds": [[678]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[24, 25]]],
        "unknownChildChildPayloadSuffixBytes": [[[25, 26]]]
      }
    ],
    "shapeControls": [
      {
        "ctrlId": \(HwpCommonCtrlId.equation.rawValue),
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": [100, 101, 113, 101],
        "rawPayloadSuffixBytes": [250, 206],
        "unknownChildCount": 1,
        "unknownChildTagIds": [675],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[9, 10]],
        "unknownChildPayloadSuffixBytes": [[11, 12]],
        "unknownChildChildTagIds": [[679]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[31, 32]]],
        "unknownChildChildPayloadSuffixBytes": [[[32, 33]]]
      }
    ],
    "genShapeObjects": [
      {
        "unknownChildCount": 1,
        "unknownChildTagIds": [676],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[13, 14]],
        "unknownChildPayloadSuffixBytes": [[15, 16]],
        "unknownChildChildTagIds": [[680]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[41, 42]]],
        "unknownChildChildPayloadSuffixBytes": [[[42, 43]]],
        "shapeComponents": [
          {
            "rawPayloadLength": 1,
            "rawChildren": [
              {
                "kind": "chartData",
                "count": 1,
                "payloadLengths": [4],
                "payloadPrefixBytes": [[202, 254]],
                "payloadSuffixBytes": [[186, 190]],
                "childCounts": [1],
                "childTagIds": [[683]],
                "childPayloadLengths": [[4]],
                "childPayloadPrefixBytes": [[[71, 72]]],
                "childPayloadSuffixBytes": [[[73, 74]]]
              },
              {
                "kind": "shapeComponentUnknown",
                "count": 1,
                "payloadLengths": [4],
                "payloadPrefixBytes": [[222, 173]],
                "payloadSuffixBytes": [[190, 239]],
                "childCounts": [1],
                "childTagIds": [[682]],
                "childPayloadLengths": [[4]],
                "childPayloadPrefixBytes": [[[61, 62]]],
                "childPayloadSuffixBytes": [[[63, 64]]]
              }
            ],
            "unknownChildCount": 1,
            "unknownChildTagIds": [677],
            "unknownChildPayloadLengths": [4],
            "unknownChildPayloadPrefixBytes": [[17, 18]],
            "unknownChildPayloadSuffixBytes": [[19, 20]],
            "unknownChildChildTagIds": [[681]],
            "unknownChildChildPayloadLengths": [[3]],
            "unknownChildChildPayloadPrefixBytes": [[[51, 52]]],
            "unknownChildChildPayloadSuffixBytes": [[[52, 53]]]
          }
        ]
      }
    ]
  }
}
"""

private func commonCtrlProperty() throws -> HwpCommonCtrlProperty {
    var reader = DataReader(commonCtrlPropertyPayload())
    return try HwpCommonCtrlProperty(&reader)
}

private func commonCtrlPropertyPayload() -> Data {
    var data = littleEndianData(HwpCommonCtrlId.genShapeObject.rawValue)
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(Int16(0)))
    data.append(littleEndianData(Int16(0)))
    data.append(littleEndianData(Int16(0)))
    data.append(littleEndianData(Int16(0)))
    data.append(littleEndianData(UInt32(0)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
