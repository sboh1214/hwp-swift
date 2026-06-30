@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class EquationEditStabilityTests: XCTestCase {
    func testEquationEditPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawPayload = concatenatedData(equationEditPayload(text: "y=2"), Data([0xCC, 0xDD]))
        let slicedPayload = concatenatedData(Data([0xFE, 0xED]), rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: slicedPayload
        )

        let edit = try HwpEquationEdit.load(record)

        let expected = ExpectedEquationEdit(
            rawPayload: slicedPayload,
            equationTextLength: 3,
            equationTextLengthRawPayload: Data([0x03, 0x00]),
            equationText: "y=2",
            equationTextRawPayload: Data([0x79, 0x00, 0x3D, 0x00, 0x32, 0x00]),
            rawTrailing: Data([0xCC, 0xDD])
        )
        assertEquationEdit(edit, matches: expected)

        let decoded = try roundTrippedEquationEdit(edit)

        expect(decoded) == edit
        assertEquationEdit(decoded, matches: expected)
    }

    func testEquationEditPreservesInvalidTextAsRawPayload() throws {
        let rawTrailing = Data([0xAA, 0xBB])
        let rawPayload = concatenatedData(
            Data([0x00, 0x00, 0x00, 0x00]),
            littleEndianData(UInt16(1)),
            littleEndianData(WCHAR(0xD800)),
            rawTrailing
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )

        let edit = try HwpEquationEdit.load(record)

        let expected = ExpectedEquationEdit(
            rawPayload: rawPayload,
            equationTextLength: 1,
            equationTextLengthRawPayload: Data([0x01, 0x00]),
            equationText: nil,
            equationTextRawPayload: littleEndianData(WCHAR(0xD800)),
            rawTrailing: rawTrailing
        )
        assertEquationEdit(edit, matches: expected)

        let decoded = try roundTrippedEquationEdit(edit)

        expect(decoded) == edit
        assertEquationEdit(decoded, matches: expected)
    }

    func testEquationEditTruncatedTextHasNoRawTrailing() throws {
        let rawPayload = concatenatedData(
            Data([0x00, 0x00, 0x00, 0x00]),
            littleEndianData(UInt16(4)),
            littleEndianData(WCHAR(0x0078))
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )

        let edit = try HwpEquationEdit.load(record)

        let expected = ExpectedEquationEdit(
            rawPayload: rawPayload,
            equationTextLength: 4,
            equationTextLengthRawPayload: Data([0x04, 0x00]),
            equationText: nil,
            equationTextRawPayload: nil,
            rawTrailing: nil
        )
        assertEquationEdit(edit, matches: expected)

        let decoded = try roundTrippedEquationEdit(edit)

        expect(decoded) == edit
        assertEquationEdit(decoded, matches: expected)
    }

    func testEquationEditMissingTextLengthPreservesOnlyProperty() throws {
        let rawPayload = Data([0x01, 0x00, 0x00, 0x00])
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )

        let edit = try HwpEquationEdit.load(record)

        expect(edit.rawPayload) == rawPayload
        expect(edit.property) == 1
        expect(edit.propertyRawPayload) == rawPayload
        expect(edit.equationTextLength).to(beNil())
        expect(edit.equationTextLengthRawPayload).to(beNil())
        expect(edit.rawTrailing).to(beNil())
    }

    func testEquationEditPartialLayoutStopsAtLastCompleteField() throws {
        let textColor = UInt32(0x00AA_BBCC)
        let textColorBytes = littleEndianData(textColor)
        let baselineBytes = littleEndianData(UInt16(bitPattern: Int16(-12)))
        let unknownAfterBaselineBytes = littleEndianData(UInt16(0x2211))
        let versionInfo = hwpStringPayload("Equation")
        let truncatedFontName = concatenatedData(
            littleEndianData(UInt16(2)),
            littleEndianData(WCHAR(0x0048))
        )

        let missingTextColor = try equationEdit(
            layoutTrailing: littleEndianData(HWPUNIT(2400))
        )
        expect(missingTextColor.letterSize) == 2400
        expect(missingTextColor.textColorRawValue).to(beNil())

        let missingBaseline = try equationEdit(
            layoutTrailing: concatenatedData(littleEndianData(HWPUNIT(2400)), textColorBytes)
        )
        expect(missingBaseline.textColorRawValue) == textColor
        expect(missingBaseline.baseline).to(beNil())

        let missingUnknownAfterBaseline = try equationEdit(
            layoutTrailing: concatenatedData(
                littleEndianData(HWPUNIT(2400)),
                textColorBytes,
                baselineBytes
            )
        )
        expect(missingUnknownAfterBaseline.baseline) == -12
        expect(missingUnknownAfterBaseline.unknownAfterBaseline).to(beNil())

        let missingVersionInfo = try equationEdit(
            layoutTrailing: concatenatedData(
                littleEndianData(HWPUNIT(2400)),
                textColorBytes,
                baselineBytes,
                unknownAfterBaselineBytes
            )
        )
        expect(missingVersionInfo.unknownAfterBaseline) == UInt16(0x2211)
        expect(missingVersionInfo.versionInfo).to(beNil())

        let truncatedFont = try equationEdit(
            layoutTrailing: concatenatedData(
                littleEndianData(HWPUNIT(2400)),
                textColorBytes,
                baselineBytes,
                unknownAfterBaselineBytes,
                versionInfo,
                truncatedFontName
            )
        )
        expect(truncatedFont.versionInfo) == "Equation"
        expect(truncatedFont.fontName).to(beNil())
    }
}

private func roundTrippedEquationEdit(_ edit: HwpEquationEdit) throws -> HwpEquationEdit {
    let encoded = try JSONEncoder().encode(edit)
    return try JSONDecoder().decode(HwpEquationEdit.self, from: encoded)
}

private struct ExpectedEquationEdit {
    let rawPayload: Data
    let equationTextLength: UInt16?
    let equationTextLengthRawPayload: Data?
    let equationText: String?
    let equationTextRawPayload: Data?
    let rawTrailing: Data?
}

private func assertEquationEdit(_ edit: HwpEquationEdit, matches expected: ExpectedEquationEdit) {
    expect(edit.rawPayload) == expected.rawPayload
    expect(edit.equationTextLength) == expected.equationTextLength
    if let equationTextLengthRawPayload = expected.equationTextLengthRawPayload {
        expect(edit.equationTextLengthRawPayload) == equationTextLengthRawPayload
    } else {
        expect(edit.equationTextLengthRawPayload).to(beNil())
    }
    if let equationText = expected.equationText {
        expect(edit.equationText) == equationText
    } else {
        expect(edit.equationText).to(beNil())
    }
    if let equationTextRawPayload = expected.equationTextRawPayload {
        expect(edit.equationTextRawPayload) == equationTextRawPayload
    } else {
        expect(edit.equationTextRawPayload).to(beNil())
    }
    if let rawTrailing = expected.rawTrailing {
        expect(edit.rawTrailing) == rawTrailing
    } else {
        expect(edit.rawTrailing).to(beNil())
    }
    expect(edit.unknownChildren).to(beEmpty())
}

private func equationEdit(layoutTrailing: Data) throws -> HwpEquationEdit {
    let record = HwpRecord(
        tagId: HwpSectionTag.eqEdit.rawValue,
        level: 2,
        payload: equationEditPayload(text: "x", layoutTrailing: layoutTrailing)
    )
    return try HwpEquationEdit.load(record)
}

private func equationEditPayload(text: String, layoutTrailing: Data = Data()) -> Data {
    let values = Array(text.utf16)
    return concatenatedData(
        Data([0x00, 0x00, 0x00, 0x00]),
        littleEndianData(UInt16(values.count)),
        values.reduce(into: Data()) { data, value in
            data.append(littleEndianData(value))
        },
        layoutTrailing
    )
}

private func hwpStringPayload(_ string: String) -> Data {
    string.utf16.reduce(into: littleEndianData(UInt16(string.utf16.count))) { data, value in
        data.append(littleEndianData(value))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
