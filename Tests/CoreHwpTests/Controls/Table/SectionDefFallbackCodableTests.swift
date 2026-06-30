@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SectionDefFallbackCodableTests: XCTestCase {
    func testTruncatedSectionDefFallbackPreservesNestedChildrenThroughParagraphCodable() throws {
        let rawPayload = concatenatedData(
            sectionDefFallbackLittleEndianData(HwpOtherCtrlId.section.rawValue),
            Data([0xAA])
        )
        let unknownChild = sectionDefFallbackNestedChildRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            nestedTagId: 0x2FD,
            nestedPayload: Data([0xCC])
        )
        let requiredChildren = sectionDefFallbackRequiredChildren()
        let controlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        controlRecord.children = requiredChildren + [unknownChild]

        expect {
            _ = try HwpSectionDef.load(controlRecord, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 1
        })

        let paragraph = try HwpParagraph.load(
            sectionDefFallbackParagraphRecord(children: [
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

        assertSectionDefFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertSectionDefFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }
}

private func assertSectionDefFallbackControl(_ control: HwpCtrlId?, rawPayload: Data) {
    guard case let .other(other) = control else {
        return fail("Expected truncated section definition to be preserved as other")
    }

    expect(other.ctrlId) == .section
    expect(other.rawPayload) == rawPayload
    expect(other.rawTrailing) == Data([0xAA])
    expect(other.ctrlDataRecords).to(beEmpty())
    expect(other.unknownChildren) == sectionDefFallbackExpectedUnknownChildren()
}

private func sectionDefFallbackExpectedUnknownChildren() -> [HwpUnknownRecord] {
    sectionDefFallbackRequiredChildren().map(HwpUnknownRecord.init)
        + [
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

private func sectionDefFallbackNestedChildRecord(
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

private func sectionDefFallbackRequiredChildren() -> [HwpRecord] {
    [
        sectionDefFallbackChild(.pageDef, sectionDefFallbackPageDefPayload()),
        sectionDefFallbackChild(.footnoteShape, sectionDefFallbackFootnoteShapePayload()),
        sectionDefFallbackChild(.footnoteShape, sectionDefFallbackFootnoteShapePayload()),
        sectionDefFallbackChild(.pageBorderFill, sectionDefFallbackPageBorderFillPayload()),
        sectionDefFallbackChild(.pageBorderFill, sectionDefFallbackPageBorderFillPayload()),
        sectionDefFallbackChild(.pageBorderFill, sectionDefFallbackPageBorderFillPayload()),
    ]
}

private func sectionDefFallbackChild(_ tag: HwpSectionTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

private func sectionDefFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: sectionDefFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func sectionDefFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(sectionDefFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(sectionDefFallbackLittleEndianData(UInt32(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt16(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt8(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt8(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt16(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt16(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt16(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt32(1)))
    return data
}

private func sectionDefFallbackPageDefPayload() -> Data {
    var data = Data()
    for _ in 0 ..< 9 {
        data.append(sectionDefFallbackLittleEndianData(HWPUNIT(0)))
    }
    data.append(sectionDefFallbackLittleEndianData(UInt32(0)))
    return data
}

private func sectionDefFallbackFootnoteShapePayload() -> Data {
    var data = Data()
    data.append(sectionDefFallbackLittleEndianData(UInt32(0)))
    data.append(sectionDefFallbackLittleEndianData(WCHAR(0)))
    data.append(sectionDefFallbackLittleEndianData(WCHAR(0)))
    data.append(sectionDefFallbackLittleEndianData(WCHAR(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt16(1)))
    data.append(sectionDefFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt8(0)))
    data.append(sectionDefFallbackLittleEndianData(UInt8(0)))
    data.append(sectionDefFallbackLittleEndianData(COLORREF(0)))
    data.append(contentsOf: [0, 0])
    return data
}

private func sectionDefFallbackPageBorderFillPayload() -> Data {
    var data = Data()
    data.append(sectionDefFallbackLittleEndianData(UInt32(0)))
    for _ in 0 ..< 5 {
        data.append(sectionDefFallbackLittleEndianData(UInt16(0)))
    }
    return data
}

private func sectionDefFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
