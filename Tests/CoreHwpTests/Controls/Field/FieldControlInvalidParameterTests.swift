@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FieldControlInvalidParameterTests: XCTestCase {
    func testParagraphPreservesInvalidUtf16FieldParameterAsRawFieldControl() throws {
        let rawTrailing = invalidUTF16FieldParameterTrailing()
        var rawPayload = fieldInvalidParameterLittleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xCC])))

        let control = try HwpFieldControl.load(record)
        let paragraph = try fieldInvalidParameterParagraph(containing: record)
        let field = try genericFieldControl(
            from: paragraph.ctrlHeaderArray?.first,
            message: "Expected invalid parameter field to stay generic field"
        )
        let roundTripped = try roundTrippedGenericField(
            from: paragraph.ctrlHeaderArray?.first,
            message: "Expected invalid parameter field after Codable round-trip"
        )

        assertInvalidParameterField(control, rawPayload: rawPayload, rawTrailing: rawTrailing)
        assertInvalidParameterField(
            field,
            rawPayload: rawPayload,
            rawTrailing: rawTrailing,
            childTagId: 0x2FA,
            childPayload: Data([0xCC])
        )
        assertInvalidParameterField(
            roundTripped,
            rawPayload: rawPayload,
            rawTrailing: rawTrailing,
            childTagId: 0x2FA,
            childPayload: Data([0xCC])
        )
    }

    func testParagraphPreservesOverflowingFieldParameterLengthAsRawFieldControl() throws {
        let rawTrailing = overflowingFieldParameterTrailing()
        var rawPayload = fieldInvalidParameterLittleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FB, level: 2, payload: Data([0xDD])))

        let control = try HwpFieldControl.load(record)
        let paragraph = try fieldInvalidParameterParagraph(containing: record)
        let field = try genericFieldControl(
            from: paragraph.ctrlHeaderArray?.first,
            message: "Expected overflowing parameter field to stay generic field"
        )
        let roundTripped = try roundTrippedGenericField(
            from: paragraph.ctrlHeaderArray?.first,
            message: "Expected overflowing parameter field after Codable round-trip"
        )

        assertInvalidParameterField(control, rawPayload: rawPayload, rawTrailing: rawTrailing)
        assertInvalidParameterField(
            field,
            rawPayload: rawPayload,
            rawTrailing: rawTrailing,
            childTagId: 0x2FB,
            childPayload: Data([0xDD])
        )
        assertInvalidParameterField(
            roundTripped,
            rawPayload: rawPayload,
            rawTrailing: rawTrailing,
            childTagId: 0x2FB,
            childPayload: Data([0xDD])
        )
    }
}

private func fieldInvalidParameterParagraph(containing record: HwpRecord) throws -> HwpParagraph {
    try HwpParagraph.load(
        fieldInvalidParameterParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            record,
        ]),
        HwpVersion(5, 0, 1, 1)
    )
}

private func genericFieldControl(
    from ctrlId: HwpCtrlId?,
    message: String
) throws -> HwpFieldControl {
    guard case let .field(field) = ctrlId else {
        fail(message)
        throw HwpError.invalidCtrlId(ctrlId: HwpFieldCtrlId.unknown.rawValue)
    }
    return field
}

private func roundTrippedGenericField(
    from ctrlId: HwpCtrlId?,
    message: String
) throws -> HwpFieldControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(ctrlId)
    )
    return try genericFieldControl(from: decoded, message: message)
}

private func assertInvalidParameterField(
    _ field: HwpFieldControl,
    rawPayload: Data,
    rawTrailing: Data,
    childTagId: UInt32? = nil,
    childPayload: Data? = nil
) {
    expect(field.semanticKind) == .field
    expect(field.fieldParameter).to(beNil())
    expect(field.fieldParameterRawTrailing).to(beNil())
    expect(field.memoParameter).to(beNil())
    expect(field.rawPayload) == rawPayload
    expect(field.rawTrailing) == rawTrailing

    if let childTagId, let childPayload {
        expect(field.unknownChildren) == [
            expectedTestUnknownRecord(tagId: childTagId, level: 2, payload: childPayload),
        ]
    }
}

private func invalidUTF16FieldParameterTrailing() -> Data {
    var data = Data()
    data.append(fieldInvalidParameterLittleEndianData(UInt32(0x8001)))
    data.append(fieldInvalidParameterLittleEndianData(WORD(1)))
    data.append(fieldInvalidParameterLittleEndianData(WCHAR(0xD800)))
    return data
}

private func overflowingFieldParameterTrailing() -> Data {
    var data = Data()
    data.append(fieldInvalidParameterLittleEndianData(UInt32(0x8001)))
    data.append(fieldInvalidParameterLittleEndianData(WORD(4)))
    data.append(fieldInvalidParameterLittleEndianData(WCHAR(0x004D)))
    data.append(fieldInvalidParameterLittleEndianData(WCHAR(0x0045)))
    return data
}

private func fieldInvalidParameterParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: fieldInvalidParameterParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func fieldInvalidParameterParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(fieldInvalidParameterLittleEndianData(UInt32(0x8000_0000)))
    data.append(fieldInvalidParameterLittleEndianData(UInt32(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt16(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt8(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt8(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt16(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt16(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt16(0)))
    data.append(fieldInvalidParameterLittleEndianData(UInt32(1)))
    return data
}

private func fieldInvalidParameterLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
