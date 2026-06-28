@testable import CoreHwp
import Foundation
import XCTest

final class FixtureObjectUnknownTests: XCTestCase {
    func testObjectControlManifestsCanAssertUnknownChildPayloadSamples() throws {
        let controls = try objectControlsWithUnknownChildren()
        let manifest = try objectUnknownChildFixtureManifest()

        FixtureAssertions.assertHyperlinks(
            manifest.expectations.hyperlinks ?? [],
            [controls.hyperlink]
        )
        FixtureAssertions.assertColumns(
            manifest.expectations.columns ?? [],
            [controls.column]
        )
        FixtureAssertions.assertTables(
            manifest.expectations.tables ?? [],
            [controls.table]
        )
    }
}

private func objectControlsWithUnknownChildren() throws -> ObjectUnknownControls {
    ObjectUnknownControls(
        hyperlink: hyperlinkWithUnknownChildren(),
        column: columnWithUnknownChildren(),
        table: try tableWithUnknownChildren()
    )
}

private struct ObjectUnknownControls {
    let hyperlink: HwpHyperlink
    let column: HwpColumn
    let table: HwpTable
}

private func hyperlinkWithUnknownChildren() -> HwpHyperlink {
    HwpHyperlink(
        ctrlId: HwpFieldCtrlId.hyperLink.rawValue,
        property: 0,
        unknownPrefix: 0,
        urlLength: 4,
        urlLengthRawPayload: Data([0x04, 0x00]),
        url: "docs",
        urlRawPayload: Data([100, 0, 111, 0, 99, 0, 115, 0]),
        rawTrailing: Data([222, 173]),
        rawPayload: littleEndianData(HwpFieldCtrlId.hyperLink.rawValue) + Data([222, 173]),
        unknownChildren: [
            unknownRecord(
                tagId: 0x2E1,
                payload: [13, 14, 15, 16],
                childTagId: 0x2E0,
                childPayload: [1, 2, 3]
            ),
        ]
    )
}

private func columnWithUnknownChildren() -> HwpColumn {
    HwpColumn(
        otherCtrlId: .column,
        property: HwpColumnProperty(),
        spacing: 0,
        widthArray: nil,
        property2: 0,
        dividerType: 0,
        dividerThickness: 0,
        dividerColor: HwpColor(0, 0, 0),
        unknown: Data([202, 254]),
        rawPayload: littleEndianData(HwpOtherCtrlId.column.rawValue) + Data([202, 254]),
        rawTrailing: Data([202, 254]),
        rawTrailingWords: [0xFECA],
        unknownChildren: [
            unknownRecord(
                tagId: 0x2D1,
                payload: [9, 10, 11, 12],
                childTagId: 0x2D0,
                childPayload: [4, 5, 6]
            ),
        ]
    )
}

private func tableWithUnknownChildren() throws -> HwpTable {
    let cellHeader = HwpTableCellHeader(
        paragraphCount: 0,
        property: 0,
        rawTrailing: Data([170]),
        rawPayload: Data([0, 0, 0, 0, 0, 0, 0, 0, 170]),
        unknownChildren: [
            unknownRecord(
                tagId: 0x2C1,
                level: 3,
                payload: [1, 2, 3, 4],
                childTagId: 0x2C0,
                childPayload: [21, 22, 23]
            ),
        ]
    )
    let commonCtrlProperty = try commonCtrlProperty(ctrlId: HwpCommonCtrlId.table.rawValue)
    return HwpTable(
        commonCtrlProperty: commonCtrlProperty,
        tableProperty: tableProperty(),
        rawPayload: commonCtrlProperty.rawPayload + Data([170, 187]),
        rawTrailing: Data([170, 187]),
        cellArray: [HwpTableCell(header: cellHeader, paragraphArray: [])],
        unknownChildren: [
            unknownRecord(
                tagId: 0x2C2,
                payload: [5, 6, 7, 8],
                childTagId: 0x2C4,
                childPayload: [31, 32, 33]
            ),
        ]
    )
}

private func tableProperty() -> HwpTableProperty {
    HwpTableProperty(
        property: 0,
        rowCount: 1,
        columnCount: 1,
        cellSpacing: 0,
        leftInnerMargin: 0,
        rightInnerMargin: 0,
        topInnerMargin: 0,
        bottomInnerMargin: 0,
        rowSize: [0, 0],
        borderFillId: 0,
        validZoneInfoSize: 0,
        zonePropertyArray: [],
        rawPayload: Data([9, 8, 7, 6]),
        rawTrailing: Data([6])
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

private func objectUnknownChildFixtureManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(
        FixtureManifest.self,
        from: Data(objectUnknownChildManifestJSON.utf8)
    )
}

private let tableControlPrefixBytes = Array(littleEndianData(HwpCommonCtrlId.table.rawValue))

private let objectUnknownChildManifestJSON = """
{
  "id": "synthetic-object-control-unknown-children",
  "generationTool": "synthetic",
  "hwpVersion": "5.0.1.1",
  "source": "unit-test",
  "features": ["synthetic"],
  "expectations": {
    "hyperlinks": [
      {
        "url": "docs",
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": \(Array(littleEndianData(HwpFieldCtrlId.hyperLink.rawValue))),
        "rawPayloadSuffixBytes": [222, 173],
        "rawTrailingLength": 2,
        "rawTrailingPrefixBytes": [222, 173],
        "rawTrailingSuffixBytes": [222, 173],
        "unknownChildCount": 1,
        "unknownChildTagIds": [737],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[13, 14]],
        "unknownChildPayloadSuffixBytes": [[15, 16]],
        "unknownChildChildTagIds": [[736]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[1, 2]]],
        "unknownChildChildPayloadSuffixBytes": [[[2, 3]]]
      }
    ],
    "columns": [
      {
        "propertyRawValue": 0,
        "propertyCount": 1,
        "isSameWidth": true,
        "rawPayloadLength": 6,
        "rawPayloadPrefixBytes": \(Array(littleEndianData(HwpOtherCtrlId.column.rawValue))),
        "rawPayloadSuffixBytes": [202, 254],
        "rawTrailingLength": 2,
        "rawTrailingPrefixBytes": [202, 254],
        "rawTrailingSuffixBytes": [202, 254],
        "unknownChildCount": 1,
        "unknownChildTagIds": [721],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[9, 10]],
        "unknownChildPayloadSuffixBytes": [[11, 12]],
        "unknownChildChildTagIds": [[720]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[4, 5]]],
        "unknownChildChildPayloadSuffixBytes": [[[5, 6]]]
      }
    ],
    "tables": [
      {
        "rowCount": 1,
        "columnCount": 1,
        "commonCtrlPropertyRawPayloadLength": 46,
        "commonCtrlPropertyRawPayloadPrefixBytes": \(tableControlPrefixBytes),
        "commonCtrlPropertyRawPayloadSuffixBytes": [0, 0],
        "rawPayloadLength": 48,
        "rawTrailingLength": 2,
        "rawTrailingPrefixBytes": [170, 187],
        "rawTrailingSuffixBytes": [170, 187],
        "tablePropertyRawPayloadLength": 4,
        "tablePropertyRawPayloadPrefixBytes": [9, 8],
        "tablePropertyRawPayloadSuffixBytes": [7, 6],
        "tablePropertyRawTrailingLength": 1,
        "tablePropertyRawTrailingPrefixBytes": [6],
        "tablePropertyRawTrailingSuffixBytes": [6],
        "cellCount": 1,
        "paragraphCount": 0,
        "cellParagraphCounts": [0],
        "cellHeaderRawPayloadLengths": [9],
        "cellHeaderRawPayloadPrefixBytes": [[0, 0, 0, 0]],
        "cellHeaderRawPayloadSuffixBytes": [[170]],
        "cellHeaderRawTrailingLengths": [1],
        "cellHeaderRawTrailingPrefixBytes": [[170]],
        "cellHeaderRawTrailingSuffixBytes": [[170]],
        "cellHeaderUnknownChildCounts": [1],
        "cellHeaderUnknownChildTagIds": [[705]],
        "cellHeaderUnknownChildPayloadLengths": [[4]],
        "cellHeaderUnknownChildPayloadPrefixBytes": [[[1, 2]]],
        "cellHeaderUnknownChildPayloadSuffixBytes": [[[3, 4]]],
        "cellHeaderNestedChildTagIds": [[[704]]],
        "cellHeaderNestedChildPayloadLengths": [[[3]]],
        "cellHeaderNestedChildPayloadPrefixBytes": [[[[21, 22]]]],
        "cellHeaderNestedChildPayloadSuffixBytes": [[[[22, 23]]]],
        "unknownChildCount": 1,
        "unknownChildTagIds": [706],
        "unknownChildPayloadLengths": [4],
        "unknownChildPayloadPrefixBytes": [[5, 6]],
        "unknownChildPayloadSuffixBytes": [[7, 8]],
        "unknownChildChildTagIds": [[708]],
        "unknownChildChildPayloadLengths": [[3]],
        "unknownChildChildPayloadPrefixBytes": [[[31, 32]]],
        "unknownChildChildPayloadSuffixBytes": [[[32, 33]]]
      }
    ]
  }
}
"""

private func commonCtrlProperty(ctrlId: UInt32) throws -> HwpCommonCtrlProperty {
    var reader = DataReader(commonCtrlPropertyPayload(ctrlId: ctrlId))
    return try HwpCommonCtrlProperty(&reader)
}

private func commonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = littleEndianData(ctrlId)
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(WORD(0)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
