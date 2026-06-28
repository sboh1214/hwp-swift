@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable file_length
// swiftlint:disable type_body_length
final class DocInfoStabilityTests: XCTestCase {
    func testIdMappingsRecordCountMismatchThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[0] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("exceeds available child records"))
        })
    }

    func testIdMappingsChildTagMismatchThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[0] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.faceName.rawValue, level: 1, payload: Data()),
        ]

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("expected DocInfo tag \(HwpDocInfoTag.binData.rawValue)"))
            expect(reason).to(contain("got \(HwpDocInfoTag.faceName.rawValue)"))
        })
    }

    func testIdMappingsCountedOptionalRecordMismatchThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = 2
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.memoShape.rawValue, level: 1, payload: Data([0x01])),
        ]

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("expected 2 tag"))
            expect(reason).to(contain("got 1"))
        })
    }

    func testIdMappingsPreservesUnknownChildrenAndForbiddenChar() throws {
        let forbiddenPayload = Data([0x01, 0x02, 0x03])
        let forbiddenChildPayload = Data([0x04, 0x05])
        let unknownPayload = Data([0xAA, 0xBB])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload()
        )
        let forbiddenRecord = HwpRecord(
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            level: 1,
            payload: forbiddenPayload
        )
        forbiddenRecord.children = [
            HwpRecord(tagId: 0x2ED, level: 2, payload: forbiddenChildPayload),
        ]
        record.children = [
            forbiddenRecord,
            HwpRecord(tagId: 0x2EF, level: 1, payload: unknownPayload),
        ]

        let idMappings = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))

        expect(idMappings.forbiddenCharArray.map(\.data)) == [forbiddenPayload]
        expect(idMappings.forbiddenCharArray.map(\.rawPayload)) == [forbiddenPayload]
        expect(idMappings.forbiddenCharArray.first?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2ED, level: 2, payload: forbiddenChildPayload),
        ]
        expect(idMappings.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2EF, level: 1, payload: unknownPayload),
        ]
    }

    func testIdMappingsConsumesCountedMemoShapeAndTrackChangeRecords() throws {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = 2
        counts[16] = 2
        counts[17] = 1
        let memoPayloads = [Data([0x01]), Data([0x02])]
        let trackChangePayload = Data([0x03])
        let trackChangeAuthorPayload = Data([0x04])
        let trackChangeContentPayloads = [Data([0x05]), Data([0x06])]
        let unknownPayload = Data([0x07])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.memoShape.rawValue, level: 1, payload: memoPayloads[0]),
            HwpRecord(tagId: HwpDocInfoTag.memoShape.rawValue, level: 1, payload: memoPayloads[1]),
            HwpRecord(
                tagId: HwpDocInfoTag.trackChange.rawValue,
                level: 1,
                payload: trackChangePayload
            ),
            HwpRecord(
                tagId: HwpDocInfoTag.trackChangeContent.rawValue,
                level: 1,
                payload: trackChangeContentPayloads[0]
            ),
            HwpRecord(
                tagId: HwpDocInfoTag.trackChangeContent.rawValue,
                level: 1,
                payload: trackChangeContentPayloads[1]
            ),
            HwpRecord(
                tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
                level: 1,
                payload: trackChangeAuthorPayload
            ),
            HwpRecord(tagId: 0x2EF, level: 1, payload: unknownPayload),
        ]

        let idMappings = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))

        expect(idMappings.memoShapeCount) == 2
        expect(idMappings.changeTraceCount) == 2
        expect(idMappings.changeTraceUserCount) == 1
        expect(idMappings.memoShapeArray.map(\.rawPayload)) == memoPayloads
        expect(idMappings.trackChangeArray.map(\.rawPayload)) == [trackChangePayload]
        expect(idMappings.trackChangeContentArray.map(\.rawPayload)) == trackChangeContentPayloads
        expect(idMappings.trackChangeAuthorArray.map(\.rawPayload)) == [trackChangeAuthorPayload]
        expect(idMappings.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2EF, level: 1, payload: unknownPayload),
        ]
    }

    func testIdMappingsConsumesLegacyMemoShapeRecords() throws {
        var counts = Array(repeating: Int32(0), count: 16)
        counts[15] = 1
        let memoPayload = Data([0xAA, 0xBB])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.memoShape.rawValue, level: 1, payload: memoPayload),
        ]

        let idMappings = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 0))

        expect(idMappings.memoShapeCount) == 1
        expect(idMappings.changeTraceCount).to(beNil())
        expect(idMappings.changeTraceUserCount).to(beNil())
        expect(idMappings.memoShapeArray.map(\.rawPayload)) == [memoPayload]
        expect(idMappings.unknownChildren).to(beEmpty())
    }

    func testDocInfoExposesIdMappingMemoShapeRecords() throws {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = 1
        counts[16] = 1
        let memoPayload = Data([0xCA, 0xFE])
        let trackChangeContentPayload = Data([0xBA, 0xBE])
        var data = recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: documentPropertiesPayload()
        )
        data.append(recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(counts)
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            level: 1,
            payload: memoPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 1,
            payload: trackChangeContentPayload
        ))

        let docInfo = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))
        var sameDocInfo = docInfo
        sameDocInfo.rawPayload = Data([0xFF])

        expect(docInfo.rawPayload) == data
        expect(docInfo.idMappings.memoShapeArray.map(\.rawPayload)) == [memoPayload]
        expect(docInfo.idMappings.trackChangeContentArray.map(\.rawPayload)) == [
            trackChangeContentPayload,
        ]
        expect(docInfo.memoShapeArray.map(\.rawPayload)) == [memoPayload]
        expect(docInfo.trackChangeContentArray.map(\.rawPayload)) == [trackChangeContentPayload]
        expect(docInfo.unknownRecords).to(beEmpty())
        expect(sameDocInfo) == docInfo
    }

    func testDocInfoRawRecordsPreservePayloadFromFixture() throws {
        let hwp = try openHwp(#file, "noori")
        expect(hwp.docInfo.rawPayload).notTo(beEmpty())

        let rawPayloads = [
            hwp.docInfo.docData?.rawPayload,
            hwp.docInfo.distributeDocData?.rawPayload,
        ]
        .compactMap { $0 }
        + hwp.docInfo.trackChangeArray.map(\.rawPayload)
        + hwp.docInfo.memoShapeArray.map(\.rawPayload)
        + hwp.docInfo.trackChangeContentArray.map(\.rawPayload)
        + hwp.docInfo.trackChangeAuthorArray.map(\.rawPayload)

        expect(rawPayloads).notTo(beEmpty())
        expect(rawPayloads.contains { !$0.isEmpty }) == true
    }

    func testDocInfoRawRecordModelsPreserveUnknownChildren() throws {
        let child = HwpRecord(tagId: 0x301, level: 1, payload: Data([0xCC]))
        let payload = Data([0xAA, 0xBB])

        let distribute = try HwpDistributeDocData.load(rawRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            payload: payload,
            children: [child]
        ))
        let trackChange = try HwpTrackChange.load(rawRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            payload: payload,
            children: [child]
        ))
        let memoShape = try HwpMemoShape.load(rawRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            payload: payload,
            children: [child]
        ))
        let trackChangeContent = try HwpTrackChangeContent.load(rawRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            payload: payload,
            children: [child]
        ))
        let trackChangeAuthor = try HwpTrackChangeAuthor.load(rawRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            payload: payload,
            children: [child]
        ))
        let forbiddenChar = try HwpForbiddenChar.load(payload)
        var sameForbiddenChar = forbiddenChar
        sameForbiddenChar.rawPayload = Data([0xFF])

        let expectedChild = expectedTestUnknownRecord(
            tagId: 0x301,
            level: 1,
            payload: Data([0xCC])
        )
        expect(distribute.unknownChildren) == [expectedChild]
        expect(trackChange.unknownChildren) == [expectedChild]
        expect(memoShape.unknownChildren) == [expectedChild]
        expect(trackChangeContent.unknownChildren) == [expectedChild]
        expect(trackChangeAuthor.unknownChildren) == [expectedChild]
        expect(forbiddenChar.data) == payload
        expect(forbiddenChar.rawPayload) == payload
        expect(sameForbiddenChar) == forbiddenChar
    }

    // swiftlint:disable:next function_body_length
    func testDocInfoKnownRawRecordsAreTypedAndPreservePayload() throws {
        let docDataPayload = Data([0x01, 0x02])
        let docDataForbiddenPayload = Data([0x03])
        let docDataUnknownPayload = Data([0x13])
        let duplicateDocumentPropertiesPayload = Data([0x0B])
        let duplicateDocDataPayload = Data([0x0C, 0x0D])
        let duplicateDocDataChildPayload = Data([0x0E])
        let distributePayload = Data([0x04])
        let distributeChildPayload = Data([0x14])
        let trackChangePayload = Data([0x05])
        let trackChangeChildPayload = Data([0x15])
        let compatibleTrackChangePayload = Data([0x10])
        let memoShapePayload = Data([0x06])
        let trackChangeContentPayload = Data([0x07])
        let trackChangeAuthorPayload = Data([0x08])
        let topLevelForbiddenPayload = Data([0x11])
        let topLevelForbiddenChildPayload = Data([0x12])
        let unknownPayload = Data([0x09])
        let compatibleUnknownPayload = Data([0x0A])
        let duplicateLayoutPayload = littleEndianData(UInt32(6))
            + littleEndianData(UInt32(7))
            + littleEndianData(UInt32(8))
            + littleEndianData(UInt32(9))
            + littleEndianData(UInt32(10))
        let duplicateLayoutChildPayload = Data([0x0F])
        let layoutPayload = littleEndianData(UInt32(1))
            + littleEndianData(UInt32(2))
            + littleEndianData(UInt32(3))
            + littleEndianData(UInt32(4))
            + littleEndianData(UInt32(5))

        var data = recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: documentPropertiesPayload()
        )
        data.append(recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload()
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: duplicateDocumentPropertiesPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: docDataPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            level: 1,
            payload: docDataForbiddenPayload
        ))
        data.append(recordData(tagId: 0x201, level: 1, payload: docDataUnknownPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.docData.rawValue,
            level: 0,
            payload: duplicateDocDataPayload
        ))
        data.append(recordData(tagId: 0x203, level: 1, payload: duplicateDocDataChildPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            level: 0,
            payload: distributePayload
        ))
        data.append(recordData(tagId: 0x205, level: 1, payload: distributeChildPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.compatibleDocument.rawValue,
            level: 0,
            payload: littleEndianData(UInt32(0))
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
            level: 1,
            payload: layoutPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
            level: 1,
            payload: duplicateLayoutPayload
        ))
        data.append(recordData(tagId: 0x204, level: 2, payload: duplicateLayoutChildPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 1,
            payload: compatibleTrackChangePayload
        ))
        data.append(recordData(tagId: 0x202, level: 1, payload: compatibleUnknownPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: trackChangePayload
        ))
        data.append(recordData(tagId: 0x206, level: 1, payload: trackChangeChildPayload))
        data.append(recordData(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            level: 0,
            payload: memoShapePayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: trackChangeContentPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: trackChangeAuthorPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            level: 0,
            payload: topLevelForbiddenPayload
        ))
        data.append(recordData(tagId: 0x207, level: 1, payload: topLevelForbiddenChildPayload))
        data.append(recordData(tagId: 0x2EE, level: 0, payload: unknownPayload))

        let docInfo = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.docData?.rawPayload) == docDataPayload
        expect(docInfo.docData?.forbiddenCharArray.map(\.data)) == [docDataForbiddenPayload]
        expect(docInfo.docData?.forbiddenCharArray.map(\.rawPayload)) == [
            docDataForbiddenPayload,
        ]
        expect(docInfo.docData?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x201, level: 1, payload: docDataUnknownPayload),
        ]
        expect(docInfo.distributeDocData?.rawPayload) == distributePayload
        expect(docInfo.distributeDocData?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x205, level: 1, payload: distributeChildPayload),
        ]
        expect(docInfo.compatibleDocument?.rawPayload) == littleEndianData(UInt32(0))
        expect(docInfo.compatibleDocument?.targetDocumentRawPayload) == littleEndianData(UInt32(0))
        expect(docInfo.compatibleDocument?.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
                level: 1,
                payload: duplicateLayoutPayload,
                children: [
                    expectedTestRecord(
                        tagId: 0x204,
                        level: 2,
                        payload: duplicateLayoutChildPayload
                    ),
                ]
            ),
            expectedTestUnknownRecord(tagId: 0x202, level: 1, payload: compatibleUnknownPayload),
        ]
        expect(docInfo.compatibleDocument?.trackChangeArray.map(\.rawPayload)) == [
            compatibleTrackChangePayload,
        ]
        expect(docInfo.layoutCompatibility?.field) == 5
        expect(docInfo.layoutCompatibility?.rawPayload) == layoutPayload
        expect(docInfo.layoutCompatibility?.fixedFieldsRawPayload) == layoutPayload
        expect(docInfo.topLevelTrackChangeArray.map(\.rawPayload)) == [trackChangePayload]
        expect(docInfo.trackChangeArray.map(\.rawPayload)) == [trackChangePayload]
        expect(docInfo.topLevelTrackChangeArray.first?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x206, level: 1, payload: trackChangeChildPayload),
        ]
        expect(docInfo.memoShapeArray.map(\.rawPayload)) == [memoShapePayload]
        expect(docInfo.trackChangeContentArray.map(\.rawPayload)) == [trackChangeContentPayload]
        expect(docInfo.trackChangeAuthorArray.map(\.rawPayload)) == [trackChangeAuthorPayload]
        expect(docInfo.topLevelForbiddenCharArray.map(\.rawPayload)) == [topLevelForbiddenPayload]
        expect(docInfo.topLevelForbiddenCharArray.first?.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x207,
                level: 1,
                payload: topLevelForbiddenChildPayload
            ),
        ]
        expect(docInfo.forbiddenCharArray.map(\.rawPayload)) == [
            docDataForbiddenPayload,
            topLevelForbiddenPayload,
        ]
        expect(docInfo.unknownRecords) == [
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.documentProperties.rawValue,
                level: 0,
                payload: duplicateDocumentPropertiesPayload
            ),
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.docData.rawValue,
                level: 0,
                payload: duplicateDocDataPayload,
                children: [
                    expectedTestRecord(
                        tagId: 0x203,
                        level: 1,
                        payload: duplicateDocDataChildPayload
                    ),
                ]
            ),
            expectedTestUnknownRecord(tagId: 0x2EE, level: 0, payload: unknownPayload),
        ]
    }
}

// swiftlint:enable type_body_length

private func documentPropertiesPayload() -> Data {
    littleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func idMappingsPayload(_ counts: [Int32] = Array(repeating: Int32(0), count: 18)) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(littleEndianData(count))
    }
}

private func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = littleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func rawRecord(tagId: UInt32, payload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: 0, payload: payload)
    record.children = children
    return record
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

// swiftlint:enable file_length
