@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileTableControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesTableThroughCodableRoundTrip() throws {
        let streams = try tableAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedTableControl(
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

        expectTableControl(in: hwp, match: injected)
        expectTableControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedTableAsNotImplemented() throws {
        let streams = try tableAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMalformedTableControl(
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

        expectMalformedTableControl(in: hwp, match: injected)
        expectMalformedTableControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct TableAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedTableControl {
    let sectionData: Data
    let commonPayload: Data
    let controlPayload: Data
    let controlRawTrailing: Data
    let tablePropertyPayload: Data
    let tablePropertyRawTrailing: Data
    let cellHeaderPayload: Data
    let cellHeaderRawTrailing: Data
    let cellHeaderUnknownPayload: Data
    let paragraphPayload: Data
    let paragraphId: UInt32
    let unknownPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        commonPayload = tableCommonCtrlPropertyPayload(
            width: 0x1111_2222,
            height: 0x3333_4444,
            instanceId: 0x5555_6666
        )
        controlRawTrailing = Data([0xCA, 0xFE])
        controlPayload = commonPayload + controlRawTrailing
        tablePropertyRawTrailing = Data([0xA1, 0xA2])
        tablePropertyPayload = makeTablePropertyPayload(
            rowCount: 1,
            columnCount: 1,
            zonePropertySize: 1,
            rawTrailing: tablePropertyRawTrailing
        )
        cellHeaderRawTrailing = Data([0xB1, 0xB2])
        cellHeaderPayload = tableCellHeaderPayload(
            paragraphCount: 1,
            rawTrailing: cellHeaderRawTrailing
        )
        cellHeaderUnknownPayload = Data([0xB3])
        paragraphId = 0x7777_8888
        paragraphPayload = tableParagraphHeaderPayload(paraId: paragraphId)
        unknownPayload = Data([0xC1, 0xC2])
        unknownGrandchildPayload = Data([0xC3])

        let recordParts = TableControlRecordParts(
            controlPayload: controlPayload,
            tablePropertyPayload: tablePropertyPayload,
            cellHeaderPayload: cellHeaderPayload,
            cellHeaderUnknownPayload: cellHeaderUnknownPayload,
            paragraphPayload: paragraphPayload,
            unknownPayload: unknownPayload,
            unknownGrandchildPayload: unknownGrandchildPayload
        )
        sectionData = assembledTableControlData(
            baseSectionData: baseSectionData,
            parts: recordParts
        )
    }
}

private struct TableControlRecordParts {
    let controlPayload: Data
    let tablePropertyPayload: Data
    let cellHeaderPayload: Data
    let cellHeaderUnknownPayload: Data
    let paragraphPayload: Data
    let unknownPayload: Data
    let unknownGrandchildPayload: Data
}

private func assembledTableControlData(
    baseSectionData: Data,
    parts: TableControlRecordParts
) -> Data {
    baseSectionData
        + tableRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: parts.controlPayload
        )
        + tableRecordData(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: parts.tablePropertyPayload
        )
        + tableRecordData(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: parts.cellHeaderPayload
        )
        + tableRecordData(tagId: 0x380, level: 3, payload: parts.cellHeaderUnknownPayload)
        + tableRecordData(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 2,
            payload: parts.paragraphPayload
        )
        + tableRecordData(tagId: HwpSectionTag.paraCharShape.rawValue, level: 3, payload: Data())
        + tableRecordData(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 3, payload: Data())
        + tableRecordData(tagId: 0x390, level: 2, payload: parts.unknownPayload)
        + tableRecordData(tagId: 0x391, level: 3, payload: parts.unknownGrandchildPayload)
}

private struct InjectedMalformedTableControl {
    let sectionData: Data
    let controlPayload: Data
    let tablePropertyPayload: Data
    let tablePropertyUnknownPayload: Data
    let unknownPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        controlPayload = tableCommonCtrlPropertyPayload(
            width: 0x0102_0304,
            height: 0x0506_0708,
            instanceId: 0x090A_0B0C
        )
        tablePropertyPayload = Data([0xAA])
        tablePropertyUnknownPayload = Data([0xAB])
        unknownPayload = Data([0xAC])
        unknownGrandchildPayload = Data([0xAD])

        sectionData = baseSectionData
            + tableRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + tableRecordData(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePropertyPayload
            )
            + tableRecordData(tagId: 0x3A0, level: 3, payload: tablePropertyUnknownPayload)
            + tableRecordData(tagId: 0x3A1, level: 2, payload: unknownPayload)
            + tableRecordData(tagId: 0x3A2, level: 3, payload: unknownGrandchildPayload)
    }
}

private func tableAssemblyStreams(fromFixture id: String) throws -> TableAssemblyStreams {
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

    return TableAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectTableControl(in hwp: HwpFile, match injected: InjectedTableControl) {
    let table = tableControls(from: hwp).last

    expect(table?.commonCtrlProperty.commonCtrlId) == .table
    expect(table?.commonCtrlProperty.rawPayload) == injected.commonPayload
    expect(table?.commonCtrlProperty.width) == 0x1111_2222
    expect(table?.commonCtrlProperty.height) == 0x3333_4444
    expect(table?.commonCtrlProperty.instanceId) == 0x5555_6666
    expect(table?.rawPayload) == injected.controlPayload
    expect(table?.rawTrailing) == injected.controlRawTrailing
    expect(table?.tableProperty.rawPayload) == injected.tablePropertyPayload
    expect(table?.tableProperty.rawTrailing) == injected.tablePropertyRawTrailing
    expect(table?.tableProperty.rowCount) == 1
    expect(table?.tableProperty.columnCount) == 1
    expect(table?.tableProperty.validZoneInfoSize) == 1
    expect(table?.tableProperty.zonePropertyArray?.map(\.borderFillId)) == [0x8888]
    expect(table?.unknownChildren) == [
        expectedTableUnknownRecord(
            tagId: 0x390,
            level: 2,
            payload: injected.unknownPayload,
            children: [
                expectedTableUnknownRecord(
                    tagId: 0x391,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]
    expect(table?.cellArray.count) == 1

    let cell = table?.cellArray.first
    expect(cell?.header.rawPayload) == injected.cellHeaderPayload
    expect(cell?.header.rawTrailing) ==
        Data(repeating: 0, count: 39) + injected.cellHeaderRawTrailing
    expect(cell?.header.paragraphCount) == 1
    expect(cell?.header.unknownChildren) == [
        expectedTableUnknownRecord(
            tagId: 0x380,
            level: 3,
            payload: injected.cellHeaderUnknownPayload
        ),
    ]
    expect(cell?.paragraphArray.count) == 1
    expect(cell?.paragraphArray.first?.paraHeader.rawPayload) == injected.paragraphPayload
    expect(cell?.paragraphArray.first?.paraHeader.paraId) == injected.paragraphId
    expect(cell?.paragraphArray.first?.paraCharShape.rawPayload).to(beEmpty())
    expect(cell?.paragraphArray.first?.paraLineSeg.rawPayload).to(beEmpty())
}

private func expectMalformedTableControl(
    in hwp: HwpFile,
    match injected: InjectedMalformedTableControl
) {
    let header = tableNotImplementedControls(from: hwp).last

    expect(header?.ctrlId) == HwpCommonCtrlId.table.rawValue
    expect(header?.rawPayload) == injected.controlPayload
    expect(header?.unknownChildren) == [
        expectedTableUnknownRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: injected.tablePropertyPayload,
            children: [
                expectedTableUnknownRecord(
                    tagId: 0x3A0,
                    level: 3,
                    payload: injected.tablePropertyUnknownPayload
                ),
            ]
        ),
        expectedTableUnknownRecord(
            tagId: 0x3A1,
            level: 2,
            payload: injected.unknownPayload,
            children: [
                expectedTableUnknownRecord(
                    tagId: 0x3A2,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]
}

private func tableControls(from hwp: HwpFile) -> [HwpTable] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .table(table) = control else {
                return nil
            }
            return table
        }
    }
}

private func tableNotImplementedControls(from hwp: HwpFile) -> [HwpCtrlHeader] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .notImplemented(header) = control,
                  header.ctrlId == HwpCommonCtrlId.table.rawValue
            else {
                return nil
            }
            return header
        }
    }
}

private func tableCommonCtrlPropertyPayload(
    width: HWPUNIT,
    height: HWPUNIT,
    instanceId: UInt32
) -> Data {
    var data = Data()
    data.append(tableLittleEndianData(HwpCommonCtrlId.table.rawValue))
    data.append(tableLittleEndianData(UInt32(0x0102_0304)))
    data.append(tableLittleEndianData(HWPUNIT(0x1111)))
    data.append(tableLittleEndianData(HWPUNIT(0x2222)))
    data.append(tableLittleEndianData(width))
    data.append(tableLittleEndianData(height))
    data.append(tableLittleEndianData(Int32(7)))
    data.append(tableLittleEndianData(HWPUNIT16(1)))
    data.append(tableLittleEndianData(HWPUNIT16(2)))
    data.append(tableLittleEndianData(HWPUNIT16(3)))
    data.append(tableLittleEndianData(HWPUNIT16(4)))
    data.append(tableLittleEndianData(instanceId))
    data.append(tableLittleEndianData(Int32(1)))
    data.append(tableLittleEndianData(WORD(0)))
    return data
}

private func makeTablePropertyPayload(
    rowCount: UInt16,
    columnCount: UInt16,
    zonePropertySize: UInt16,
    rawTrailing: Data
) -> Data {
    var data = Data()
    data.append(tableLittleEndianData(UInt32(0x0203_0405)))
    data.append(tableLittleEndianData(rowCount))
    data.append(tableLittleEndianData(columnCount))
    data.append(tableLittleEndianData(HWPUNIT16(0x1111)))
    data.append(tableLittleEndianData(HWPUNIT16(0x2222)))
    data.append(tableLittleEndianData(HWPUNIT16(0x3333)))
    data.append(tableLittleEndianData(HWPUNIT16(0x4444)))
    data.append(tableLittleEndianData(HWPUNIT16(0x5555)))
    for _ in 0 ..< rowCount {
        data.append(tableLittleEndianData(UInt16(0x6666)))
    }
    data.append(tableLittleEndianData(UInt16(0x7777)))
    data.append(tableLittleEndianData(zonePropertySize))
    data.append(tableZonePropertyPayload(borderFillId: 0x8888))
    data.append(rawTrailing)
    return data
}

private func tableZonePropertyPayload(borderFillId: UInt16) -> Data {
    var data = Data()
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(borderFillId))
    return data
}

private func tableCellHeaderPayload(
    paragraphCount: Int32,
    rawTrailing: Data
) -> Data {
    var data = Data()
    data.append(tableLittleEndianData(paragraphCount))
    data.append(tableLittleEndianData(UInt32(0x1010_2020)))
    data.append(Data(repeating: 0, count: 39))
    data.append(rawTrailing)
    return data
}

private func tableParagraphHeaderPayload(paraId: UInt32) -> Data {
    var data = Data()
    data.append(tableLittleEndianData(UInt32(0x8000_0000)))
    data.append(tableLittleEndianData(UInt32(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt8(0)))
    data.append(tableLittleEndianData(UInt8(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(UInt16(0)))
    data.append(tableLittleEndianData(paraId))
    data.append(tableLittleEndianData(UInt16(0)))
    return data
}

private func tableRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = tableLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func expectedTableUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func tableLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
