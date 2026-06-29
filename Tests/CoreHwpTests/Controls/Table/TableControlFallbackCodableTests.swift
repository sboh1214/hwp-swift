@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TableControlFallbackCodableTests: XCTestCase {
    func testTruncatedTableFallbackPreservesNestedChildrenThroughParagraphCodable() throws {
        let rawPayload = tableFallbackLittleEndianData(HwpCommonCtrlId.table.rawValue)
        let tableRecord = tableFallbackNestedChildRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: Data([0xAA]),
            nestedTagId: 0x2FD,
            nestedPayload: Data([0xCC])
        )
        let unknownRecord = tableFallbackNestedChildRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            nestedTagId: 0x2FC,
            nestedPayload: Data([0xDD])
        )
        let controlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        controlRecord.children = [tableRecord, unknownRecord]

        let paragraph = try HwpParagraph.load(
            tableFallbackParagraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                controlRecord,
            ]),
            HwpVersion(5, 0, 1, 1)
        )
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )

        assertTableFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertTableFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }
}

private func assertTableFallbackControl(_ control: HwpCtrlId?, rawPayload: Data) {
    guard case let .notImplemented(header) = control else {
        return fail("Expected truncated table control to be preserved as notImplemented")
    }

    expect(header.ctrlId) == HwpCommonCtrlId.table.rawValue
    expect(header.rawPayload) == rawPayload
    expect(header.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: Data([0xAA]),
            children: [
                expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xCC])),
            ]
        ),
        expectedTestUnknownRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            children: [
                expectedTestRecord(tagId: 0x2FC, level: 3, payload: Data([0xDD])),
            ]
        ),
    ]
}

private func tableFallbackNestedChildRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    nestedTagId: UInt32,
    nestedPayload: Data
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = [
        HwpRecord(tagId: nestedTagId, level: level + 1, payload: nestedPayload),
    ]
    return record
}

private func tableFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: tableFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func tableFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(tableFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(tableFallbackLittleEndianData(UInt32(0)))
    data.append(tableFallbackLittleEndianData(UInt16(0)))
    data.append(tableFallbackLittleEndianData(UInt8(0)))
    data.append(tableFallbackLittleEndianData(UInt8(0)))
    data.append(tableFallbackLittleEndianData(UInt16(0)))
    data.append(tableFallbackLittleEndianData(UInt16(0)))
    data.append(tableFallbackLittleEndianData(UInt16(0)))
    data.append(tableFallbackLittleEndianData(UInt32(1)))
    return data
}

private func tableFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
