@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoDuplicateRecordStabilityTests: XCTestCase {
    func testDuplicateSingletonRecordsArePreservedAsUnknownRecords() throws {
        let fixture = DuplicateDocInfoSingletonFixture()
        let docInfo = try HwpDocInfo.load(fixture.data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.docData?.rawPayload) == fixture.docDataPayload
        expect(docInfo.distributeDocData?.rawPayload) == fixture.distributePayload
        expect(docInfo.compatibleDocument?.rawPayload) == fixture.compatiblePayload
        expect(docInfo.compatibleDocument?.targetDocumentRawPayload) == fixture.compatiblePayload
        expect(docInfo.layoutCompatibility?.rawPayload) == fixture.layoutPayload
        expect(docInfo.layoutCompatibility?.fixedFieldsRawPayload) == fixture.layoutPayload
        expect(docInfo.unknownRecords) == fixture.duplicateUnknownRecords
    }
}

private struct DuplicateDocInfoSingletonFixture {
    let duplicateDocumentPropertiesPayload = duplicateDocInfoDocumentPropertiesPayload()
    let duplicateDocumentPropertiesChildPayload = Data([0xB0])
    let duplicateIdMappingsPayload = Data([0xA1])
    let duplicateIdMappingsChildPayload = Data([0xB1])
    let docDataPayload = Data([0x01])
    let duplicateDocDataPayload = Data([0xA5])
    let duplicateDocDataChildPayload = Data([0xB5])
    let distributePayload = Data([0x02])
    let duplicateDistributePayload = Data([0xA2])
    let duplicateDistributeChildPayload = Data([0xB2])
    let compatiblePayload = duplicateDocInfoLittleEndianData(UInt32(0))
    let duplicateCompatiblePayload = duplicateDocInfoLittleEndianData(UInt32(1))
    let duplicateCompatibleChildPayload = Data([0xB3])
    let layoutPayload = duplicateDocInfoLayoutPayload(2, 3, 4, 5, 6)
    let duplicateLayoutPayload = duplicateDocInfoLayoutPayload(7, 8, 9, 10, 11)
    let duplicateLayoutChildPayload = Data([0xB4])

    var duplicateUnknownRecords: [HwpUnknownRecord] {
        [
            duplicateUnknownRecord(
                .documentProperties,
                duplicateDocumentPropertiesPayload,
                0x300,
                duplicateDocumentPropertiesChildPayload
            ),
            duplicateUnknownRecord(
                .idMappings,
                duplicateIdMappingsPayload,
                0x301,
                duplicateIdMappingsChildPayload
            ),
            duplicateUnknownRecord(
                .docData,
                duplicateDocDataPayload,
                0x305,
                duplicateDocDataChildPayload
            ),
            duplicateUnknownRecord(
                .distributeDocData,
                duplicateDistributePayload,
                0x302,
                duplicateDistributeChildPayload
            ),
            duplicateUnknownRecord(
                .compatibleDocument,
                duplicateCompatiblePayload,
                0x303,
                duplicateCompatibleChildPayload
            ),
            duplicateUnknownRecord(
                .layoutCompatibility,
                duplicateLayoutPayload,
                0x304,
                duplicateLayoutChildPayload
            ),
        ]
    }

    var data: Data {
        var data = requiredRecords()
        appendDuplicateRecords(to: &data)
        return data
    }

    private func requiredRecords() -> Data {
        concatenatedData(
            duplicateDocInfoRecordData(
                tagId: HwpDocInfoTag.documentProperties.rawValue,
                payload: duplicateDocInfoDocumentPropertiesPayload()
            ),
            duplicateDocInfoRecordData(
                tagId: HwpDocInfoTag.idMappings.rawValue,
                payload: duplicateDocInfoIdMappingsPayload()
            )
        )
    }

    private func appendDuplicateRecords(to data: inout Data) {
        appendRecordWithChild(
            tag: .documentProperties,
            payload: duplicateDocumentPropertiesPayload,
            childTag: 0x300,
            childPayload: duplicateDocumentPropertiesChildPayload,
            to: &data
        )
        appendRecordWithChild(
            tag: .idMappings,
            payload: duplicateIdMappingsPayload,
            childTag: 0x301,
            childPayload: duplicateIdMappingsChildPayload,
            to: &data
        )
        appendRecord(.docData, payload: docDataPayload, to: &data)
        appendRecordWithChild(
            tag: .docData,
            payload: duplicateDocDataPayload,
            childTag: 0x305,
            childPayload: duplicateDocDataChildPayload,
            to: &data
        )
        appendRecord(.distributeDocData, payload: distributePayload, to: &data)
        appendRecordWithChild(
            tag: .distributeDocData,
            payload: duplicateDistributePayload,
            childTag: 0x302,
            childPayload: duplicateDistributeChildPayload,
            to: &data
        )
        appendRecord(.compatibleDocument, payload: compatiblePayload, to: &data)
        appendRecordWithChild(
            tag: .compatibleDocument,
            payload: duplicateCompatiblePayload,
            childTag: 0x303,
            childPayload: duplicateCompatibleChildPayload,
            to: &data
        )
        appendRecord(.layoutCompatibility, payload: layoutPayload, to: &data)
        appendRecordWithChild(
            tag: .layoutCompatibility,
            payload: duplicateLayoutPayload,
            childTag: 0x304,
            childPayload: duplicateLayoutChildPayload,
            to: &data
        )
    }

    private func appendRecord(
        _ tag: HwpDocInfoTag,
        payload: Data,
        to data: inout Data
    ) {
        data.append(duplicateDocInfoRecordData(tagId: tag.rawValue, payload: payload))
    }

    private func appendRecordWithChild(
        tag: HwpDocInfoTag,
        payload: Data,
        childTag: UInt32,
        childPayload: Data,
        to data: inout Data
    ) {
        appendRecord(tag, payload: payload, to: &data)
        data.append(duplicateDocInfoRecordData(tagId: childTag, level: 1, payload: childPayload))
    }

    private func duplicateUnknownRecord(
        _ tag: HwpDocInfoTag,
        _ payload: Data,
        _ childTag: UInt32,
        _ childPayload: Data
    ) -> HwpUnknownRecord {
        expectedTestUnknownRecord(
            tagId: tag.rawValue,
            level: 0,
            payload: payload,
            children: [
                expectedTestRecord(
                    tagId: childTag,
                    level: 1,
                    payload: childPayload
                ),
            ]
        )
    }
}

private func duplicateDocInfoDocumentPropertiesPayload() -> Data {
    concatenatedData(duplicateDocInfoLittleEndianData(UInt16(1)), Data(repeating: 0, count: 24))
}

private func duplicateDocInfoIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(duplicateDocInfoLittleEndianData(count))
    }
}

private func duplicateDocInfoRecordData(
    tagId: UInt32,
    level: UInt32 = 0,
    payload: Data
) -> Data {
    let header = tagId | (level << 10) | (UInt32(payload.count) << 20)
    var data = duplicateDocInfoLittleEndianData(header)
    data.append(payload)
    return data
}

private func duplicateDocInfoLayoutPayload(
    _ char: UInt32,
    _ paragraph: UInt32,
    _ section: UInt32,
    _ object: UInt32,
    _ field: UInt32
) -> Data {
    concatenatedData(
        duplicateDocInfoLittleEndianData(char),
        duplicateDocInfoLittleEndianData(paragraph),
        duplicateDocInfoLittleEndianData(section),
        duplicateDocInfoLittleEndianData(object),
        duplicateDocInfoLittleEndianData(field)
    )
}

private func duplicateDocInfoLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
