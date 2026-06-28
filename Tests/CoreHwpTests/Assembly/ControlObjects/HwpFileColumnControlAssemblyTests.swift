@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileColumnControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesColumnThroughCodableRoundTrip() throws {
        let streams = try columnAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedColumnControl(
            baseSectionData: try XCTUnwrap(streams.sectionDataArray.first)
        )
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0] = injected.sectionData

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectColumnControl(in: hwp, match: injected)
        expectColumnControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedColumnAsOtherControl() throws {
        let streams = try columnAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMalformedColumnControl(
            baseSectionData: try XCTUnwrap(streams.sectionDataArray.first)
        )
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0] = injected.sectionData

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectMalformedColumnControl(in: hwp, match: injected)
        expectMalformedColumnControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct ColumnAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedColumnControl {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let childPayload: Data
    let grandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xCA, 0xFE])
        payload = columnControlPayload(rawTrailing: rawTrailing)
        childPayload = Data([0xC1, 0xC2])
        grandchildPayload = Data([0xC3])
        sectionData = baseSectionData
            + columnRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            )
            + columnRecordData(tagId: 0x2D1, level: 2, payload: childPayload)
            + columnRecordData(tagId: 0x2D2, level: 3, payload: grandchildPayload)
    }
}

private struct InjectedMalformedColumnControl {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let childPayload: Data
    let grandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xAA])
        payload = columnLittleEndianData(HwpOtherCtrlId.column.rawValue) + rawTrailing
        childPayload = Data([0xD1, 0xD2])
        grandchildPayload = Data([0xD3])
        sectionData = baseSectionData
            + columnRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            )
            + columnRecordData(tagId: 0x2D3, level: 2, payload: childPayload)
            + columnRecordData(tagId: 0x2D4, level: 3, payload: grandchildPayload)
    }
}

private func columnAssemblyStreams(fromFixture id: String) throws -> ColumnAssemblyStreams {
    let fixture = try FixtureLoader.load(id: id)
    let ole: OLEFile
    do {
        ole = try OLEFile(fixture.documentURL.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    let streams = try StreamReader.rootStreams(from: ole.root.children)
    let reader = StreamReader(ole, streams)
    let fileHeader = try HwpFileHeader.load(reader.getDataFromStream(.fileHeader, false))
    let docInfoData = try reader.getDataFromStream(
        .docInfo,
        fileHeader.fileProperty.isCompressed
    )
    let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)
    let sectionDataArray = try reader.getDataFromStorage(
        .bodyText,
        fileHeader.fileProperty.isCompressed,
        expectedCount: Int(docInfo.documentProperties.sectionSize)
    )

    return ColumnAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectColumnControl(in hwp: HwpFile, match injected: InjectedColumnControl) {
    let column = columnControls(from: hwp).last

    expect(column?.otherCtrlId) == .column
    expect(column?.rawPayload) == injected.payload
    expect(column?.rawTrailing) == injected.rawTrailing
    expect(column?.rawTrailingWords) == [UInt16(0xFECA)]
    expect(column?.unknown) == injected.rawTrailing
    expect(column?.property.rawValue) == 4100
    expect(column?.property.count) == 1
    expect(column?.property.isSameWidth) == true
    expect(column?.spacing) == 0x1122
    expect(column?.property2) == 0x3344
    expect(column?.dividerType) == 0x55
    expect(column?.dividerThickness) == 0x66
    expect(column?.dividerColor) == HwpColor(0xAA, 0x99, 0x88)
    expect(column?.widthArray).to(beNil())
    expect(column?.unknownChildren) == [
        columnExpectedUnknownRecord(
            tagId: 0x2D1,
            level: 2,
            payload: injected.childPayload,
            children: [
                columnExpectedRecord(
                    tagId: 0x2D2,
                    level: 3,
                    payload: injected.grandchildPayload
                ),
            ]
        ),
    ]
}

private func expectMalformedColumnControl(
    in hwp: HwpFile,
    match injected: InjectedMalformedColumnControl
) {
    let other = columnOtherControls(from: hwp).last

    expect(other?.ctrlId) == .column
    expect(other?.rawPayload) == injected.payload
    expect(other?.rawTrailing) == injected.rawTrailing
    expect(other?.numberingInfo).to(beNil())
    expect(other?.pageHideInfo).to(beNil())
    expect(other?.indexmarkInfo).to(beNil())
    expect(other?.bookmarkInfo).to(beNil())
    expect(other?.unknownChildren) == [
        columnExpectedUnknownRecord(
            tagId: 0x2D3,
            level: 2,
            payload: injected.childPayload,
            children: [
                columnExpectedRecord(
                    tagId: 0x2D4,
                    level: 3,
                    payload: injected.grandchildPayload
                ),
            ]
        ),
    ]
}

private func columnControls(from hwp: HwpFile) -> [HwpColumn] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .column(column) = control else {
                return nil
            }
            return column
        }
    }
}

private func columnOtherControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .other(other) = control, other.ctrlId == .column else {
                return nil
            }
            return other
        }
    }
}

private func columnControlPayload(rawTrailing: Data) -> Data {
    var data = Data()
    data.append(columnLittleEndianData(HwpOtherCtrlId.column.rawValue))
    data.append(columnLittleEndianData(UInt16(4100)))
    data.append(columnLittleEndianData(HWPUNIT16(0x1122)))
    data.append(columnLittleEndianData(UInt16(0x3344)))
    data.append(columnLittleEndianData(UInt8(0x55)))
    data.append(columnLittleEndianData(UInt8(0x66)))
    data.append(columnLittleEndianData(COLORREF(0x7788_99AA)))
    data.append(rawTrailing)
    return data
}

private func columnRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = columnLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func columnExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        columnExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func columnExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func columnLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
