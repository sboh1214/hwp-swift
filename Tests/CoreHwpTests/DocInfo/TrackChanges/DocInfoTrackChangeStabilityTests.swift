// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class DocInfoTrackChangeStabilityTests: XCTestCase {
    func testTrackChangeExposesHeaderAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0x01, 0x00, 0xAA, 0xBB])
        let payload = littleEndianData(UInt32(56)) + rawTrailing
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: payload
        )

        let trackChange = try HwpTrackChange.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChange.self,
            from: JSONEncoder().encode(trackChange)
        )

        expect(trackChange.trackChangeInfo?.headerValue) == 56
        expect(trackChange.trackChangeInfo?.headerRawPayload) == littleEndianData(UInt32(56))
        expect(trackChange.trackChangeInfo?.rawTrailing) == rawTrailing
        expect(trackChange.rawPayload) == payload
        expect(decoded.trackChangeInfo?.headerValue) == 56
        expect(decoded.trackChangeInfo?.headerRawPayload) == littleEndianData(UInt32(56))
        expect(decoded.trackChangeInfo?.rawTrailing) == rawTrailing
        expect(decoded.rawPayload) == payload
    }

    func testMalformedTrackChangePayloadIsPreservedWithoutParsedInfo() throws {
        let payload = Data([0x38, 0x00, 0x00])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: payload
        )

        let trackChange = try HwpTrackChange.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChange.self,
            from: JSONEncoder().encode(trackChange)
        )

        expect(trackChange.trackChangeInfo).to(beNil())
        expect(trackChange.rawPayload) == payload
        expect(decoded.trackChangeInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testTrackChangePayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawTrailing = Data([0xCC, 0xDD])
        let payload = littleEndianData(UInt32(56)) + rawTrailing
        let paddedPayload = Data([0xAA, 0xBB]) + payload
        let slicedPayload = paddedPayload.dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let trackChange = try HwpTrackChange.load(record)

        expect(trackChange.trackChangeInfo?.headerValue) == 56
        expect(trackChange.trackChangeInfo?.headerRawPayload) == littleEndianData(UInt32(56))
        expect(trackChange.trackChangeInfo?.rawTrailing) == rawTrailing
        expect(trackChange.rawPayload) == slicedPayload
    }

    func testTrackChangeContentExposesKindTimestampAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0x01, 0x00, 0xAA, 0xBB])
        let payload = trackChangeContentPayload(
            kind: 17,
            timestamp: TrackChangeContentTimestamp(2026, 6, 15, 4, 30),
            rawTrailing: rawTrailing
        )
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: payload
        )

        let content = try HwpTrackChangeContent.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeContent.self,
            from: JSONEncoder().encode(content)
        )

        assertTrackChangeContent(
            content,
            kind: 17,
            timestamp: TrackChangeContentTimestamp(2026, 6, 15, 4, 30),
            rawTrailing: rawTrailing,
            rawPayload: payload
        )
        assertTrackChangeContent(
            decoded,
            kind: 17,
            timestamp: TrackChangeContentTimestamp(2026, 6, 15, 4, 30),
            rawTrailing: rawTrailing,
            rawPayload: payload
        )
    }

    func testMalformedTrackChangeContentPayloadIsPreservedWithoutParsedInfo() throws {
        let payload = littleEndianData(UInt32(17)) + littleEndianData(UInt16(2026))
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: payload
        )

        let content = try HwpTrackChangeContent.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeContent.self,
            from: JSONEncoder().encode(content)
        )

        expect(content.contentInfo).to(beNil())
        expect(content.rawPayload) == payload
        expect(decoded.contentInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testMalformedTrackChangeRawRecordsPreserveUnknownChildren() throws {
        let contentPayload = Data([0x11, 0x22])
        let contentChildPayload = Data([0xC0, 0xC1])
        let contentRecord = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: contentPayload
        )
        contentRecord.children = [
            HwpRecord(tagId: 0x301, level: 1, payload: contentChildPayload),
        ]

        let authorPayload = Data([0x33, 0x44, 0x55])
        let authorChildPayload = Data([0xA0, 0xA1, 0xA2])
        let authorRecord = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: authorPayload
        )
        authorRecord.children = [
            HwpRecord(tagId: 0x302, level: 1, payload: authorChildPayload),
        ]

        let content = try HwpTrackChangeContent.load(contentRecord)
        let author = try HwpTrackChangeAuthor.load(authorRecord)

        expect(content.contentInfo).to(beNil())
        expect(content.rawPayload) == contentPayload
        expect(content.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x301, level: 1, payload: contentChildPayload),
        ]
        expect(author.authorInfo).to(beNil())
        expect(author.rawPayload) == authorPayload
        expect(author.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x302, level: 1, payload: authorChildPayload),
        ]
    }

    func testTrackChangeContentPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let payload = trackChangeContentPayload(
            kind: 16,
            timestamp: TrackChangeContentTimestamp(2026, 6, 15, 4, 31)
        )
        let paddedPayload = Data([0xAA, 0xBB]) + payload
        let slicedPayload = paddedPayload.dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let content = try HwpTrackChangeContent.load(record)

        assertTrackChangeContent(
            content,
            kind: 16,
            timestamp: TrackChangeContentTimestamp(2026, 6, 15, 4, 31),
            rawTrailing: Data(repeating: 0, count: 12),
            rawPayload: slicedPayload
        )
    }

    func testTrackChangeAuthorExposesParsedNameAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0x01, 0x00, 0x00, 0x00, 0x02, 0x00])
        let payload = trackChangeAuthorPayload(name: "CoreHwp Fixture", rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeAuthor.self,
            from: JSONEncoder().encode(author)
        )

        expect(author.authorInfo?.name) == "CoreHwp Fixture"
        expect(author.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(15))
        expect(author.authorInfo?.nameRawPayload) == trackChangeAuthorNamePayload(
            "CoreHwp Fixture"
        )
        expect(author.authorInfo?.rawTrailing) == rawTrailing
        expect(author.rawPayload) == payload
        expect(decoded.authorInfo?.name) == "CoreHwp Fixture"
        expect(decoded.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(15))
        expect(decoded.authorInfo?.nameRawPayload) == trackChangeAuthorNamePayload(
            "CoreHwp Fixture"
        )
        expect(decoded.authorInfo?.rawTrailing) == rawTrailing
        expect(decoded.rawPayload) == payload
    }

    func testTrackChangeAuthorDecodesUtf16SurrogatePairs() throws {
        let rawTrailing = Data([0xAA, 0xBB])
        let payload = trackChangeAuthorPayload(name: "CoreHwp 😀", rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)

        expect(author.authorInfo?.name) == "CoreHwp 😀"
        expect(author.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(10))
        expect(author.authorInfo?.nameRawPayload) == trackChangeAuthorNamePayload("CoreHwp 😀")
        expect(author.authorInfo?.rawTrailing) == rawTrailing
        expect(author.rawPayload) == payload
    }

    func testTrackChangeAuthorAllowsEmptyNameAndPreservesTrailingBytes() throws {
        let rawTrailing = Data([0x01, 0x02, 0x03, 0x04])
        let payload = littleEndianData(UInt32(0)) + rawTrailing
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)

        expect(author.authorInfo?.name) == ""
        expect(author.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(0))
        expect(author.authorInfo?.nameRawPayload).to(beEmpty())
        expect(author.authorInfo?.rawTrailing) == rawTrailing
        expect(author.rawPayload) == payload
    }

    func testTrackChangeAuthorWithInvalidUtf16IsPreservedWithoutParsedInfo() throws {
        let payload = littleEndianData(UInt32(1))
            + littleEndianData(WCHAR(0xD800))
            + Data([0xAA, 0xBB])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeAuthor.self,
            from: JSONEncoder().encode(author)
        )

        expect(author.authorInfo).to(beNil())
        expect(author.rawPayload) == payload
        expect(decoded.authorInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testMalformedTrackChangeAuthorPayloadIsPreservedWithoutParsedInfo() throws {
        let payload = littleEndianData(UInt32(5)) + Data([0x43, 0x00])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeAuthor.self,
            from: JSONEncoder().encode(author)
        )

        expect(author.authorInfo).to(beNil())
        expect(author.rawPayload) == payload
        expect(decoded.authorInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testTrackChangeAuthorWithOversizedLengthIsPreservedWithoutParsedInfo() throws {
        let payload = littleEndianData(UInt32.max)
            + littleEndianData(WCHAR(0x0043))
            + Data([0xAA, 0xBB])
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: payload
        )

        let author = try HwpTrackChangeAuthor.load(record)
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeAuthor.self,
            from: JSONEncoder().encode(author)
        )

        expect(author.authorInfo).to(beNil())
        expect(author.rawPayload) == payload
        expect(decoded.authorInfo).to(beNil())
        expect(decoded.rawPayload) == payload
    }

    func testTrackChangeAuthorPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let payload = trackChangeAuthorPayload(name: "CoreHwp Fixture")
        let paddedPayload = Data([0xAA, 0xBB]) + payload
        let slicedPayload = paddedPayload.dropFirst(2)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: slicedPayload
        )

        let author = try HwpTrackChangeAuthor.load(record)

        expect(author.authorInfo?.name) == "CoreHwp Fixture"
        expect(author.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(15))
        expect(author.authorInfo?.nameRawPayload) == trackChangeAuthorNamePayload(
            "CoreHwp Fixture"
        )
        expect(author.rawPayload) == slicedPayload
    }

    func testTrackChangesFixtureExposesContentAndAuthorKnownFields() throws {
        let hwp = try openHwp(#file, "track-changes")

        assertTrackChangesFixtureKnownFields(hwp)
    }

    func testTrackChangesFixtureKnownFieldsSurviveHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "track-changes")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        assertTrackChangesFixtureKnownFields(decoded)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.docInfo.trackChangeContentArray.map(\.rawPayload)) ==
            hwp.docInfo.trackChangeContentArray.map(\.rawPayload)
        expect(decoded.docInfo.trackChangeAuthorArray.map(\.rawPayload)) ==
            hwp.docInfo.trackChangeAuthorArray.map(\.rawPayload)
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testDocInfoMergesIdMappingsAndTopLevelTrackChangeContentAndAuthors() throws {
        let fixture = MergedTrackChangeDocInfoFixture()
        let docInfo = try HwpDocInfo.load(fixture.data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.idMappings.trackChangeContentArray.map(\.rawPayload)) == [
            fixture.idMappingsContentPayload,
        ]
        expect(docInfo.idMappings.trackChangeAuthorArray.map(\.rawPayload)) == [
            fixture.idMappingsAuthorPayload,
        ]
        expect(docInfo.trackChangeContentArray.map(\.rawPayload)) == [
            fixture.idMappingsContentPayload,
            fixture.topLevelContentPayload,
        ]
        expect(docInfo.trackChangeContentArray.map(\.contentInfo?.kind)) == [21, 22]
        expect(docInfo.trackChangeAuthorArray.map(\.rawPayload)) == [
            fixture.idMappingsAuthorPayload,
            fixture.topLevelAuthorPayload,
        ]
        expect(docInfo.trackChangeAuthorArray.map(\.authorInfo?.name)) == [
            "IdMapping Author",
            "TopLevel Author",
        ]
        expect(docInfo.unknownRecords).to(beEmpty())
    }
}

private func assertTrackChangesFixtureKnownFields(_ hwp: HwpFile) {
    expect(hwp.docInfo.trackChangeContentArray.count) == 2
    expect(hwp.docInfo.trackChangeContentArray.map(\.rawPayload.count)) == [26, 26]
    expect(hwp.docInfo.trackChangeContentArray.map(\.contentInfo?.kind)) == [17, 16]
    expect(hwp.docInfo.trackChangeContentArray.map {
        Array($0.contentInfo?.kindRawPayload ?? Data())
    }) == [
        [17, 0, 0, 0],
        [16, 0, 0, 0],
    ]
    expect(hwp.docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.year)) == [2026, 2026]
    expect(hwp.docInfo.trackChangeContentArray.map(\.contentInfo?.timestamp.minute)) == [30, 31]
    expect(hwp.docInfo.trackChangeContentArray.map(\.contentInfo?.timestampRawPayload.count)) ==
        [10, 10]
    expect(hwp.docInfo.trackChangeContentArray.map {
        Array($0.contentInfo?.timestampRawPayload ?? Data())
    }) == [
        [234, 7, 6, 0, 15, 0, 4, 0, 30, 0],
        [234, 7, 6, 0, 15, 0, 4, 0, 31, 0],
    ]
    expect(hwp.docInfo.trackChangeContentArray.map(\.contentInfo?.rawTrailing.count)) == [12, 12]
    expect(hwp.docInfo.trackChangeContentArray.map {
        Array($0.contentInfo?.rawTrailing.prefix(4) ?? Data())
    }) == [
        [1, 0, 0, 0],
        [1, 0, 0, 0],
    ]
    expect(hwp.docInfo.trackChangeContentArray.map {
        Array($0.contentInfo?.rawTrailing.suffix(4) ?? Data())
    }) == [
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]

    expect(hwp.docInfo.trackChangeAuthorArray.count) == 1
    let author = hwp.docInfo.trackChangeAuthorArray.first
    expect(author?.rawPayload.count) == 42
    expect(author?.authorInfo?.name) == "CoreHwp Fixture"
    expect(author?.authorInfo?.nameLengthRawPayload) == littleEndianData(UInt32(15))
    expect(author?.authorInfo?.nameRawPayload.count) == 30
    expect(author?.authorInfo?.rawTrailing.count) == 8
    expect(Array(author?.authorInfo?.rawTrailing.prefix(4) ?? Data())) == [1, 0, 0, 0]
    expect(Array(author?.authorInfo?.rawTrailing.suffix(4) ?? Data())) == [0, 0, 0, 0]
}

private struct MergedTrackChangeDocInfoFixture {
    let idMappingsContentPayload = trackChangeContentPayload(
        kind: 21,
        timestamp: TrackChangeContentTimestamp(2026, 6, 20, 16, 40),
        rawTrailing: Data([0xC1, 0xC2])
    )
    let topLevelContentPayload = trackChangeContentPayload(
        kind: 22,
        timestamp: TrackChangeContentTimestamp(2026, 6, 20, 16, 41),
        rawTrailing: Data([0xD1, 0xD2])
    )
    let idMappingsAuthorPayload = trackChangeAuthorPayload(
        name: "IdMapping Author",
        rawTrailing: Data([0xA1, 0xA2])
    )
    let topLevelAuthorPayload = trackChangeAuthorPayload(
        name: "TopLevel Author",
        rawTrailing: Data([0xB1, 0xB2])
    )

    var data: Data {
        var data = requiredRecords()
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 1,
            payload: idMappingsContentPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 1,
            payload: idMappingsAuthorPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            level: 0,
            payload: topLevelContentPayload
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            level: 0,
            payload: topLevelAuthorPayload
        ))
        return data
    }

    private func requiredRecords() -> Data {
        var idMappingCounts = Array(repeating: Int32(0), count: 18)
        idMappingCounts[16] = 1
        idMappingCounts[17] = 1

        return recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: documentPropertiesPayload()
        ) + recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload(idMappingCounts)
        )
    }
}

private func documentPropertiesPayload() -> Data {
    littleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func idMappingsPayload(_ counts: [Int32] = Array(repeating: Int32(0), count: 18)) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(littleEndianData(count))
    }
}

private func trackChangeContentPayload(
    kind: UInt32,
    timestamp: TrackChangeContentTimestamp,
    rawTrailing: Data = Data(repeating: 0, count: 12)
) -> Data {
    var payload = littleEndianData(kind)
    payload.append(trackChangeContentTimestampPayload(timestamp))
    payload.append(rawTrailing)
    return payload
}

private func assertTrackChangeContent(
    _ content: HwpTrackChangeContent,
    kind: UInt32,
    timestamp: TrackChangeContentTimestamp,
    rawTrailing: Data,
    rawPayload: Data
) {
    expect(content.contentInfo?.kind) == kind
    expect(content.contentInfo?.kindRawPayload) == littleEndianData(kind)
    expect(content.contentInfo?.timestamp.year) == timestamp.year
    expect(content.contentInfo?.timestamp.month) == timestamp.month
    expect(content.contentInfo?.timestamp.day) == timestamp.day
    expect(content.contentInfo?.timestamp.hour) == timestamp.hour
    expect(content.contentInfo?.timestamp.minute) == timestamp.minute
    expect(content.contentInfo?.timestampRawPayload) ==
        trackChangeContentTimestampPayload(timestamp)
    expect(content.contentInfo?.rawTrailing) == rawTrailing
    expect(content.rawPayload) == rawPayload
}

private func trackChangeContentTimestampPayload(
    _ timestamp: TrackChangeContentTimestamp
) -> Data {
    timestamp.values.reduce(into: Data()) { payload, value in
        payload.append(littleEndianData(value))
    }
}

private struct TrackChangeContentTimestamp {
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

private func trackChangeAuthorPayload(
    name: String,
    rawTrailing: Data = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
) -> Data {
    var payload = littleEndianData(UInt32(name.utf16.count))
    payload.append(trackChangeAuthorNamePayload(name))
    payload.append(rawTrailing)
    return payload
}

private func trackChangeAuthorNamePayload(_ name: String) -> Data {
    var payload = Data()
    for character in name.utf16 {
        payload.append(littleEndianData(character))
    }
    return payload
}

private func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    littleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20)) + payload
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
