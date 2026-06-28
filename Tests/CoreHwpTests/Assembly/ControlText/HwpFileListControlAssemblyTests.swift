@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileListControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesListControlsThroughCodableRoundTrip() throws {
        let streams = try listAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedListControls(
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

        for spec in injected.specs {
            expectListControl(in: hwp, match: spec)
            expectListControl(in: decoded, match: spec)
        }
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedListControlAsOtherControl() throws {
        let streams = try listAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMalformedListControl(
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

        expectMalformedListControl(in: hwp, match: injected)
        expectMalformedListControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct ListAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedListControls {
    let sectionData: Data
    let specs: [InjectedListControl]

    init(baseSectionData: Data) {
        specs = [
            InjectedListControl(ctrlId: .header, index: 0),
            InjectedListControl(ctrlId: .footer, index: 1),
            InjectedListControl(ctrlId: .footnote, index: 2),
            InjectedListControl(ctrlId: .endnote, index: 3),
        ]
        sectionData = specs.reduce(baseSectionData) { data, spec in
            data + spec.recordData
        }
    }
}

private struct InjectedListControl {
    let ctrlId: HwpOtherCtrlId
    let recordData: Data
    let controlPayload: Data
    let controlRawTrailing: Data
    let listHeaderPayload: Data
    let listHeaderRawTrailing: Data
    let listHeaderUnknownPayload: Data
    let listHeaderGrandchildPayload: Data
    let paragraphPayload: Data
    let paragraphId: UInt32
    let controlUnknownPayload: Data
    let controlGrandchildPayload: Data

    init(ctrlId: HwpOtherCtrlId, index: UInt8) {
        self.ctrlId = ctrlId
        controlRawTrailing = Data([0xA0 + index])
        controlPayload = listLittleEndianData(ctrlId.rawValue) + controlRawTrailing
        listHeaderRawTrailing = Data([0xB0 + index, 0xB8 + index])
        listHeaderPayload = makeListHeaderPayload(
            paragraphCount: 1,
            property: UInt32(0x1100 + UInt32(index)),
            rawTrailing: listHeaderRawTrailing
        )
        listHeaderUnknownPayload = Data([0xC0 + index])
        listHeaderGrandchildPayload = Data([0xC8 + index])
        paragraphId = UInt32(0x9000 + UInt32(index))
        paragraphPayload = listParagraphHeaderPayload(paraId: paragraphId)
        controlUnknownPayload = Data([0xD0 + index])
        controlGrandchildPayload = Data([0xD8 + index])

        recordData = listRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: controlPayload
        )
            + listRecordData(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload
            )
            + listRecordData(
                tagId: 0x320 + UInt32(index),
                level: 3,
                payload: listHeaderUnknownPayload
            )
            + listRecordData(
                tagId: 0x330 + UInt32(index),
                level: 4,
                payload: listHeaderGrandchildPayload
            )
            + listRecordData(
                tagId: HwpSectionTag.paraHeader.rawValue,
                level: 2,
                payload: paragraphPayload
            )
            + listRecordData(tagId: HwpSectionTag.paraCharShape.rawValue, level: 3, payload: Data())
            + listRecordData(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 3, payload: Data())
            + listRecordData(tagId: 0x340 + UInt32(index), level: 2, payload: controlUnknownPayload)
            + listRecordData(
                tagId: 0x350 + UInt32(index),
                level: 3,
                payload: controlGrandchildPayload
            )
    }
}

private struct InjectedMalformedListControl {
    let sectionData: Data
    let ctrlId: HwpOtherCtrlId
    let controlPayload: Data
    let controlRawTrailing: Data
    let listHeaderPayload: Data
    let listHeaderUnknownPayload: Data
    let controlUnknownPayload: Data
    let controlGrandchildPayload: Data

    init(baseSectionData: Data) {
        ctrlId = .footer
        controlRawTrailing = Data([0xEE])
        controlPayload = listLittleEndianData(ctrlId.rawValue) + controlRawTrailing
        listHeaderPayload = Data([0xAA])
        listHeaderUnknownPayload = Data([0xAB])
        controlUnknownPayload = Data([0xAC])
        controlGrandchildPayload = Data([0xAD])

        sectionData = baseSectionData
            + listRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + listRecordData(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload
            )
            + listRecordData(tagId: 0x360, level: 3, payload: listHeaderUnknownPayload)
            + listRecordData(tagId: 0x361, level: 2, payload: controlUnknownPayload)
            + listRecordData(tagId: 0x362, level: 3, payload: controlGrandchildPayload)
    }
}

private func listAssemblyStreams(fromFixture id: String) throws -> ListAssemblyStreams {
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

    return ListAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectListControl(in hwp: HwpFile, match spec: InjectedListControl) {
    let control = listControl(spec.ctrlId, in: hwp)

    expect(control?.header.ctrlId) == spec.ctrlId.rawValue
    expect(control?.header.rawPayload) == spec.controlPayload
    expect(control?.header.unknownChildren) == expectedHeaderUnknownChildren(for: spec)
    expect(control?.listArray.count) == 1
    expect(control?.unknownChildren) == [
        expectedListUnknownRecord(
            tagId: 0x340 + listIndex(spec.ctrlId),
            level: 2,
            payload: spec.controlUnknownPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x350 + listIndex(spec.ctrlId),
                    level: 3,
                    payload: spec.controlGrandchildPayload
                ),
            ]
        ),
    ]

    let list = control?.listArray.first
    expect(list?.header.paragraphCount) == 1
    expect(list?.header.property) == 0x1100 + listIndex(spec.ctrlId)
    expect(list?.header.rawPayload) == spec.listHeaderPayload
    expect(list?.header.rawTrailing) == spec.listHeaderRawTrailing
    expect(list?.header.rawTrailingWords) == [
        UInt16(spec.listHeaderRawTrailing[0])
            | UInt16(spec.listHeaderRawTrailing[1]) << 8,
    ]
    expect(list?.headerRawPayload) == spec.listHeaderPayload
    expect(list?.headerUnknownChildren) == [
        expectedListUnknownRecord(
            tagId: 0x320 + listIndex(spec.ctrlId),
            level: 3,
            payload: spec.listHeaderUnknownPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x330 + listIndex(spec.ctrlId),
                    level: 4,
                    payload: spec.listHeaderGrandchildPayload
                ),
            ]
        ),
    ]
    expect(list?.paragraphArray.count) == 1

    let paragraph = list?.paragraphArray.first
    expect(paragraph?.paraHeader.rawPayload) == spec.paragraphPayload
    expect(paragraph?.paraHeader.paraId) == spec.paragraphId
    expect(paragraph?.paraCharShape.rawPayload).to(beEmpty())
    expect(paragraph?.paraLineSeg.rawPayload).to(beEmpty())
    expect(paragraph?.unknownChildren).to(beEmpty())
}

private func expectMalformedListControl(
    in hwp: HwpFile,
    match injected: InjectedMalformedListControl
) {
    let other = listOtherControls(from: hwp, ctrlId: injected.ctrlId).last

    expect(other?.ctrlId) == injected.ctrlId
    expect(other?.rawPayload) == injected.controlPayload
    expect(other?.rawTrailing) == injected.controlRawTrailing
    expect(other?.ctrlDataRecords).to(beEmpty())
    expect(other?.unknownChildren) == [
        expectedListUnknownRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: injected.listHeaderPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x360,
                    level: 3,
                    payload: injected.listHeaderUnknownPayload
                ),
            ]
        ),
        expectedListUnknownRecord(
            tagId: 0x361,
            level: 2,
            payload: injected.controlUnknownPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x362,
                    level: 3,
                    payload: injected.controlGrandchildPayload
                ),
            ]
        ),
    ]
}

private func listControl(_ ctrlId: HwpOtherCtrlId, in hwp: HwpFile) -> HwpListControl? {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control -> HwpListControl? in
            switch (ctrlId, control) {
            case let (.header, .header(listControl)),
                 let (.footer, .footer(listControl)),
                 let (.footnote, .footnote(listControl)),
                 let (.endnote, .endnote(listControl)):
                return listControl
            default:
                return nil
            }
        }
    }.last
}

private func listOtherControls(from hwp: HwpFile, ctrlId: HwpOtherCtrlId) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .other(other) = control, other.ctrlId == ctrlId else {
                return nil
            }
            return other
        }
    }
}

private func expectedHeaderUnknownChildren(for spec: InjectedListControl) -> [HwpUnknownRecord] {
    [
        expectedListUnknownRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: spec.listHeaderPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x320 + listIndex(spec.ctrlId),
                    level: 3,
                    payload: spec.listHeaderUnknownPayload,
                    children: [
                        expectedListUnknownRecord(
                            tagId: 0x330 + listIndex(spec.ctrlId),
                            level: 4,
                            payload: spec.listHeaderGrandchildPayload
                        ),
                    ]
                ),
            ]
        ),
        expectedListUnknownRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 2,
            payload: spec.paragraphPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 3,
                    payload: Data()
                ),
                expectedListUnknownRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 3,
                    payload: Data()
                ),
            ]
        ),
        expectedListUnknownRecord(
            tagId: 0x340 + listIndex(spec.ctrlId),
            level: 2,
            payload: spec.controlUnknownPayload,
            children: [
                expectedListUnknownRecord(
                    tagId: 0x350 + listIndex(spec.ctrlId),
                    level: 3,
                    payload: spec.controlGrandchildPayload
                ),
            ]
        ),
    ]
}

private func listIndex(_ ctrlId: HwpOtherCtrlId) -> UInt32 {
    switch ctrlId {
    case .header:
        0
    case .footer:
        1
    case .footnote:
        2
    case .endnote:
        3
    default:
        UInt32.max
    }
}

private func makeListHeaderPayload(
    paragraphCount: Int32,
    property: UInt32,
    rawTrailing: Data
) -> Data {
    listLittleEndianData(paragraphCount)
        + listLittleEndianData(property)
        + rawTrailing
}

private func listParagraphHeaderPayload(paraId: UInt32) -> Data {
    var data = Data()
    data.append(listLittleEndianData(UInt32(0x8000_0000)))
    data.append(listLittleEndianData(UInt32(0)))
    data.append(listLittleEndianData(UInt16(0)))
    data.append(listLittleEndianData(UInt8(0)))
    data.append(listLittleEndianData(UInt8(0)))
    data.append(listLittleEndianData(UInt16(0)))
    data.append(listLittleEndianData(UInt16(0)))
    data.append(listLittleEndianData(UInt16(0)))
    data.append(listLittleEndianData(paraId))
    data.append(listLittleEndianData(UInt16(0)))
    return data
}

private func listRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = listLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func expectedListUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func listLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
