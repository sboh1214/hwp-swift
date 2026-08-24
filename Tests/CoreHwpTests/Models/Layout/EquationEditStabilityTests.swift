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

    func testViewerModeEmptiesEquationNestedRawSlicesButKeepsTypedValues() throws {
        let payload = fullyPopulatedEquationPayload()
        let preserved = try loadEquationEdit(payload, options: .default)
        let viewer = try loadEquationEdit(payload, options: .viewer)

        expect(viewer.property) == preserved.property
        expect(viewer.equationTextLength) == preserved.equationTextLength
        expect(viewer.equationText) == preserved.equationText
        expect(viewer.letterSize) == preserved.letterSize
        expect(viewer.textColorRawValue) == preserved.textColorRawValue
        expect(viewer.baseline) == preserved.baseline
        expect(viewer.unknownAfterBaseline) == preserved.unknownAfterBaseline
        expect(viewer.versionInfoLength) == preserved.versionInfoLength
        expect(viewer.versionInfo) == preserved.versionInfo
        expect(viewer.fontNameLength) == preserved.fontNameLength
        expect(viewer.fontName) == preserved.fontName
        expect(viewer.equationText).notTo(beNil())
        expect(viewer.fontName).notTo(beNil())

        assertEquationNestedRawSlicesEmptiedByViewer(preserved: preserved, viewer: viewer)
        expect(preserved.rawPayload).notTo(beEmpty())
        expect(viewer.rawPayload).to(beEmpty())
    }
}

private func loadEquationEdit(_ payload: Data, options: HwpLoadOptions) throws -> HwpEquationEdit {
    try HwpEquationEdit.load(HwpRecord(
        tagId: HwpSectionTag.eqEdit.rawValue,
        level: 2,
        payload: payload,
        options: options
    ))
}

private func fullyPopulatedEquationPayload() -> Data {
    let layoutTrailing = concatenatedData(
        littleEndianData(HWPUNIT(2400)),
        littleEndianData(UInt32(0x00AA_BBCC)),
        littleEndianData(UInt16(bitPattern: Int16(-12))),
        littleEndianData(UInt16(0x2211)),
        hwpStringPayload("Equation"),
        hwpStringPayload("HYSMyeongJo"),
        Data([0xCC, 0xDD])
    )
    return equationEditPayload(text: "y=2", layoutTrailing: layoutTrailing)
}

private func assertEquationNestedRawSlicesEmptiedByViewer(
    preserved: HwpEquationEdit,
    viewer: HwpEquationEdit
) {
    let slices: [(KeyPath<HwpEquationEdit, Data?>, String)] = [
        (\.propertyRawPayload, "propertyRawPayload"),
        (\.equationTextLengthRawPayload, "equationTextLengthRawPayload"),
        (\.equationTextRawPayload, "equationTextRawPayload"),
        (\.letterSizeRawPayload, "letterSizeRawPayload"),
        (\.textColorRawPayload, "textColorRawPayload"),
        (\.baselineRawPayload, "baselineRawPayload"),
        (\.unknownAfterBaselineRawPayload, "unknownAfterBaselineRawPayload"),
        (\.versionInfoLengthRawPayload, "versionInfoLengthRawPayload"),
        (\.versionInfoRawPayload, "versionInfoRawPayload"),
        (\.fontNameLengthRawPayload, "fontNameLengthRawPayload"),
        (\.fontNameRawPayload, "fontNameRawPayload"),
        (\.rawTrailing, "rawTrailing"),
    ]
    for (slice, label) in slices {
        expectRawSliceEmptiedByViewer(
            preserved: preserved[keyPath: slice],
            viewer: viewer[keyPath: slice],
            label
        )
    }
}

private func expectRawSliceEmptiedByViewer(preserved: Data?, viewer: Data?, _ label: String) {
    expect(preserved ?? Data()).notTo(beEmpty(), description: "\(label): default는 원문 보존")
    expect(viewer ?? Data()).to(beEmpty(), description: "\(label): viewer는 원문 제거")
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
