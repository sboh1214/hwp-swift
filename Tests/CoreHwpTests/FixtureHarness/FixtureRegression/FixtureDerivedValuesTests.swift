@testable import CoreHwp
import Nimble
import XCTest

final class FixtureDerivedValuesTests: XCTestCase {
    func testAllGenShapeObjectsIncludesNestedTableImageReferences() throws {
        let hwp = try openHwp(#file, "noori")

        let topLevelObjects = FixtureDerivedValues.genShapeObjects(from: hwp)
        let allObjects = FixtureDerivedValues.allGenShapeObjects(from: hwp)
        let binaryDataIds = allObjects
            .flatMap(\.shapeComponentArray)
            .flatMap(\.pictureArray)
            .compactMap(\.binaryDataId)

        expect(topLevelObjects.count) == 1
        expect(FixtureDerivedValues.allParagraphs(from: hwp).count) == 65
        expect(allObjects.count) == 4
        expect(FixtureDerivedValues.allControlCounts(from: hwp)) == [
            "column": 1,
            "genShapeObject": 4,
            "pageNumberPosition": 1,
            "section": 1,
            "table": 5,
        ]
        expect(Set(binaryDataIds)) == Set([1, 2, 3, 4])
    }

    func testAllGenShapeObjectsIncludesOleBinaryDataReferences() throws {
        let hwp = try openHwp(#file, "chart")

        let oleBinaryDataIds = FixtureDerivedValues.allGenShapeObjects(from: hwp)
            .flatMap(\.shapeComponentArray)
            .flatMap(\.oleArray)
            .compactMap(\.binaryDataId)

        expect(oleBinaryDataIds) == [1]
        expect(hwp.binaryDataArray.compactMap(\.streamId)) == [1]
    }

    func testPreservedControlsIncludesNestedUnknownAndNotImplementedTableControls() throws {
        let nestedUnknownHeader = HwpCtrlHeader(
            ctrlId: 0x1122_3344,
            rawPayload: littleEndianData(UInt32(0x1122_3344)) + Data([0xAA, 0xBB]),
            unknownChildren: []
        )
        let nestedNotImplementedHeader = HwpCtrlHeader(
            ctrlId: 0x5566_7788,
            rawPayload: littleEndianData(UInt32(0x5566_7788)) + Data([0xCC]),
            unknownChildren: [
                HwpUnknownRecord(
                    HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xDD]))
                ),
            ]
        )
        var nestedParagraph = HwpParagraph()
        nestedParagraph.ctrlHeaderArray = [
            .notImplemented(nestedNotImplementedHeader),
            .unknown(nestedUnknownHeader),
        ]

        let table = try tableWithNestedParagraph(nestedParagraph)
        var rootParagraph = HwpParagraph()
        rootParagraph.ctrlHeaderArray = [.table(table)]

        var section = HwpSection()
        section.paragraph = [rootParagraph]

        let preservedControls = FixtureDerivedValues.preservedControls(from: [section])

        expect(preservedControls.map(\.kind)) == ["notImplemented", "unknown"]
        expect(preservedControls.map(\.header.ctrlId)) == [0x5566_7788, 0x1122_3344]
        expect(preservedControls.map(\.header.rawPayload.count)) == [5, 6]
        FixtureAssertions.assertUnknownRecordSamples(
            preservedControls.first?.header.unknownChildren ?? [],
            rootLevel: 2,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: [0x2FA],
                payloadLengths: [1],
                payloadPrefixes: [[0xDD]],
                payloadSuffixes: [[0xDD]]
            )
        )
    }

    func testFieldControlsAndCountsIncludeRevisionControls() {
        let control = HwpFieldControl(
            ctrlId: .revisionSign,
            rawTrailing: Data([0xAA]),
            fieldParameterHeaderRawPayload: nil,
            fieldParameter: nil,
            rawPayload: littleEndianData(HwpFieldCtrlId.revisionSign.rawValue) + Data([0xAA]),
            unknownChildren: []
        )
        var paragraph = HwpParagraph()
        paragraph.ctrlHeaderArray = [.revision(control)]

        var section = HwpSection()
        section.paragraph = [paragraph]

        expect(FixtureDerivedValues.fieldControls(from: [section]).map(\.ctrlId)) == [
            .revisionSign,
        ]
        expect(FixtureDerivedValues.controlName(.revision(control))) == "revision"
    }
}

private func tableWithNestedParagraph(_ paragraph: HwpParagraph) throws -> HwpTable {
    var commonReader = DataReader(commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue))
    let commonProperty = try HwpCommonCtrlProperty(&commonReader)
    let tableProperty = try HwpTableProperty.load(
        tablePropertyPayload(rowCount: 1, columnCount: 1),
        HwpVersion(5, 0, 1, 1)
    )
    let cellHeader = try HwpTableCellHeader.load(
        HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 1,
            payload: listHeaderPayload(paragraphCount: 1)
        )
    )

    return HwpTable(
        commonCtrlProperty: commonProperty,
        tableProperty: tableProperty,
        rawPayload: Data(),
        rawTrailing: Data(),
        cellArray: [HwpTableCell(header: cellHeader, paragraphArray: [paragraph])],
        unknownChildren: []
    )
}

private func commonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
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

private func tablePropertyPayload(rowCount: UInt16, columnCount: UInt16) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(rowCount))
    data.append(littleEndianData(columnCount))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(Data(repeating: 0, count: Int(rowCount) * MemoryLayout<UInt16>.size))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    return data
}

private func listHeaderPayload(paragraphCount: Int32) -> Data {
    littleEndianData(paragraphCount) + littleEndianData(UInt32(0))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
