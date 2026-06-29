@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SectionCodableTests: XCTestCase {
    func testSectionPreservesMultipleParagraphsAndInterleavedUnknownTopLevelRecords() throws {
        let unknownPayload = Data([0xD0, 0xD1])
        let unknownChildPayload = Data([0xE0])
        var data = sectionCodableParagraphRecordData()
        data.append(sectionCodableRecordData(tagId: 0x2FE, level: 0, payload: unknownPayload))
        data.append(sectionCodableRecordData(
            tagId: 0x2FD,
            level: 1,
            payload: unknownChildPayload
        ))
        data.append(sectionCodableParagraphRecordData())

        let section = try HwpSection.load(data, HwpVersion(5, 0, 3, 2))
        let decoded = try JSONDecoder().decode(HwpSection.self, from: JSONEncoder().encode(section))

        expect(section.rawPayload) == data
        expect(section.paragraph.count) == 2
        expect(section.unknownRecords) == [
            expectedTestUnknownRecord(
                tagId: 0x2FE,
                level: 0,
                payload: unknownPayload,
                children: [
                    expectedTestRecord(tagId: 0x2FD, level: 1, payload: unknownChildPayload),
                ]
            ),
        ]
        expect(decoded.rawPayload) == data
        expect(decoded.paragraph.count) == 2
        expect(decoded.unknownRecords) == section.unknownRecords
    }

    func testSectionUnknownRecordsPreservePayloadsThroughCodableRoundTrip() throws {
        let unknownPayload = Data([0xCA, 0xFE])
        let unknownChildPayload = Data([0xAA])
        var data = sectionCodableRecordData(tagId: 0x2FE, level: 0, payload: unknownPayload)
        data.append(sectionCodableRecordData(tagId: 0x2FD, level: 1, payload: unknownChildPayload))
        data.append(sectionCodableRecordData(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: sectionCodableParaHeaderPayload()
        ))
        data.append(sectionCodableRecordData(
            tagId: HwpSectionTag.paraCharShape.rawValue,
            level: 1,
            payload: sectionCodableParaCharShapePayload()
        ))
        data.append(sectionCodableRecordData(
            tagId: HwpSectionTag.paraLineSeg.rawValue,
            level: 1,
            payload: Data()
        ))

        let section = try HwpSection.load(data, HwpVersion(5, 0, 3, 2))
        let decoded = try JSONDecoder().decode(HwpSection.self, from: JSONEncoder().encode(section))

        expect(decoded.rawPayload) == data
        expect(decoded.paragraph.count) == 1
        expect(decoded.unknownRecords) == [
            expectedTestUnknownRecord(
                tagId: 0x2FE,
                level: 0,
                payload: unknownPayload,
                children: [
                    expectedTestRecord(tagId: 0x2FD, level: 1, payload: unknownChildPayload),
                ]
            ),
        ]
    }

    func testSectionPreservesNotImplementedControlThroughCodableRoundTrip() throws {
        let ctrlPayload = sectionCodableLittleEndianData(HwpCommonCtrlId.table.rawValue)
        let tablePayload = Data([0xAA])
        let unknownChildPayload = Data([0xBB, 0xCC])
        var data = sectionCodableParagraphRecordData()
        data.append(sectionCodableRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        ))
        data.append(sectionCodableRecordData(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: tablePayload
        ))
        data.append(sectionCodableRecordData(
            tagId: 0x2FE,
            level: 2,
            payload: unknownChildPayload
        ))

        let section = try HwpSection.load(data, HwpVersion(5, 0, 3, 2))
        let decoded = try JSONDecoder().decode(HwpSection.self, from: JSONEncoder().encode(section))

        expect(decoded.rawPayload) == data
        expect(decoded.paragraph.count) == 1
        guard case let .notImplemented(header) = decoded.paragraph.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected malformed table control to be preserved as notImplemented")
        }
        expect(header.ctrlId) == HwpCommonCtrlId.table.rawValue
        expect(header.rawPayload) == ctrlPayload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePayload
            ),
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: unknownChildPayload),
        ]
    }
}

private func sectionCodableParagraphRecordData() -> Data {
    var data = sectionCodableRecordData(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: sectionCodableParaHeaderPayload()
    )
    data.append(sectionCodableRecordData(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: sectionCodableParaCharShapePayload()
    ))
    data.append(sectionCodableRecordData(
        tagId: HwpSectionTag.paraLineSeg.rawValue,
        level: 1,
        payload: Data()
    ))
    return data
}

private func sectionCodableParaHeaderPayload() -> Data {
    var data = Data()
    data.append(sectionCodableLittleEndianData(UInt32(0x8000_0000)))
    data.append(sectionCodableLittleEndianData(UInt32(0)))
    data.append(sectionCodableLittleEndianData(UInt16(0)))
    data.append(contentsOf: [0, 0])
    data.append(sectionCodableLittleEndianData(UInt16(1)))
    data.append(sectionCodableLittleEndianData(UInt16(0)))
    data.append(sectionCodableLittleEndianData(UInt16(0)))
    data.append(sectionCodableLittleEndianData(UInt32(0)))
    data.append(sectionCodableLittleEndianData(UInt16(0)))
    return data
}

private func sectionCodableParaCharShapePayload() -> Data {
    concatenatedData(
        sectionCodableLittleEndianData(UInt32(0)),
        sectionCodableLittleEndianData(UInt32(0))
    )
}

private func sectionCodableRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = sectionCodableLittleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func sectionCodableLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
