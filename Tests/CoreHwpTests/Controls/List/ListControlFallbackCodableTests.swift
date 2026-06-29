@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ListControlFallbackCodableTests: XCTestCase {
    func testTruncatedListHeaderFallbackPreservesNestedChildrenThroughParagraphCodable() throws {
        let rawPayload = listFallbackLittleEndianData(HwpOtherCtrlId.header.rawValue)
        let listHeader = listFallbackNestedChildRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: Data([0xAA]),
            nestedTagId: 0x2FD,
            nestedPayload: Data([0xCC])
        )
        let unknownChild = listFallbackNestedChildRecord(
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
        controlRecord.children = [listHeader, unknownChild]

        let paragraph = try HwpParagraph.load(
            listFallbackParagraphRecord(children: [
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

        assertListFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertListFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }
}

private func assertListFallbackControl(_ control: HwpCtrlId?, rawPayload: Data) {
    guard case let .other(other) = control else {
        return fail("Expected truncated list control to be preserved as other")
    }

    expect(other.ctrlId) == .header
    expect(other.rawPayload) == rawPayload
    expect(other.rawTrailing).to(beEmpty())
    expect(other.ctrlDataRecords).to(beEmpty())
    expect(other.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
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

private func listFallbackNestedChildRecord(
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

private func listFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: listFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func listFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(listFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(listFallbackLittleEndianData(UInt32(0)))
    data.append(listFallbackLittleEndianData(UInt16(0)))
    data.append(listFallbackLittleEndianData(UInt8(0)))
    data.append(listFallbackLittleEndianData(UInt8(0)))
    data.append(listFallbackLittleEndianData(UInt16(0)))
    data.append(listFallbackLittleEndianData(UInt16(0)))
    data.append(listFallbackLittleEndianData(UInt16(0)))
    data.append(listFallbackLittleEndianData(UInt32(1)))
    return data
}

private func listFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
