@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileSectionDefAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesSectionDefThroughCodableRoundTrip() throws {
        let streams = try sectionDefAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedSectionDef(
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

        expectSectionDef(in: hwp, match: injected)
        expectSectionDef(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedSectionDefAsOtherControl() throws {
        let streams = try sectionDefAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMalformedSectionDef(
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

        expectMalformedSectionDef(in: hwp, match: injected)
        expectMalformedSectionDef(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct SectionDefAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedSectionDef {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let pageDefPayload: Data
    let footnotePayload: Data
    let endnotePayload: Data
    let bothBorderPayload: Data
    let evenBorderPayload: Data
    let oddBorderPayload: Data
    let unknownPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xCA, 0xFE])
        payload = sectionDefPayload(rawTrailing: rawTrailing)
        pageDefPayload = sectionDefPageDefPayload(rawTrailing: Data([0xA1]))
        footnotePayload = sectionDefFootnoteShapePayload(
            userSymbol: 0x21,
            rawTrailing: Data([0x00, 0x00, 0xA2])
        )
        endnotePayload = sectionDefFootnoteShapePayload(
            userSymbol: 0x22,
            rawTrailing: Data([0x00, 0x00, 0xA3])
        )
        bothBorderPayload = sectionDefPageBorderFillPayload(rawTrailing: Data([0xB1]))
        evenBorderPayload = sectionDefPageBorderFillPayload(rawTrailing: Data([0xB2]))
        oddBorderPayload = sectionDefPageBorderFillPayload(rawTrailing: Data([0xB3]))
        unknownPayload = Data([0xC1, 0xC2])
        unknownGrandchildPayload = Data([0xC3])

        sectionData = assembledSectionDefData(
            baseSectionData: baseSectionData,
            payload: payload,
            children: [
                SectionDefChildSpec(.pageDef, pageDefPayload),
                SectionDefChildSpec(.footnoteShape, footnotePayload),
                SectionDefChildSpec(.footnoteShape, endnotePayload),
                SectionDefChildSpec(.pageBorderFill, bothBorderPayload),
                SectionDefChildSpec(.pageBorderFill, evenBorderPayload),
                SectionDefChildSpec(.pageBorderFill, oddBorderPayload),
            ],
            unknownPayload: unknownPayload,
            unknownGrandchildPayload: unknownGrandchildPayload
        )
    }
}

private struct InjectedMalformedSectionDef {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let childRecords: [SectionDefChildSpec]
    let unknownPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xAA])
        payload = concatenatedData(
            sectionDefLittleEndianData(HwpOtherCtrlId.section.rawValue),
            rawTrailing
        )
        childRecords = [
            SectionDefChildSpec(.pageDef, sectionDefPageDefPayload()),
            SectionDefChildSpec(.footnoteShape, sectionDefFootnoteShapePayload()),
            SectionDefChildSpec(.footnoteShape, sectionDefFootnoteShapePayload()),
            SectionDefChildSpec(.pageBorderFill, sectionDefPageBorderFillPayload()),
            SectionDefChildSpec(.pageBorderFill, sectionDefPageBorderFillPayload()),
            SectionDefChildSpec(.pageBorderFill, sectionDefPageBorderFillPayload()),
        ]
        unknownPayload = Data([0xD1, 0xD2])
        unknownGrandchildPayload = Data([0xD3])

        let childSectionData = childRecords.reduce(
            concatenatedData(
                baseSectionData,
                sectionDefRecordData(
                    tagId: HwpSectionTag.ctrlHeader.rawValue,
                    level: 1,
                    payload: payload
                )
            )
        ) { data, child in
            concatenatedData(
                data,
                sectionDefRecordData(tagId: child.tag.rawValue, level: 2, payload: child.payload)
            )
        }
        sectionData = concatenatedData(
            childSectionData,
            sectionDefRecordData(tagId: 0x2C3, level: 2, payload: unknownPayload),
            sectionDefRecordData(tagId: 0x2C4, level: 3, payload: unknownGrandchildPayload)
        )
    }
}

private struct SectionDefChildSpec {
    let tag: HwpSectionTag
    let payload: Data

    init(_ tag: HwpSectionTag, _ payload: Data) {
        self.tag = tag
        self.payload = payload
    }
}

private func assembledSectionDefData(
    baseSectionData: Data,
    payload: Data,
    children: [SectionDefChildSpec],
    unknownPayload: Data,
    unknownGrandchildPayload: Data
) -> Data {
    var data = baseSectionData
    data.append(sectionDefRecordData(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: payload
    ))
    for child in children {
        data.append(sectionDefRecordData(
            tagId: child.tag.rawValue,
            level: 2,
            payload: child.payload
        ))
    }
    data.append(sectionDefRecordData(tagId: 0x2C1, level: 2, payload: unknownPayload))
    data.append(sectionDefRecordData(tagId: 0x2C2, level: 3, payload: unknownGrandchildPayload))
    return data
}

private func sectionDefAssemblyStreams(fromFixture id: String) throws -> SectionDefAssemblyStreams {
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

    return SectionDefAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectSectionDef(in hwp: HwpFile, match injected: InjectedSectionDef) {
    let sectionDef = sectionDefs(from: hwp).last

    expect(sectionDef?.rawPayload) == injected.payload
    expect(sectionDef?.ctrlId) == HwpOtherCtrlId.section.rawValue
    expect(sectionDef?.columnSpacing) == 0x1111
    expect(sectionDef?.verticalLineAlign) == 0x2222
    expect(sectionDef?.horizontalLineAlign) == 0x3333
    expect(sectionDef?.defaultTabSpacing) == 0x4444_5555
    expect(sectionDef?.numberParaShapeId) == 0x6666
    expect(sectionDef?.pageStartNumber) == 1
    expect(sectionDef?.pictureStartNumber) == 2
    expect(sectionDef?.tableStartNumber) == 3
    expect(sectionDef?.equationNumber) == 4
    expect(sectionDef?.defaultLanguage) == 0x0412
    expect(sectionDef?.unknown) == injected.rawTrailing
    expect(sectionDef?.pageDef.rawPayload) == injected.pageDefPayload
    expect(sectionDef?.footNoteShape.rawPayload) == injected.footnotePayload
    expect(sectionDef?.endNoteShape.rawPayload) == injected.endnotePayload
    expect(sectionDef?.pageBorderFillBoth.rawPayload) == injected.bothBorderPayload
    expect(sectionDef?.pageBorderFillEven.rawPayload) == injected.evenBorderPayload
    expect(sectionDef?.pageBorderFillOdd.rawPayload) == injected.oddBorderPayload
    expect(sectionDef?.unknownChildren) == [
        sectionDefExpectedUnknownRecord(
            tagId: 0x2C1,
            level: 2,
            payload: injected.unknownPayload,
            children: [
                sectionDefExpectedRecord(
                    tagId: 0x2C2,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]
}

private func expectMalformedSectionDef(
    in hwp: HwpFile,
    match injected: InjectedMalformedSectionDef
) {
    let other = sectionDefOtherControls(from: hwp).last

    expect(other?.ctrlId) == .section
    expect(other?.rawPayload) == injected.payload
    expect(other?.rawTrailing) == injected.rawTrailing
    expect(other?.ctrlDataRecords).to(beEmpty())
    expect(other?.unknownChildren) == malformedSectionDefExpectedChildren(injected)
}

private func malformedSectionDefExpectedChildren(
    _ injected: InjectedMalformedSectionDef
) -> [HwpUnknownRecord] {
    injected.childRecords.map { child in
        sectionDefExpectedUnknownRecord(
            tagId: child.tag.rawValue,
            level: 2,
            payload: child.payload
        )
    }
        + [
            sectionDefExpectedUnknownRecord(
                tagId: 0x2C3,
                level: 2,
                payload: injected.unknownPayload,
                children: [
                    sectionDefExpectedRecord(
                        tagId: 0x2C4,
                        level: 3,
                        payload: injected.unknownGrandchildPayload
                    ),
                ]
            ),
        ]
}

private func sectionDefs(from hwp: HwpFile) -> [HwpSectionDef] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .section(sectionDef) = control else {
                return nil
            }
            return sectionDef
        }
    }
}

private func sectionDefOtherControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .other(other) = control, other.ctrlId == .section else {
                return nil
            }
            return other
        }
    }
}

private func sectionDefPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    data.append(sectionDefLittleEndianData(HwpOtherCtrlId.section.rawValue))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0x1111)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0x2222)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0x3333)))
    data.append(sectionDefLittleEndianData(HWPUNIT(0x4444_5555)))
    data.append(sectionDefLittleEndianData(UInt16(0x6666)))
    data.append(sectionDefLittleEndianData(UInt16(1)))
    data.append(sectionDefLittleEndianData(UInt16(2)))
    data.append(sectionDefLittleEndianData(UInt16(3)))
    data.append(sectionDefLittleEndianData(UInt16(4)))
    data.append(sectionDefLittleEndianData(UInt16(0x0412)))
    data.append(rawTrailing)
    return data
}

private func sectionDefPageDefPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    for _ in 0 ..< 9 {
        data.append(sectionDefLittleEndianData(HWPUNIT(0)))
    }
    data.append(sectionDefLittleEndianData(UInt32(0)))
    data.append(rawTrailing)
    return data
}

private func sectionDefFootnoteShapePayload(
    userSymbol: WCHAR = 0,
    rawTrailing: Data = Data([0, 0])
) -> Data {
    var data = Data()
    data.append(sectionDefLittleEndianData(UInt32(0)))
    data.append(sectionDefLittleEndianData(userSymbol))
    data.append(sectionDefLittleEndianData(WCHAR(0)))
    data.append(sectionDefLittleEndianData(WCHAR(0)))
    data.append(sectionDefLittleEndianData(UInt16(1)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefLittleEndianData(UInt8(0)))
    data.append(sectionDefLittleEndianData(UInt8(0)))
    data.append(sectionDefLittleEndianData(COLORREF(0)))
    data.append(rawTrailing)
    return data
}

private func sectionDefPageBorderFillPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    data.append(sectionDefLittleEndianData(UInt32(0)))
    for _ in 0 ..< 5 {
        data.append(sectionDefLittleEndianData(UInt16(0)))
    }
    data.append(rawTrailing)
    return data
}

private func sectionDefRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = sectionDefLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func sectionDefExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        sectionDefExpectedRecord(
            tagId: tagId,
            level: level,
            payload: payload,
            children: children
        )
    )
}

private func sectionDefExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func sectionDefLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
