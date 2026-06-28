@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class IdMappingsUnknownInterleavingTests: XCTestCase {
    func testUnknownChildrenInterleavedBeforeCountedRecordsArePreserved() throws {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[0] = 1
        counts[1] = 1
        let unknownBeforePayload = Data([0xA1])
        let unknownBetweenPayload = Data([0xA2])
        let binDataPayload = binDataEmbeddingPayload(streamId: 7, extensionName: "png")
        let extraBinDataPayload = binDataEmbeddingPayload(streamId: 8, extensionName: "gif")
        let extraBinDataChildPayload = Data([0xB1, 0xB2])
        let faceNamePayload = faceNamePayload("CoreHwp")
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        let extraBinDataRecord = HwpRecord(
            tagId: HwpDocInfoTag.binData.rawValue,
            level: 1,
            payload: extraBinDataPayload
        )
        extraBinDataRecord.children = [
            HwpRecord(tagId: 0x2ED, level: 2, payload: extraBinDataChildPayload),
        ]
        record.children = [
            HwpRecord(tagId: 0x2EF, level: 1, payload: unknownBeforePayload),
            HwpRecord(tagId: HwpDocInfoTag.binData.rawValue, level: 1, payload: binDataPayload),
            HwpRecord(tagId: 0x2EE, level: 1, payload: unknownBetweenPayload),
            extraBinDataRecord,
            HwpRecord(tagId: HwpDocInfoTag.faceName.rawValue, level: 1, payload: faceNamePayload),
        ]

        let idMappings = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))

        expect(idMappings.binDataArray.map(\.rawPayload)) == [binDataPayload]
        expect(idMappings.binDataArray.map(\.streamId)) == [7]
        expect(idMappings.faceNameKoreanArray.map(\.faceName)) == ["CoreHwp"]
        expect(idMappings.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2EF, level: 1, payload: unknownBeforePayload),
            expectedTestUnknownRecord(tagId: 0x2EE, level: 1, payload: unknownBetweenPayload),
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.binData.rawValue,
                level: 1,
                payload: extraBinDataPayload,
                children: [
                    expectedTestRecord(tagId: 0x2ED, level: 2, payload: extraBinDataChildPayload),
                ]
            ),
        ]
    }

    func testReservedChildInterleavedBeforeCountedRecordsIsPreserved() throws {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[0] = 1
        counts[1] = 1
        let reservedPayload = Data([0x29, 0x00])
        let reservedChildPayload = Data([0xA9])
        let binDataPayload = binDataEmbeddingPayload(streamId: 9, extensionName: "bmp")
        let faceNamePayload = faceNamePayload("Reserved")
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        let reservedRecord = HwpRecord(
            tagId: HwpDocInfoTag.reserved.rawValue,
            level: 1,
            payload: reservedPayload
        )
        reservedRecord.children = [
            HwpRecord(tagId: 0x2F9, level: 2, payload: reservedChildPayload),
        ]
        record.children = [
            reservedRecord,
            HwpRecord(tagId: HwpDocInfoTag.binData.rawValue, level: 1, payload: binDataPayload),
            HwpRecord(tagId: HwpDocInfoTag.faceName.rawValue, level: 1, payload: faceNamePayload),
        ]

        let idMappings = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))

        expect(idMappings.binDataArray.map(\.streamId)) == [9]
        expect(idMappings.faceNameKoreanArray.map(\.faceName)) == ["Reserved"]
        expect(idMappings.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.reserved.rawValue,
                level: 1,
                payload: reservedPayload,
                children: [
                    expectedTestRecord(tagId: 0x2F9, level: 2, payload: reservedChildPayload),
                ]
            ),
        ]
    }

    func testExtraOptionalKnownRawRecordsArePreservedAsUnknownChildren() throws {
        let fixture = ExtraOptionalKnownRawRecordsFixture()

        let idMappings = try HwpIdMappings.load(fixture.record, HwpVersion(5, 0, 3, 2))

        expect(idMappings.memoShapeArray.map(\.rawPayload)) == [fixture.consumedMemoPayload]
        expect(idMappings.trackChangeContentArray.map(\.rawPayload)) == [
            fixture.consumedContentPayload,
        ]
        expect(idMappings.trackChangeAuthorArray.map(\.rawPayload)) == [
            fixture.consumedAuthorPayload,
        ]
        expect(idMappings.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.memoShape.rawValue,
                level: 1,
                payload: fixture.extraMemoPayload
            ),
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.trackChangeContent.rawValue,
                level: 1,
                payload: fixture.extraContentPayload
            ),
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
                level: 1,
                payload: fixture.extraAuthorPayload,
                children: [
                    expectedTestRecord(
                        tagId: 0x2FD,
                        level: 2,
                        payload: fixture.extraAuthorChildPayload
                    ),
                ]
            ),
        ]
    }
}

private struct ExtraOptionalKnownRawRecordsFixture {
    let consumedMemoPayload = Data([0x11])
    let extraMemoPayload = Data([0x12])
    let consumedContentPayload = Data([0x21])
    let extraContentPayload = Data([0x22])
    let consumedAuthorPayload = Data([0x31])
    let extraAuthorPayload = Data([0x32])
    let extraAuthorChildPayload = Data([0xAA])

    var record: HwpRecord {
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        record.children = [
            docInfoChild(.memoShape, consumedMemoPayload),
            docInfoChild(.memoShape, extraMemoPayload),
            docInfoChild(.trackChangeContent, consumedContentPayload),
            docInfoChild(.trackChangeContent, extraContentPayload),
            docInfoChild(.trackChangeAuthor, consumedAuthorPayload),
            extraAuthorRecord,
        ]
        return record
    }

    private var counts: [Int32] {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = 1
        counts[16] = 1
        counts[17] = 1
        return counts
    }

    private var extraAuthorRecord: HwpRecord {
        let record = docInfoChild(.trackChangeAuthor, extraAuthorPayload)
        record.children = [
            HwpRecord(tagId: 0x2FD, level: 2, payload: extraAuthorChildPayload),
        ]
        return record
    }
}

private func docInfoChild(_ tag: HwpDocInfoTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 1, payload: payload)
}

private func idMappingsPayload(_ counts: [Int32]) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(littleEndianData(count))
    }
}

private func binDataEmbeddingPayload(streamId: UInt16, extensionName: String) -> Data {
    let property = UInt16(HwpBinDataType.embedding.rawValue)
        | UInt16(HwpBinDataCompressType.never.rawValue << 4)
        | UInt16(HwpBinDataState.successed.rawValue << 6)
    return littleEndianData(property)
        + littleEndianData(streamId)
        + lengthPrefixedUTF16Data(extensionName)
}

private func faceNamePayload(_ name: String) -> Data {
    Data([0]) + lengthPrefixedUTF16Data(name)
}

private func lengthPrefixedUTF16Data(_ string: String) -> Data {
    var data = littleEndianData(UInt16(string.utf16.count))
    for character in string.utf16 {
        data.append(littleEndianData(character))
    }
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
