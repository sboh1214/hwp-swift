@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFilePageNumberPositionAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesPageNumberPositionThroughCodableRoundTrip()
        throws
    {
        let streams = try pageNumberPositionAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedPageNumberPosition(
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

        expectPageNumberPosition(in: hwp, match: injected)
        expectPageNumberPosition(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedPageNumberPositionAsOtherControl()
        throws
    {
        let streams = try pageNumberPositionAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMalformedPageNumberPosition(
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

        expectMalformedPageNumberPosition(in: hwp, match: injected)
        expectMalformedPageNumberPosition(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct PageNumberPositionAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedPageNumberPosition {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let childPayload: Data
    let grandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xCA, 0xFE])
        payload = pageNumberPositionPayload(rawTrailing: rawTrailing)
        childPayload = Data([0xC1, 0xC2])
        grandchildPayload = Data([0xC3])
        sectionData = baseSectionData
            + pageNumberPositionRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            )
            + pageNumberPositionRecordData(tagId: 0x2E1, level: 2, payload: childPayload)
            + pageNumberPositionRecordData(tagId: 0x2E2, level: 3, payload: grandchildPayload)
    }
}

private struct InjectedMalformedPageNumberPosition {
    let sectionData: Data
    let payload: Data
    let rawTrailing: Data
    let childPayload: Data
    let grandchildPayload: Data

    init(baseSectionData: Data) {
        payload = truncatedPageNumberPositionPayload()
        rawTrailing = Data(payload.dropFirst(MemoryLayout<UInt32>.size))
        childPayload = Data([0xD1, 0xD2])
        grandchildPayload = Data([0xD3])
        sectionData = baseSectionData
            + pageNumberPositionRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            )
            + pageNumberPositionRecordData(tagId: 0x2E3, level: 2, payload: childPayload)
            + pageNumberPositionRecordData(tagId: 0x2E4, level: 3, payload: grandchildPayload)
    }
}

private func pageNumberPositionAssemblyStreams(
    fromFixture id: String
) throws -> PageNumberPositionAssemblyStreams {
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

    return PageNumberPositionAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectPageNumberPosition(
    in hwp: HwpFile,
    match injected: InjectedPageNumberPosition
) {
    let position = pageNumberPositions(from: hwp).last

    expect(position?.otherCtrlId) == .pageNumberPosition
    expect(position?.rawPayload) == injected.payload
    expect(position?.rawTrailing) == injected.rawTrailing
    expect(position?.property) == 0x0102_0304
    expect(position?.userSymbol) == 0
    expect(position?.headDecoration) == 45
    expect(position?.tailDecoration) == 45
    expect(position?.unused) == 45
    expect(position?.unknown) == 0xAABB_CCDD
    expect(position?.unknownChildren) == [
        pageNumberExpectedUnknownRecord(
            tagId: 0x2E1,
            level: 2,
            payload: injected.childPayload,
            children: [
                pageNumberExpectedRecord(
                    tagId: 0x2E2,
                    level: 3,
                    payload: injected.grandchildPayload
                ),
            ]
        ),
    ]
}

private func expectMalformedPageNumberPosition(
    in hwp: HwpFile,
    match injected: InjectedMalformedPageNumberPosition
) {
    let other = pageNumberPositionOtherControls(from: hwp).last

    expect(other?.ctrlId) == .pageNumberPosition
    expect(other?.rawPayload) == injected.payload
    expect(other?.rawTrailing) == injected.rawTrailing
    expect(other?.numberingInfo).to(beNil())
    expect(other?.pageHideInfo).to(beNil())
    expect(other?.indexmarkInfo).to(beNil())
    expect(other?.bookmarkInfo).to(beNil())
    expect(other?.unknownChildren) == [
        pageNumberExpectedUnknownRecord(
            tagId: 0x2E3,
            level: 2,
            payload: injected.childPayload,
            children: [
                pageNumberExpectedRecord(
                    tagId: 0x2E4,
                    level: 3,
                    payload: injected.grandchildPayload
                ),
            ]
        ),
    ]
}

private func pageNumberPositions(from hwp: HwpFile) -> [HwpPageNumberPosition] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .pageNumberPosition(position) = control else {
                return nil
            }
            return position
        }
    }
}

private func pageNumberPositionOtherControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .other(other) = control, other.ctrlId == .pageNumberPosition else {
                return nil
            }
            return other
        }
    }
}

private func pageNumberPositionPayload(rawTrailing: Data) -> Data {
    var data = Data()
    data.append(pageNumberLittleEndianData(HwpOtherCtrlId.pageNumberPosition.rawValue))
    data.append(pageNumberLittleEndianData(UInt32(0x0102_0304)))
    data.append(pageNumberLittleEndianData(WCHAR(0)))
    data.append(pageNumberLittleEndianData(WCHAR(45)))
    data.append(pageNumberLittleEndianData(WCHAR(45)))
    data.append(pageNumberLittleEndianData(WCHAR(45)))
    data.append(pageNumberLittleEndianData(UInt32(0xAABB_CCDD)))
    data.append(rawTrailing)
    return data
}

private func truncatedPageNumberPositionPayload() -> Data {
    var data = Data()
    data.append(pageNumberLittleEndianData(HwpOtherCtrlId.pageNumberPosition.rawValue))
    data.append(pageNumberLittleEndianData(UInt32(0x0102_0304)))
    data.append(pageNumberLittleEndianData(WCHAR(0)))
    data.append(pageNumberLittleEndianData(WCHAR(45)))
    data.append(pageNumberLittleEndianData(WCHAR(45)))
    data.append(0xAA)
    return data
}

private func pageNumberPositionRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = pageNumberLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func pageNumberExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        pageNumberExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func pageNumberExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func pageNumberLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
