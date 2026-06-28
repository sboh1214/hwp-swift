@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoTopLevelTrackChangeTests: XCTestCase {
    func testDocInfoPreservesMultipleTopLevelTrackChangeRecordsInOrder() throws {
        let firstPayload = Data([0x10, 0x11])
        let secondPayload = Data([0x20, 0x21])
        let firstChildPayload = Data([0x12])
        let secondChildPayload = Data([0x22])

        var data = topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: topLevelTrackChangeDocumentPropertiesPayload()
        )
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: topLevelTrackChangeIdMappingsPayload()
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: firstPayload
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: 0x301,
            level: 1,
            payload: firstChildPayload
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: secondPayload
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: 0x302,
            level: 1,
            payload: secondChildPayload
        ))

        let docInfo = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.topLevelTrackChangeArray.map(\.rawPayload)) == [
            firstPayload,
            secondPayload,
        ]
        expect(docInfo.trackChangeArray.map(\.rawPayload)) == [firstPayload, secondPayload]
        expect(docInfo.topLevelTrackChangeArray.map(\.unknownChildren)) == [
            [expectedTestUnknownRecord(tagId: 0x301, level: 1, payload: firstChildPayload)],
            [expectedTestUnknownRecord(tagId: 0x302, level: 1, payload: secondChildPayload)],
        ]
        expect(docInfo.unknownRecords).to(beEmpty())
    }

    func testDocInfoSeparatesTopLevelTrackChangesFromIdMappingsAggregate() throws {
        let idMappingTrackPayload = Data([0xA0, 0xA1])
        let topLevelPayload = Data([0xB0, 0xB1])
        var data = topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: topLevelTrackChangeDocumentPropertiesPayload()
        )
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: topLevelTrackChangeIdMappingsPayload()
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 1,
            payload: idMappingTrackPayload
        ))
        data.append(topLevelTrackChangeRecordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: topLevelPayload
        ))

        let docInfo = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.idMappings.trackChangeArray.map(\.rawPayload)) == [idMappingTrackPayload]
        expect(docInfo.topLevelTrackChangeArray.map(\.rawPayload)) == [topLevelPayload]
        expect(docInfo.trackChangeArray.map(\.rawPayload)) == [
            idMappingTrackPayload,
            topLevelPayload,
        ]
        expect(docInfo.unknownRecords).to(beEmpty())
    }
}

private func topLevelTrackChangeDocumentPropertiesPayload() -> Data {
    topLevelTrackChangeLittleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func topLevelTrackChangeIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(topLevelTrackChangeLittleEndianData(count))
    }
}

private func topLevelTrackChangeRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = topLevelTrackChangeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func topLevelTrackChangeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
