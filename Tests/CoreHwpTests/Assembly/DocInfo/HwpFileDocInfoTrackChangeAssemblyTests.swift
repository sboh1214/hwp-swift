@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileDocInfoTrackChangeAssemblyTests: XCTestCase {
    func testActualFixtureBasedTopLevelTrackChangeContentAndAuthorSurviveCodableRoundTrip()
        throws
    {
        let streams = try trackChangeDocInfoAssemblyStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.trackChangeContentArray).to(beEmpty())
        expect(baseDocInfo.trackChangeAuthorArray).to(beEmpty())

        let injected = InjectedTrackChangeDocInfo(
            baseDocInfoData: streams.docInfoData
        )
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectTopLevelTrackChangeDocInfoRecords(in: hwp.docInfo, match: injected)
        expectTopLevelTrackChangeDocInfoRecords(in: decoded.docInfo, match: injected)
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }
}

private struct TrackChangeDocInfoAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedTrackChangeDocInfo {
    let docInfoData: Data
    let contentPayload: Data
    let contentChildPayload: Data
    let contentGrandchildPayload: Data
    let authorPayload: Data
    let authorNamePayload: Data
    let authorTrailingPayload: Data
    let authorChildPayload: Data
    let authorGrandchildPayload: Data

    init(baseDocInfoData: Data) {
        contentPayload = trackChangeContentPayload(
            kind: 31,
            timestamp: TrackChangeTimestamp(2026, 6, 26, 22, 38),
            rawTrailing: Data([0xC1, 0xC2, 0xC3])
        )
        contentChildPayload = Data([0xD1, 0xD2])
        contentGrandchildPayload = Data([0xD3])
        authorTrailingPayload = Data([0xA1, 0xA2, 0xA3])
        authorPayload = trackChangeAuthorPayload(
            name: "Injected Author",
            rawTrailing: authorTrailingPayload
        )
        authorNamePayload = trackChangeAuthorNamePayload("Injected Author")
        authorChildPayload = Data([0xE1, 0xE2])
        authorGrandchildPayload = Data([0xE3])

        docInfoData = baseDocInfoData
            + trackChangeDocInfoRecordData(
                tagId: HwpDocInfoTag.trackChangeContent.rawValue,
                level: 0,
                payload: contentPayload
            )
            + trackChangeDocInfoRecordData(
                tagId: 0x320,
                level: 1,
                payload: contentChildPayload
            )
            + trackChangeDocInfoRecordData(
                tagId: 0x321,
                level: 2,
                payload: contentGrandchildPayload
            )
            + trackChangeDocInfoRecordData(
                tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
                level: 0,
                payload: authorPayload
            )
            + trackChangeDocInfoRecordData(
                tagId: 0x322,
                level: 1,
                payload: authorChildPayload
            )
            + trackChangeDocInfoRecordData(
                tagId: 0x323,
                level: 2,
                payload: authorGrandchildPayload
            )
    }
}

private struct TrackChangeTimestamp {
    let year: UInt16
    let month: UInt16
    let day: UInt16
    let hour: UInt16
    let minute: UInt16

    var values: [UInt16] {
        [year, month, day, hour, minute]
    }

    init(
        _ year: UInt16,
        _ month: UInt16,
        _ day: UInt16,
        _ hour: UInt16,
        _ minute: UInt16
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }
}

private func trackChangeDocInfoAssemblyStreams(
    fromFixture id: String
) throws -> TrackChangeDocInfoAssemblyStreams {
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

    return TrackChangeDocInfoAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectTopLevelTrackChangeDocInfoRecords(
    in docInfo: HwpDocInfo,
    match injected: InjectedTrackChangeDocInfo
) {
    expect(docInfo.idMappings.trackChangeContentArray).to(beEmpty())
    expect(docInfo.idMappings.trackChangeAuthorArray).to(beEmpty())
    expectTrackChangeContentRecords(in: docInfo, match: injected)
    expectTrackChangeAuthorRecords(in: docInfo, match: injected)
}

private func expectTrackChangeContentRecords(
    in docInfo: HwpDocInfo,
    match injected: InjectedTrackChangeDocInfo
) {
    expect(docInfo.trackChangeContentArray.map(\.rawPayload)) == [
        injected.contentPayload,
    ]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.kind)) == [31]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.year)) == [2026]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.month)) == [6]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.day)) == [26]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.hour)) == [22]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.minute)) == [38]
    expect(docInfo.trackChangeContentArray.map(\.contentInfo?.rawTrailing)) == [
        Data([0xC1, 0xC2, 0xC3]),
    ]
    expect(docInfo.trackChangeContentArray.map(\.unknownChildren)) == [
        [
            trackChangeExpectedUnknownRecord(
                tagId: 0x320,
                level: 1,
                payload: injected.contentChildPayload,
                children: [
                    trackChangeExpectedRecord(
                        tagId: 0x321,
                        level: 2,
                        payload: injected.contentGrandchildPayload
                    ),
                ]
            ),
        ],
    ]
}

private func expectTrackChangeAuthorRecords(
    in docInfo: HwpDocInfo,
    match injected: InjectedTrackChangeDocInfo
) {
    expect(docInfo.trackChangeAuthorArray.map(\.rawPayload)) == [
        injected.authorPayload,
    ]
    expect(docInfo.trackChangeAuthorArray.map(\.authorInfo?.name)) == ["Injected Author"]
    expect(docInfo.trackChangeAuthorArray.map(\.authorInfo?.nameRawPayload)) == [
        injected.authorNamePayload,
    ]
    expect(docInfo.trackChangeAuthorArray.map(\.authorInfo?.rawTrailing)) == [
        injected.authorTrailingPayload,
    ]
    expect(docInfo.trackChangeAuthorArray.map(\.unknownChildren)) == [
        [
            trackChangeExpectedUnknownRecord(
                tagId: 0x322,
                level: 1,
                payload: injected.authorChildPayload,
                children: [
                    trackChangeExpectedRecord(
                        tagId: 0x323,
                        level: 2,
                        payload: injected.authorGrandchildPayload
                    ),
                ]
            ),
        ],
    ]
}

private func trackChangeContentPayload(
    kind: UInt32,
    timestamp: TrackChangeTimestamp,
    rawTrailing: Data
) -> Data {
    var payload = trackChangeLittleEndianData(kind)
    for value in timestamp.values {
        payload.append(trackChangeLittleEndianData(value))
    }
    payload.append(rawTrailing)
    return payload
}

private func trackChangeAuthorPayload(name: String, rawTrailing: Data) -> Data {
    var payload = trackChangeLittleEndianData(UInt32(name.utf16.count))
    payload.append(trackChangeAuthorNamePayload(name))
    payload.append(rawTrailing)
    return payload
}

private func trackChangeAuthorNamePayload(_ name: String) -> Data {
    name.utf16.reduce(into: Data()) { data, codeUnit in
        data.append(trackChangeLittleEndianData(WCHAR(codeUnit)))
    }
}

private func trackChangeDocInfoRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = trackChangeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func trackChangeExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        trackChangeExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func trackChangeExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func trackChangeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
