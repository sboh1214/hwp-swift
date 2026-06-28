@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileNumberingControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesAutoAndNewNumberThroughCodableRoundTrip()
        throws
    {
        let streams = try numberingAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedNumberingControls(
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

        expectAutoNumberControl(in: hwp, match: injected)
        expectAutoNumberControl(in: decoded, match: injected)
        expectNewNumberControl(in: hwp, match: injected)
        expectNewNumberControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct NumberingAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedNumberingControls {
    let sectionData: Data
    let autoPayload: Data
    let autoRawTrailing: Data
    let autoInfoTrailing: Data
    let autoUnknownPayload: Data
    let newPayload: Data
    let newRawTrailing: Data
    let newInfoTrailing: Data
    let newUnknownPayload: Data
    let newGrandchildPayload: Data

    init(baseSectionData: Data) {
        autoInfoTrailing = Data([0xA1, 0xA2])
        autoRawTrailing = numberingPayload(kind: 3, number: 12, format: 0x0031_0000)
            + autoInfoTrailing
        autoPayload = numberingLittleEndianData(HwpOtherCtrlId.autoNumber.rawValue)
            + autoRawTrailing
        autoUnknownPayload = Data([0xA3, 0xA4])

        newInfoTrailing = Data([0xB1])
        newRawTrailing = numberingPayload(kind: 4, number: 99, format: 0x0029_0000)
            + newInfoTrailing
        newPayload = numberingLittleEndianData(HwpOtherCtrlId.newNumber.rawValue)
            + newRawTrailing
        newUnknownPayload = Data([0xB2, 0xB3])
        newGrandchildPayload = Data([0xB4])

        sectionData = baseSectionData
            + numberingRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: autoPayload
            )
            + numberingRecordData(tagId: 0x2E4, level: 2, payload: autoUnknownPayload)
            + numberingRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: newPayload
            )
            + numberingRecordData(tagId: 0x2E5, level: 2, payload: newUnknownPayload)
            + numberingRecordData(tagId: 0x2E6, level: 3, payload: newGrandchildPayload)
    }
}

private func numberingAssemblyStreams(
    fromFixture id: String
) throws -> NumberingAssemblyStreams {
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

    return NumberingAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectAutoNumberControl(
    in hwp: HwpFile,
    match injected: InjectedNumberingControls
) {
    let autoNumber = autoNumberControls(from: hwp).last

    expect(autoNumber?.ctrlId) == .autoNumber
    expect(autoNumber?.rawPayload) == injected.autoPayload
    expect(autoNumber?.rawTrailing) == injected.autoRawTrailing
    expect(autoNumber?.numberingInfo?.kind) == 3
    expect(autoNumber?.numberingInfo?.number) == 12
    expect(autoNumber?.numberingInfo?.format) == 0x0031_0000
    expect(autoNumber?.numberingInfo?.rawTrailing) == injected.autoInfoTrailing
    expect(autoNumber?.unknownChildren) == [
        numberingExpectedUnknownRecord(
            tagId: 0x2E4,
            level: 2,
            payload: injected.autoUnknownPayload
        ),
    ]
}

private func expectNewNumberControl(
    in hwp: HwpFile,
    match injected: InjectedNumberingControls
) {
    let newNumber = newNumberControls(from: hwp).last

    expect(newNumber?.ctrlId) == .newNumber
    expect(newNumber?.rawPayload) == injected.newPayload
    expect(newNumber?.rawTrailing) == injected.newRawTrailing
    expect(newNumber?.numberingInfo?.kind) == 4
    expect(newNumber?.numberingInfo?.number) == 99
    expect(newNumber?.numberingInfo?.format) == 0x0029_0000
    expect(newNumber?.numberingInfo?.rawTrailing) == injected.newInfoTrailing
    expect(newNumber?.unknownChildren) == [
        numberingExpectedUnknownRecord(
            tagId: 0x2E5,
            level: 2,
            payload: injected.newUnknownPayload,
            children: [
                numberingExpectedRecord(
                    tagId: 0x2E6,
                    level: 3,
                    payload: injected.newGrandchildPayload
                ),
            ]
        ),
    ]
}

private func autoNumberControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .autoNumber(otherControl) = control else {
                return nil
            }
            return otherControl
        }
    }
}

private func newNumberControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .newNumber(otherControl) = control else {
                return nil
            }
            return otherControl
        }
    }
}

private func numberingPayload(kind: UInt32, number: UInt32, format: UInt32) -> Data {
    numberingLittleEndianData(kind)
        + numberingLittleEndianData(number)
        + numberingLittleEndianData(format)
}

private func numberingRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = numberingLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func numberingExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        numberingExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func numberingExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func numberingLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
