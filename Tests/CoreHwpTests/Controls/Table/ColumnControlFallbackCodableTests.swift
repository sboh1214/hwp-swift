@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ColumnControlFallbackCodableTests: XCTestCase {
    func testTruncatedColumnFallbackPreservesNestedChildrenThroughParagraphCodable() throws {
        let rawPayload = concatenatedData(
            columnFallbackLittleEndianData(HwpOtherCtrlId.column.rawValue),
            Data([0xAA])
        )
        let unknownChild = columnFallbackNestedChildRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            nestedTagId: 0x2FD,
            nestedPayload: Data([0xCC])
        )
        let controlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        controlRecord.children = [unknownChild]

        let paragraph = try HwpParagraph.load(
            columnFallbackParagraphRecord(children: [
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

        assertColumnFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertColumnFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }
}

private func assertColumnFallbackControl(_ control: HwpCtrlId?, rawPayload: Data) {
    guard case let .other(other) = control else {
        return fail("Expected truncated column control to be preserved as other")
    }

    expect(other.ctrlId) == .column
    expect(other.rawPayload) == rawPayload
    expect(other.rawTrailing) == Data([0xAA])
    expect(other.ctrlDataRecords).to(beEmpty())
    expect(other.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            children: [
                expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xCC])),
            ]
        ),
    ]
}

private func columnFallbackNestedChildRecord(
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

private func columnFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: columnFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func columnFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(columnFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(columnFallbackLittleEndianData(UInt32(0)))
    data.append(columnFallbackLittleEndianData(UInt16(0)))
    data.append(columnFallbackLittleEndianData(UInt8(0)))
    data.append(columnFallbackLittleEndianData(UInt8(0)))
    data.append(columnFallbackLittleEndianData(UInt16(0)))
    data.append(columnFallbackLittleEndianData(UInt16(0)))
    data.append(columnFallbackLittleEndianData(UInt16(0)))
    data.append(columnFallbackLittleEndianData(UInt32(1)))
    return data
}

private func columnFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
