@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoCodableTests: XCTestCase {
    func testDocInfoRawRecordsPreservePayloadsThroughCodableRoundTrip() throws {
        let fixture = DocInfoCodableFixture.make()
        let docInfo = try HwpDocInfo.load(fixture.data, HwpVersion(5, 0, 3, 2))
        let decoded = try JSONDecoder().decode(
            HwpDocInfo.self,
            from: JSONEncoder().encode(docInfo)
        )

        assertDecodedDocInfo(decoded, fixture)
    }
}

private func assertDecodedDocInfo(_ decoded: HwpDocInfo, _ fixture: DocInfoCodableFixture) {
    expect(decoded.rawPayload) == fixture.data
    expect(decoded.docData?.rawPayload) == fixture.docDataPayload
    expect(decoded.docData?.forbiddenCharArray.map(\.data)) == [fixture.forbiddenCharPayload]
    expect(decoded.docData?.forbiddenCharArray.map(\.rawPayload)) == [
        fixture.forbiddenCharPayload,
    ]
    expect(decoded.forbiddenCharArray.map(\.rawPayload)) == [
        fixture.forbiddenCharPayload,
        fixture.topLevelForbiddenCharPayload,
    ]
    assertDecodedDistributeDocData(decoded, fixture)
    assertDecodedCompatibleDocument(decoded, fixture)
    assertDecodedTopLevelRawRecords(decoded, fixture)
    assertDecodedUnknownRecords(decoded, fixture)
}

private func assertDecodedDistributeDocData(
    _ decoded: HwpDocInfo,
    _ fixture: DocInfoCodableFixture
) {
    expect(decoded.distributeDocData?.rawPayload) == fixture.distributePayload
    assertSingleUnknownRecordTree(
        decoded.distributeDocData?.unknownChildren ?? [],
        parent: .init(0x205, 1, fixture.distributeChildPayload),
        child: .init(0x305, 2, fixture.distributeGrandchildPayload)
    )
}

private func assertDecodedCompatibleDocument(
    _ decoded: HwpDocInfo,
    _ fixture: DocInfoCodableFixture
) {
    expect(decoded.compatibleDocument?.rawPayload) == fixture.compatiblePayload
    expect(decoded.compatibleDocument?.targetDocumentRawPayload) == fixture.compatiblePayload
    expect(decoded.compatibleDocument?.layoutCompatibility?.rawPayload) ==
        fixture.compatibleLayoutPayload
    expect(decoded.compatibleDocument?.layoutCompatibility?.fixedFieldsRawPayload) ==
        fixture.compatibleLayoutPayload
    assertSingleUnknownRecordTree(
        decoded.compatibleDocument?.layoutCompatibility?.unknownChildren ?? [],
        parent: .init(0x209, 2, fixture.compatibleLayoutChildPayload),
        child: .init(0x309, 3, fixture.compatibleLayoutGrandchildPayload)
    )
    expect(decoded.compatibleDocument?.trackChangeArray.map(\.rawPayload)) == [
        fixture.compatibleTrackChangePayload,
    ]
    assertSingleUnknownRecordTree(
        decoded.compatibleDocument?.trackChangeArray.first?.unknownChildren ?? [],
        parent: .init(0x206, 2, fixture.compatibleTrackChangeChildPayload),
        child: .init(0x306, 3, fixture.compatibleTrackChangeGrandchildPayload)
    )
    assertSingleUnknownRecordTree(
        decoded.compatibleDocument?.unknownChildren ?? [],
        parent: .init(0x207, 1, fixture.compatibleUnknownPayload),
        child: .init(0x307, 2, fixture.compatibleUnknownGrandchildPayload)
    )
}

private func assertDecodedTopLevelRawRecords(
    _ decoded: HwpDocInfo,
    _ fixture: DocInfoCodableFixture
) {
    expect(decoded.layoutCompatibility?.rawPayload) == fixture.layoutPayload
    expect(decoded.layoutCompatibility?.fixedFieldsRawPayload) == fixture.layoutPayload
    assertSingleUnknownRecordTree(
        decoded.layoutCompatibility?.unknownChildren ?? [],
        parent: .init(0x20A, 1, fixture.layoutChildPayload),
        child: .init(0x30A, 2, fixture.layoutGrandchildPayload)
    )
    expect(decoded.topLevelTrackChangeArray.map(\.rawPayload)) == [fixture.trackChangePayload]
    expect(decoded.trackChangeArray.map(\.rawPayload)) == [fixture.trackChangePayload]
    assertSingleUnknownRecordTree(
        decoded.topLevelTrackChangeArray.first?.unknownChildren ?? [],
        parent: .init(0x208, 1, fixture.trackChangeChildPayload),
        child: .init(0x308, 2, fixture.trackChangeGrandchildPayload)
    )
    expect(decoded.memoShapeArray.map(\.rawPayload)) == [fixture.memoShapePayload]
    assertSingleUnknownRecordTree(
        decoded.memoShapeArray.first?.unknownChildren ?? [],
        parent: .init(0x20B, 1, fixture.memoShapeChildPayload),
        child: .init(0x30B, 2, fixture.memoShapeGrandchildPayload)
    )
    expect(decoded.trackChangeContentArray.map(\.rawPayload)) == [
        fixture.trackChangeContentPayload,
    ]
    assertSingleUnknownRecordTree(
        decoded.trackChangeContentArray.first?.unknownChildren ?? [],
        parent: .init(0x20C, 1, fixture.trackChangeContentChildPayload),
        child: .init(0x30C, 2, fixture.trackChangeContentGrandchildPayload)
    )
    expect(decoded.trackChangeAuthorArray.map(\.rawPayload)) == [
        fixture.trackChangeAuthorPayload,
    ]
    assertSingleUnknownRecordTree(
        decoded.trackChangeAuthorArray.first?.unknownChildren ?? [],
        parent: .init(0x20D, 1, fixture.trackChangeAuthorChildPayload),
        child: .init(0x30D, 2, fixture.trackChangeAuthorGrandchildPayload)
    )
    expect(decoded.topLevelForbiddenCharArray.map(\.rawPayload)) == [
        fixture.topLevelForbiddenCharPayload,
    ]
    assertSingleUnknownRecordTree(
        decoded.topLevelForbiddenCharArray.first?.unknownChildren ?? [],
        parent: .init(0x20F, 1, fixture.topLevelForbiddenCharChildPayload),
        child: .init(0x30F, 2, fixture.topLevelForbiddenCharGrandchildPayload)
    )
}

private func assertDecodedUnknownRecords(_ decoded: HwpDocInfo, _ fixture: DocInfoCodableFixture) {
    expect(decoded.unknownRecords) == [
        expectedUnknownRecord(
            tagId: 0x2EE,
            level: 0,
            payload: fixture.unknownPayload,
            children: [
                expectedRecord(
                    tagId: 0x2ED,
                    level: 1,
                    payload: fixture.unknownChildPayload,
                    children: [
                        expectedRecord(
                            tagId: 0x2EC,
                            level: 2,
                            payload: fixture.unknownGrandchildPayload
                        ),
                    ]
                ),
            ]
        ),
    ]
}

private func assertSingleUnknownRecordTree(
    _ actual: [HwpUnknownRecord],
    parent: ExpectedRecordSpec,
    child: ExpectedRecordSpec
) {
    expect(actual) == [
        expectedUnknownRecord(
            tagId: parent.tagId,
            level: parent.level,
            payload: parent.payload,
            children: [
                expectedRecord(tagId: child.tagId, level: child.level, payload: child.payload),
            ]
        ),
    ]
}

private struct ExpectedRecordSpec {
    let tagId: UInt32
    let level: UInt32
    let payload: Data

    init(_ tagId: UInt32, _ level: UInt32, _ payload: Data) {
        self.tagId = tagId
        self.level = level
        self.payload = payload
    }
}

private func expectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        expectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func expectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private struct DocInfoCodableFixture {
    var data: Data
    let docDataPayload = Data([0x01, 0x02])
    let forbiddenCharPayload = Data([0x03])
    let distributePayload = Data([0x04])
    let distributeChildPayload = Data([0x14])
    let distributeGrandchildPayload = Data([0x34])
    let compatiblePayload = docInfoLittleEndianData(UInt32(0))
    let compatibleLayoutPayload = docInfoLayoutCompatibilityPayload(1, 2, 3, 4, 5)
    let compatibleLayoutChildPayload = Data([0x23])
    let compatibleLayoutGrandchildPayload = Data([0x33])
    let compatibleTrackChangePayload = Data([0x24])
    let compatibleTrackChangeChildPayload = Data([0x25])
    let compatibleTrackChangeGrandchildPayload = Data([0x35])
    let compatibleUnknownPayload = Data([0x26])
    let compatibleUnknownGrandchildPayload = Data([0x36])
    let layoutPayload = docInfoLayoutCompatibilityPayload(6, 7, 8, 9, 10)
    let layoutChildPayload = Data([0x27])
    let layoutGrandchildPayload = Data([0x37])
    let trackChangePayload = Data([0x05])
    let trackChangeChildPayload = Data([0x15])
    let trackChangeGrandchildPayload = Data([0x38])
    let memoShapePayload = Data([0x06])
    let memoShapeChildPayload = Data([0x16])
    let memoShapeGrandchildPayload = Data([0x46])
    let trackChangeContentPayload = Data([0x07])
    let trackChangeContentChildPayload = Data([0x17])
    let trackChangeContentGrandchildPayload = Data([0x47])
    let trackChangeAuthorPayload = Data([0x08])
    let trackChangeAuthorChildPayload = Data([0x18])
    let trackChangeAuthorGrandchildPayload = Data([0x48])
    let topLevelForbiddenCharPayload = Data([0x0A])
    let topLevelForbiddenCharChildPayload = Data([0x1A])
    let topLevelForbiddenCharGrandchildPayload = Data([0x4A])
    let unknownPayload = Data([0x09])
    let unknownChildPayload = Data([0x19])
    let unknownGrandchildPayload = Data([0x39])

    static func make() -> Self {
        var fixture = Self(data: Data())
        fixture.data = docInfoCodableRecords(for: fixture).reduce(into: Data()) { data, record in
            data.append(record)
        }
        return fixture
    }
}

private func docInfoCodableRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    docInfoBaseRecords(for: fixture)
        + docInfoDistributeRecords(for: fixture)
        + docInfoCompatibleDocumentRecords(for: fixture)
        + docInfoTopLevelRawRecords(for: fixture)
        + docInfoUnknownRecords(for: fixture)
}

private func docInfoBaseRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    [
        docInfoRecordData(.documentProperties, 0, docInfoDocumentPropertiesPayload()),
        docInfoRecordData(.idMappings, 0, docInfoIdMappingsPayload()),
        docInfoRecordData(.docData, 0, fixture.docDataPayload),
        docInfoRecordData(.forbiddenChar, 1, fixture.forbiddenCharPayload),
    ]
}

private func docInfoDistributeRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    [
        docInfoRecordData(.distributeDocData, 0, fixture.distributePayload),
        docInfoRecordData(tagId: 0x205, level: 1, payload: fixture.distributeChildPayload),
        docInfoRecordData(tagId: 0x305, level: 2, payload: fixture.distributeGrandchildPayload),
    ]
}

private func docInfoCompatibleDocumentRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    [
        docInfoRecordData(.compatibleDocument, 0, fixture.compatiblePayload),
        docInfoRecordData(.layoutCompatibility, 1, fixture.compatibleLayoutPayload),
        docInfoRecordData(tagId: 0x209, level: 2, payload: fixture.compatibleLayoutChildPayload),
        docInfoRecordData(
            tagId: 0x309,
            level: 3,
            payload: fixture.compatibleLayoutGrandchildPayload
        ),
        docInfoRecordData(.trackChange, 1, fixture.compatibleTrackChangePayload),
        docInfoRecordData(
            tagId: 0x206,
            level: 2,
            payload: fixture.compatibleTrackChangeChildPayload
        ),
        docInfoRecordData(
            tagId: 0x306,
            level: 3,
            payload: fixture.compatibleTrackChangeGrandchildPayload
        ),
        docInfoRecordData(tagId: 0x207, level: 1, payload: fixture.compatibleUnknownPayload),
        docInfoRecordData(
            tagId: 0x307,
            level: 2,
            payload: fixture.compatibleUnknownGrandchildPayload
        ),
    ]
}

private func docInfoTopLevelRawRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    [
        docInfoRecordData(.layoutCompatibility, 0, fixture.layoutPayload),
        docInfoRecordData(tagId: 0x20A, level: 1, payload: fixture.layoutChildPayload),
        docInfoRecordData(tagId: 0x30A, level: 2, payload: fixture.layoutGrandchildPayload),
        docInfoRecordData(.trackChange, 0, fixture.trackChangePayload),
        docInfoRecordData(tagId: 0x208, level: 1, payload: fixture.trackChangeChildPayload),
        docInfoRecordData(tagId: 0x308, level: 2, payload: fixture.trackChangeGrandchildPayload),
        docInfoRecordData(.memoShape, 0, fixture.memoShapePayload),
        docInfoRecordData(tagId: 0x20B, level: 1, payload: fixture.memoShapeChildPayload),
        docInfoRecordData(tagId: 0x30B, level: 2, payload: fixture.memoShapeGrandchildPayload),
        docInfoRecordData(.trackChangeContent, 0, fixture.trackChangeContentPayload),
        docInfoRecordData(
            tagId: 0x20C,
            level: 1,
            payload: fixture.trackChangeContentChildPayload
        ),
        docInfoRecordData(
            tagId: 0x30C,
            level: 2,
            payload: fixture.trackChangeContentGrandchildPayload
        ),
        docInfoRecordData(.trackChangeAuthor, 0, fixture.trackChangeAuthorPayload),
        docInfoRecordData(
            tagId: 0x20D,
            level: 1,
            payload: fixture.trackChangeAuthorChildPayload
        ),
        docInfoRecordData(
            tagId: 0x30D,
            level: 2,
            payload: fixture.trackChangeAuthorGrandchildPayload
        ),
        docInfoRecordData(.forbiddenChar, 0, fixture.topLevelForbiddenCharPayload),
        docInfoRecordData(
            tagId: 0x20F,
            level: 1,
            payload: fixture.topLevelForbiddenCharChildPayload
        ),
        docInfoRecordData(
            tagId: 0x30F,
            level: 2,
            payload: fixture.topLevelForbiddenCharGrandchildPayload
        ),
    ]
}

private func docInfoUnknownRecords(for fixture: DocInfoCodableFixture) -> [Data] {
    [
        docInfoRecordData(tagId: 0x2EE, level: 0, payload: fixture.unknownPayload),
        docInfoRecordData(tagId: 0x2ED, level: 1, payload: fixture.unknownChildPayload),
        docInfoRecordData(tagId: 0x2EC, level: 2, payload: fixture.unknownGrandchildPayload),
    ]
}

private func docInfoDocumentPropertiesPayload() -> Data {
    docInfoLittleEndianData(UInt16(1)) + Data(repeating: 0, count: 24)
}

private func docInfoIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(docInfoLittleEndianData(count))
    }
}

private func docInfoLayoutCompatibilityPayload(_ values: UInt32...) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(docInfoLittleEndianData(value))
    }
}

private func docInfoRecordData(_ tag: HwpDocInfoTag, _ level: UInt32, _ payload: Data) -> Data {
    docInfoRecordData(tagId: tag.rawValue, level: level, payload: payload)
}

private func docInfoRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = docInfoLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func docInfoLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
