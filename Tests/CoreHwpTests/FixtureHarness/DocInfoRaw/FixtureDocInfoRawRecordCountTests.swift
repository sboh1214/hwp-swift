@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixtureDocInfoRawRecordCountTests: XCTestCase {
    func testRawDocInfoRecordCountDoesNotCountIdMappingTrackChanges() throws {
        let idMappingPayload = Data([0xA0, 0xA1, 0xA2, 0xA3])
        let topLevelPayload = Data([0xB0, 0xB1, 0xB2, 0xB3])
        let docInfo = try HwpDocInfo.load(
            rawRecordCountDocInfoData(
                idMappingTrackChangePayload: idMappingPayload,
                topLevelTrackChangePayload: topLevelPayload
            ),
            HwpVersion(5, 0, 3, 2)
        )

        expect(docInfo.idMappings.trackChangeArray.map(\.rawPayload)) == [idMappingPayload]
        expect(docInfo.topLevelTrackChangeArray.map(\.rawPayload)) == [topLevelPayload]
        expect(docInfo.trackChangeArray.map(\.rawPayload)) == [
            idMappingPayload,
            topLevelPayload,
        ]
        expect(FixtureAssertions.rawDocInfoRecordCount(docInfo)) == 1
    }

    func testRawDocInfoRecordCountIncludesIdMappingMemoContentAndAuthorRecords() throws {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = 1
        counts[16] = 1
        counts[17] = 1
        let memoPayload = Data([0xC0, 0xC1])
        let contentPayload = Data([0xD0, 0xD1])
        let authorPayload = Data([0xE0, 0xE1])
        let docInfo = try HwpDocInfo.load(
            rawRecordCountDocInfoData(
                idMappingCounts: counts,
                idMappingChildren: [
                    rawRecordCountRecordData(
                        tagId: HwpDocInfoTag.memoShape.rawValue,
                        level: 1,
                        payload: memoPayload
                    ),
                    rawRecordCountRecordData(
                        tagId: HwpDocInfoTag.trackChangeContent.rawValue,
                        level: 1,
                        payload: contentPayload
                    ),
                    rawRecordCountRecordData(
                        tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
                        level: 1,
                        payload: authorPayload
                    ),
                ]
            ),
            HwpVersion(5, 0, 3, 2)
        )

        expect(docInfo.idMappings.memoShapeArray.map(\.rawPayload)) == [memoPayload]
        expect(docInfo.idMappings.trackChangeContentArray.map(\.rawPayload)) == [
            contentPayload,
        ]
        expect(docInfo.idMappings.trackChangeAuthorArray.map(\.rawPayload)) == [
            authorPayload,
        ]
        expect(FixtureAssertions.rawDocInfoRecordCount(docInfo)) == 3
    }
}

private func rawRecordCountDocInfoData(
    idMappingTrackChangePayload: Data,
    topLevelTrackChangePayload: Data
) -> Data {
    rawRecordCountRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: rawRecordCountDocumentPropertiesPayload()
    )
        + rawRecordCountRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: rawRecordCountIdMappingsPayload()
        )
        + rawRecordCountRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 1,
            payload: idMappingTrackChangePayload
        )
        + rawRecordCountRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: topLevelTrackChangePayload
        )
}

private func rawRecordCountDocInfoData(
    idMappingCounts: [Int32],
    idMappingChildren: [Data]
) -> Data {
    rawRecordCountRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: rawRecordCountDocumentPropertiesPayload()
    )
        + rawRecordCountRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: rawRecordCountIdMappingsPayload(idMappingCounts)
        )
        + idMappingChildren.reduce(into: Data()) { data, child in
            data.append(child)
        }
}

private func rawRecordCountDocumentPropertiesPayload() -> Data {
    rawRecordCountLittleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func rawRecordCountIdMappingsPayload(
    _ counts: [Int32] = Array(repeating: Int32(0), count: 18)
) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(rawRecordCountLittleEndianData(count))
    }
}

private func rawRecordCountRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = rawRecordCountLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func rawRecordCountLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
