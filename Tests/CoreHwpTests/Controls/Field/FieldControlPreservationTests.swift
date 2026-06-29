@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FieldControlPreservationTests: XCTestCase {
    func testFieldControlInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let parameter = "MEMO/1"
        var payload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        payload.append(fieldParameterTrailing(parameter))
        let slicedPayload = concatenatedData(Data([0xEF]), payload).dropFirst()
        let childPayload = Data([0xAA])
        let child = HwpRecord(tagId: 0x2FD, level: 2, payload: childPayload)
        var reader = DataReader(slicedPayload)

        let control = try HwpFieldControl(&reader, [child])

        expect(control.ctrlId) == .unknown
        expect(control.rawPayload) == slicedPayload
        expect(control.rawTrailing) == fieldParameterTrailing(parameter)
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(control.fieldParameter) == parameter
        expect(control.memoParameter?.rawValue) == parameter
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: childPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testFieldControlsPreserveRawPayloadTrailingBytesAndChildren() throws {
        expect(allKnownFieldControlIds) == HwpFieldCtrlId.allCases

        for ctrlId in HwpFieldCtrlId.allCases {
            let label = String(describing: ctrlId)
            try assertFieldControlPreservation(ctrlId: ctrlId, label: label)
        }
    }

    func testFieldControlExtractsOptionalParameterText() throws {
        let parameter = "MEMO/65535/1/239261456/31259664/sboh/\\;;"
        let rawTrailing = fieldParameterTrailing(parameter)
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpFieldControl.load(record)

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .memo
        expect(control.isMemoField) == true
        expect(control.isRevisionField) == false
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawTrailing) == Data()
        expect(control.memoParameter?.rawValue) == parameter
        expect(control.memoParameter?.marker) == "MEMO"
        expect(control.memoParameter?.components) == [
            "MEMO", "65535", "1", "239261456", "31259664", "sboh", "\\;;",
        ]
        expect(control.memoParameter?.fields) == [
            "65535", "1", "239261456", "31259664", "sboh", "\\;;",
        ]
        expect(control.memoParameter?.author) == "sboh"
        expect(control.memoParameter?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
    }

    func testParagraphClassifiesUnknownFieldWithMemoParameterAsMemoControl() throws {
        let parameter = "MEMO/65535/1/239261456/31259664/sboh/\\;;"
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(fieldParameterTrailing(parameter))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .memo(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected unknown MEMO parameter field to be classified as memo")
        }

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .memo
        expect(control.isMemoField) == true
        expect(control.isRevisionField) == false
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawTrailing) == Data()
        expect(control.memoParameter?.rawValue) == parameter
        expect(control.memoParameter?.author) == "sboh"
        expect(control.memoParameter?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
    }

    func testParagraphClassifiesShortMemoParameterWithoutAuthorAsMemoControl() throws {
        let parameter = "MEMO/1"
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(fieldParameterTrailing(parameter))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .memo(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected short MEMO parameter field to be classified as memo")
        }

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .memo
        expect(control.isMemoField) == true
        expect(control.isRevisionField) == false
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawTrailing) == Data()
        expect(control.memoParameter?.rawValue) == parameter
        expect(control.memoParameter?.components) == ["MEMO", "1"]
        expect(control.memoParameter?.fields) == ["1"]
        expect(control.memoParameter?.author).to(beNil())
        expect(control.memoParameter?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
    }

    func testParagraphDoesNotClassifyNonMemoParameterAsMemoControl() throws {
        let parameter = "DATE/2026/06/17"
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(fieldParameterTrailing(parameter))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .field(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected unknown non-MEMO parameter field to stay generic field")
        }

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .field
        expect(control.isMemoField) == false
        expect(control.isRevisionField) == false
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawTrailing) == Data()
        expect(control.memoParameter).to(beNil())
        expect(control.rawPayload) == rawPayload
    }

    func testMemoParameterSurvivesCtrlIdCodableRoundTrip() throws {
        let parameter = "MEMO/65535/1/239261456/31259664/sboh/\\;;"
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(fieldParameterTrailing(parameter))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        let control = try HwpCtrlId.memo(HwpFieldControl.load(record))

        let data = try JSONEncoder().encode(control)
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: data)

        guard case let .memo(decodedControl) = decoded else {
            return fail("Expected memo control after Codable round-trip")
        }
        expect(decoded) == control
        expect(decodedControl.fieldParameterHeaderValue) == 0x8001
        expect(decodedControl.memoParameter?.rawValue) == parameter
        expect(decodedControl.memoParameter?.components) == [
            "MEMO", "65535", "1", "239261456", "31259664", "sboh", "\\;;",
        ]
        expect(decodedControl.memoParameter?.author) == "sboh"
        expect(decodedControl.memoParameter?.rawTrailing) == Data()
        expect(decodedControl.rawPayload) == rawPayload
    }

    func testParagraphPreservesTruncatedHyperlinkAsGenericFieldControl() throws {
        let rawPayload = truncatedHyperlinkPayload()
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xDD])))

        expect {
            _ = try HwpHyperlink.load(record)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 6
            expect(actual) == 2
        })

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .field(field) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated hyperlink to be preserved as field")
        }

        expect(field.ctrlId) == .hyperLink
        expect(field.semanticKind) == .field
        expect(field.isRevisionField) == false
        expect(field.rawPayload) == rawPayload
        expect(field.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(field.fieldParameter).to(beNil())
        expect(field.fieldParameterRawTrailing).to(beNil())
        expect(field.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xDD])),
        ]
    }

    func testParagraphPreservesInvalidUnicodeHyperlinkAsGenericFieldControl() throws {
        let rawPayload = invalidUnicodeHyperlinkPayload()
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xEE])))

        expect {
            _ = try HwpHyperlink.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .field(field) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected invalid unicode hyperlink to be preserved as field")
        }

        expect(field.ctrlId) == .hyperLink
        expect(field.semanticKind) == .field
        expect(field.rawPayload) == rawPayload
        expect(field.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(field.fieldParameter).to(beNil())
        expect(field.fieldParameterRawTrailing).to(beNil())
        expect(field.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xEE])),
        ]
    }
}

private func fieldParameterTrailing(_ parameter: String) -> Data {
    var data = Data()
    let chars = [WCHAR](parameter)
    data.append(littleEndianData(UInt32(0x8001)))
    data.append(littleEndianData(WORD(chars.count)))
    for char in chars {
        data.append(littleEndianData(char))
    }
    return data
}

private func assertFieldControlPreservation(
    ctrlId: HwpFieldCtrlId,
    label: String
) throws {
    let rawTrailing = Data(label.utf8)
    var rawPayload = littleEndianData(ctrlId.rawValue)
    rawPayload.append(rawTrailing)
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children.append(HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xAA])))

    let paragraph = try HwpParagraph.load(
        paragraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            record,
        ]),
        HwpVersion(5, 0, 1, 1)
    )

    let field = try extractedField(from: paragraph, expectedCtrlId: ctrlId, label: label)
    expect(field.ctrlId) == ctrlId
    expect(field.semanticKind) == semanticKind(for: ctrlId)
    expect(field.isMemoField) == (ctrlId == .memo)
    expect(field.isRevisionField) == ctrlId.isRevision
    expect(field.rawTrailing) == rawTrailing
    expect(field.fieldParameter).to(beNil())
    expect(field.fieldParameterRawTrailing).to(beNil())
    expect(field.memoParameter).to(beNil())
    expect(field.rawPayload) == rawPayload
    expect(field.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xAA])),
    ]
}

private let allKnownFieldControlIds: [HwpFieldCtrlId] = [
    .unknown,
    .date,
    .docDate,
    .path,
    .bookmark,
    .mailMerge,
    .crossRef,
    .formula,
    .clickHere,
    .summary,
    .userInfo,
    .hyperLink,
    .revisionSign,
    .revisionDelete,
    .revisionAttach,
    .revisionClipping,
    .revisionSawtooth,
    .revisionThinking,
    .revisionPraise,
    .revisionLine,
    .revisionSimpleChange,
    .revisionHyperLink,
    .revisionLineAttach,
    .revisionLineLink,
    .revisionLineRansfer,
    .revisionRightMove,
    .revisionLeftMove,
    .revisionTransfer,
    .revisionSimpleInsert,
    .revisionSplit,
    .revisionChange,
    .memo,
    .privateInfoSecurity,
    .tableOfContents,
]

private func extractedField(
    from paragraph: HwpParagraph,
    expectedCtrlId ctrlId: HwpFieldCtrlId,
    label: String
) throws -> HwpFieldControl {
    switch paragraph.ctrlHeaderArray?.first {
    case let .memo(control) where ctrlId == .memo:
        return control
    case let .revision(control) where ctrlId.isRevision:
        return control
    case let .field(control) where ctrlId != .memo && !ctrlId.isRevision:
        return control
    default:
        fail("Expected field-like control for \(label)")
        throw HwpError.invalidCtrlId(ctrlId: ctrlId.rawValue)
    }
}

private func semanticKind(for ctrlId: HwpFieldCtrlId) -> HwpFieldControlKind {
    if ctrlId == .memo {
        return .memo
    }
    if ctrlId.isRevision {
        return .revision
    }
    return .field
}

private func truncatedHyperlinkPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(BYTE(0)))
    data.append(littleEndianData(WORD(3)))
    data.append(littleEndianData(WCHAR(0x0041)))
    return data
}

private func invalidUnicodeHyperlinkPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(BYTE(0xFF)))
    data.append(littleEndianData(WORD(2)))
    data.append(littleEndianData(WCHAR(0x0041)))
    data.append(littleEndianData(WCHAR(0xD800)))
    return data
}

private func paragraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: paragraphHeaderPayload()
    )
    record.children = children
    return record
}

private func paragraphHeaderPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x8000_0000)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt32(1)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
