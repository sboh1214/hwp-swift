@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileOtherControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesBookmarkCtrlDataThroughCodableRoundTrip()
        throws
    {
        let streams = try otherControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedBookmarkControl(
            baseSectionData: try XCTUnwrap(streams.sectionDataArray.first)
        )
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0] = injected.sectionData

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expectBookmarkControl(in: hwp, match: injected)
        expectBookmarkControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesPageHideAndIndexmarkThroughCodableRoundTrip()
        throws
    {
        let streams = try otherControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedPageHideIndexmark(
            baseSectionData: try XCTUnwrap(streams.sectionDataArray.first)
        )
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0] = injected.sectionData

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expectPageHideControl(in: hwp, match: injected)
        expectPageHideControl(in: decoded, match: injected)
        expectIndexmarkControl(in: hwp, match: injected)
        expectIndexmarkControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct OtherControlAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedBookmarkControl {
    let sectionData: Data
    let controlPayload: Data
    let rawTrailing: Data
    let bookmarkName: String
    let bookmarkNameRawPayload: Data
    let ctrlDataPayload: Data
    let ctrlDataRawTrailing: Data
    let ctrlDataUnknownPayload: Data
    let unknownChildPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        rawTrailing = Data([0xA9, 0xAA])
        controlPayload = otherControlLittleEndianData(HwpOtherCtrlId.bookmark.rawValue)
            + rawTrailing
        bookmarkName = "CoreHwpBookmarkInjected"
        bookmarkNameRawPayload = otherControlUTF16LittleEndianData(bookmarkName)
        ctrlDataRawTrailing = Data([0xCA, 0xFE])
        ctrlDataPayload = Self.bookmarkCtrlDataPayload(
            name: bookmarkName,
            rawTrailing: ctrlDataRawTrailing
        )
        ctrlDataUnknownPayload = Data([0xB1, 0xB2])
        unknownChildPayload = Data([0xC1, 0xC2])
        unknownGrandchildPayload = Data([0xC3])

        sectionData = baseSectionData
            + otherControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + otherControlRecordData(
                tagId: HwpSectionTag.ctrlData.rawValue,
                level: 2,
                payload: ctrlDataPayload
            )
            + otherControlRecordData(
                tagId: 0x2F2,
                level: 3,
                payload: ctrlDataUnknownPayload
            )
            + otherControlRecordData(
                tagId: 0x2F1,
                level: 2,
                payload: unknownChildPayload
            )
            + otherControlRecordData(
                tagId: 0x2F0,
                level: 3,
                payload: unknownGrandchildPayload
            )
    }

    private static func bookmarkCtrlDataPayload(
        name: String,
        rawTrailing: Data
    ) -> Data {
        var payload = Data(repeating: 0, count: 10)
        payload.append(otherControlLittleEndianData(WORD(name.utf16.count)))
        payload.append(name.utf16.reduce(into: Data()) { data, codeUnit in
            data.append(otherControlLittleEndianData(WCHAR(codeUnit)))
        })
        payload.append(rawTrailing)
        return payload
    }
}

private struct InjectedPageHideIndexmark {
    let sectionData: Data
    let pageHidePayload: Data
    let pageHideRawTrailing: Data
    let pageHideInfoRawTrailing: Data
    let pageHideUnknownPayload: Data
    let indexmarkPayload: Data
    let indexmarkRawTrailing: Data
    let indexmarkText: String
    let indexmarkTextPayload: Data
    let indexmarkInfoRawTrailing: Data
    let indexmarkUnknownPayload: Data
    let indexmarkGrandchildPayload: Data

    init(baseSectionData: Data) {
        pageHideInfoRawTrailing = Data([0xA1, 0xA2])
        pageHideRawTrailing = otherControlLittleEndianData(UInt32(0x20))
            + pageHideInfoRawTrailing
        pageHidePayload = otherControlLittleEndianData(HwpOtherCtrlId.pageHide.rawValue)
            + pageHideRawTrailing
        pageHideUnknownPayload = Data([0xA3, 0xA4])

        indexmarkText = "InjectedIndex"
        indexmarkTextPayload = otherControlUTF16LittleEndianData(indexmarkText)
        indexmarkInfoRawTrailing = Data([0xB1, 0xB2, 0xB3])
        indexmarkRawTrailing = otherControlLittleEndianData(UInt16(indexmarkText.utf16.count))
            + indexmarkTextPayload
            + indexmarkInfoRawTrailing
        indexmarkPayload = otherControlLittleEndianData(HwpOtherCtrlId.indexmark.rawValue)
            + indexmarkRawTrailing
        indexmarkUnknownPayload = Data([0xB4, 0xB5])
        indexmarkGrandchildPayload = Data([0xB6])

        sectionData = baseSectionData
            + otherControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: pageHidePayload
            )
            + otherControlRecordData(
                tagId: 0x2E8,
                level: 2,
                payload: pageHideUnknownPayload
            )
            + otherControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: indexmarkPayload
            )
            + otherControlRecordData(
                tagId: 0x2E9,
                level: 2,
                payload: indexmarkUnknownPayload
            )
            + otherControlRecordData(
                tagId: 0x2EA,
                level: 3,
                payload: indexmarkGrandchildPayload
            )
    }
}

private func otherControlAssemblyStreams(
    fromFixture id: String
) throws -> OtherControlAssemblyStreams {
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

    return OtherControlAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectBookmarkControl(
    in hwp: HwpFile,
    match injected: InjectedBookmarkControl
) {
    let bookmark = bookmarkControls(from: hwp).last

    expect(bookmark?.ctrlId) == .bookmark
    expect(bookmark?.rawPayload) == injected.controlPayload
    expect(bookmark?.rawTrailing) == injected.rawTrailing
    expect(bookmark?.bookmarkInfo?.name) == injected.bookmarkName
    expect(bookmark?.bookmarkInfo?.nameRawPayload) == injected.bookmarkNameRawPayload
    expect(bookmark?.bookmarkInfo?.rawTrailing) == injected.ctrlDataRawTrailing
    expect(bookmark?.ctrlDataRecords.map(\.rawPayload)) == [injected.ctrlDataPayload]
    expect(bookmark?.ctrlDataRecords.first?.unknownChildren) == [
        otherControlExpectedUnknownRecord(
            tagId: 0x2F2,
            level: 3,
            payload: injected.ctrlDataUnknownPayload
        ),
    ]
    expect(bookmark?.unknownChildren ?? []) == [
        otherControlExpectedUnknownRecord(
            tagId: 0x2F1,
            level: 2,
            payload: injected.unknownChildPayload,
            children: [
                otherControlExpectedRecord(
                    tagId: 0x2F0,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]
}

private func expectPageHideControl(
    in hwp: HwpFile,
    match injected: InjectedPageHideIndexmark
) {
    let pageHide = pageHideControls(from: hwp).last

    expect(pageHide?.ctrlId) == .pageHide
    expect(pageHide?.rawPayload) == injected.pageHidePayload
    expect(pageHide?.rawTrailing) == injected.pageHideRawTrailing
    expect(pageHide?.pageHideInfo?.rawValue) == 0x20
    expect(pageHide?.pageHideInfo?.rawTrailing) == injected.pageHideInfoRawTrailing
    expect(pageHide?.unknownChildren) == [
        otherControlExpectedUnknownRecord(
            tagId: 0x2E8,
            level: 2,
            payload: injected.pageHideUnknownPayload
        ),
    ]
}

private func expectIndexmarkControl(
    in hwp: HwpFile,
    match injected: InjectedPageHideIndexmark
) {
    let indexmark = indexmarkControls(from: hwp).last

    expect(indexmark?.ctrlId) == .indexmark
    expect(indexmark?.rawPayload) == injected.indexmarkPayload
    expect(indexmark?.rawTrailing) == injected.indexmarkRawTrailing
    expect(indexmark?.indexmarkInfo?.text) == injected.indexmarkText
    expect(indexmark?.indexmarkInfo?.textRawPayload) == injected.indexmarkTextPayload
    expect(indexmark?.indexmarkInfo?.rawTrailing) == injected.indexmarkInfoRawTrailing
    expect(indexmark?.unknownChildren) == [
        otherControlExpectedUnknownRecord(
            tagId: 0x2E9,
            level: 2,
            payload: injected.indexmarkUnknownPayload,
            children: [
                otherControlExpectedRecord(
                    tagId: 0x2EA,
                    level: 3,
                    payload: injected.indexmarkGrandchildPayload
                ),
            ]
        ),
    ]
}

private func bookmarkControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .bookmark(otherControl) = control else {
                return nil
            }
            return otherControl
        }
    }
}

private func pageHideControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .pageHide(otherControl) = control else {
                return nil
            }
            return otherControl
        }
    }
}

private func indexmarkControls(from hwp: HwpFile) -> [HwpOtherControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .indexmark(otherControl) = control else {
                return nil
            }
            return otherControl
        }
    }
}

private func otherControlRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = otherControlLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func otherControlExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        otherControlExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func otherControlExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func otherControlLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func otherControlUTF16LittleEndianData(_ text: String) -> Data {
    text.utf16.reduce(into: Data()) { data, character in
        data.append(otherControlLittleEndianData(character))
    }
}
