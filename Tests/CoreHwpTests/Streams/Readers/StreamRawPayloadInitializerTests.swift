@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class StreamRawPayloadInitializerTests: XCTestCase {
    func testDocInfoInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = streamRawPayloadMinimalDocInfoData(sectionSize: 1)
        let slicedPayload = (Data([0xFF, 0xEE]) + payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let docInfo = try HwpDocInfo(&reader, HwpVersion())

        expect(docInfo.rawPayload) == slicedPayload
        expect(docInfo.documentProperties.sectionSize) == 1
        expect(docInfo.unknownRecords).to(beEmpty())
        expect(reader.isEOF) == true
    }

    func testSectionInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = streamRawPayloadMinimalSectionData()
        let slicedPayload = (Data([0xFF, 0xEE]) + payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let section = try HwpSection(&reader, HwpVersion())

        expect(section.rawPayload) == slicedPayload
        expect(section.paragraph.count) == 1
        expect(section.unknownRecords).to(beEmpty())
        expect(reader.isEOF) == true
    }
}

private func streamRawPayloadMinimalDocInfoData(sectionSize: UInt16) -> Data {
    streamRawPayloadRecordData(
        tagId: HwpDocInfoTag.documentProperties.rawValue,
        level: 0,
        payload: streamRawPayloadDocumentPropertiesPayload(sectionSize: sectionSize)
    )
        + streamRawPayloadRecordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: streamRawPayloadIdMappingsPayload()
        )
}

private func streamRawPayloadMinimalSectionData() -> Data {
    streamRawPayloadRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: streamRawPayloadParaHeaderPayload()
    )
        + streamRawPayloadRecordData(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: streamRawPayloadParaCharShapePayload()
        )
}

private func streamRawPayloadDocumentPropertiesPayload(sectionSize: UInt16) -> Data {
    streamRawPayloadLittleEndianData(sectionSize) + Data(repeating: 0, count: 24)
}

private func streamRawPayloadIdMappingsPayload() -> Data {
    Array(repeating: Int32(0), count: 18).reduce(into: Data()) { data, count in
        data.append(streamRawPayloadLittleEndianData(count))
    }
}

private func streamRawPayloadParaHeaderPayload() -> Data {
    streamRawPayloadLittleEndianData(UInt32(0x8000_0000))
        + streamRawPayloadLittleEndianData(UInt32(0))
        + streamRawPayloadLittleEndianData(UInt16(0))
        + Data([0, 0])
        + streamRawPayloadLittleEndianData(UInt16(1))
        + streamRawPayloadLittleEndianData(UInt16(0))
        + streamRawPayloadLittleEndianData(UInt16(0))
        + streamRawPayloadLittleEndianData(UInt32(0))
        + streamRawPayloadLittleEndianData(UInt16(0))
}

private func streamRawPayloadParaCharShapePayload() -> Data {
    streamRawPayloadLittleEndianData(UInt32(0)) + streamRawPayloadLittleEndianData(UInt32(0))
}

private func streamRawPayloadRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = streamRawPayloadLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func streamRawPayloadLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
