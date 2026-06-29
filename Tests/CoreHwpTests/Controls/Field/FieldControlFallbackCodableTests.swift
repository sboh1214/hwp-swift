@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FieldControlFallbackCodableTests: XCTestCase {
    func testTruncatedHyperlinkFallbackPreservesNestedChildrenThroughParagraphCodable() throws {
        let rawPayload = fieldFallbackTruncatedHyperlinkPayload()
        let controlRecord = fieldFallbackControlRecord(rawPayload: rawPayload)

        expect {
            _ = try HwpHyperlink.load(controlRecord)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 6
            expect(actual) == 2
        })

        let paragraph = try fieldFallbackParagraph(controlRecord: controlRecord)
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )

        assertFieldFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertFieldFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }

    func testInvalidUnicodeHyperlinkFallbackPreservesNestedChildrenThroughParagraphCodable()
        throws
    {
        let rawPayload = fieldFallbackInvalidUnicodeHyperlinkPayload()
        let controlRecord = fieldFallbackControlRecord(rawPayload: rawPayload)

        expect {
            _ = try HwpHyperlink.load(controlRecord)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })

        let paragraph = try fieldFallbackParagraph(controlRecord: controlRecord)
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )

        assertFieldFallbackControl(paragraph.ctrlHeaderArray?.first, rawPayload: rawPayload)
        assertFieldFallbackControl(decoded.ctrlHeaderArray?.first, rawPayload: rawPayload)
    }
}

private func assertFieldFallbackControl(_ control: HwpCtrlId?, rawPayload: Data) {
    guard case let .field(field) = control else {
        return fail("Expected malformed hyperlink to be preserved as field")
    }

    expect(field.ctrlId) == .hyperLink
    expect(field.semanticKind) == .field
    expect(field.isMemoField) == false
    expect(field.isRevisionField) == false
    expect(field.rawPayload) == rawPayload
    expect(field.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
    expect(field.fieldParameter).to(beNil())
    expect(field.fieldParameterRawPayload).to(beNil())
    expect(field.fieldParameterRawTrailing).to(beNil())
    expect(field.memoParameter).to(beNil())
    expect(field.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FA,
            level: 2,
            payload: Data([0xDD]),
            children: [
                expectedTestRecord(tagId: 0x2F9, level: 3, payload: Data([0xEE])),
            ]
        ),
    ]
}

private func fieldFallbackControlRecord(rawPayload: Data) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = [
        fieldFallbackNestedChildRecord(
            tagId: 0x2FA,
            level: 2,
            payload: Data([0xDD]),
            nestedTagId: 0x2F9,
            nestedPayload: Data([0xEE])
        ),
    ]
    return record
}

private func fieldFallbackParagraph(controlRecord: HwpRecord) throws -> HwpParagraph {
    try HwpParagraph.load(
        fieldFallbackParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            controlRecord,
        ]),
        HwpVersion(5, 0, 1, 1)
    )
}

private func fieldFallbackNestedChildRecord(
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

private func fieldFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: fieldFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func fieldFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(fieldFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(fieldFallbackLittleEndianData(UInt32(0)))
    data.append(fieldFallbackLittleEndianData(UInt16(0)))
    data.append(fieldFallbackLittleEndianData(UInt8(0)))
    data.append(fieldFallbackLittleEndianData(UInt8(0)))
    data.append(fieldFallbackLittleEndianData(UInt16(0)))
    data.append(fieldFallbackLittleEndianData(UInt16(0)))
    data.append(fieldFallbackLittleEndianData(UInt16(0)))
    data.append(fieldFallbackLittleEndianData(UInt32(1)))
    return data
}

private func fieldFallbackTruncatedHyperlinkPayload() -> Data {
    var data = fieldFallbackHyperlinkPrefix(urlLength: 3, prefix: 0)
    data.append(fieldFallbackLittleEndianData(WCHAR(0x0041)))
    return data
}

private func fieldFallbackInvalidUnicodeHyperlinkPayload() -> Data {
    var data = fieldFallbackHyperlinkPrefix(urlLength: 2, prefix: 0xFF)
    data.append(fieldFallbackLittleEndianData(WCHAR(0x0041)))
    data.append(fieldFallbackLittleEndianData(WCHAR(0xD800)))
    return data
}

private func fieldFallbackHyperlinkPrefix(urlLength: WORD, prefix: BYTE) -> Data {
    var data = Data()
    data.append(fieldFallbackLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
    data.append(fieldFallbackLittleEndianData(UInt32(0)))
    data.append(fieldFallbackLittleEndianData(prefix))
    data.append(fieldFallbackLittleEndianData(urlLength))
    return data
}

private func fieldFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
