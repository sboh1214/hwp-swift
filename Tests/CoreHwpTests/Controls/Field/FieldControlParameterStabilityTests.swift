@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FieldControlParameterStabilityTests: XCTestCase {
    func testInvalidFieldCtrlIdThrowsTypedError() {
        let invalidCtrlId: UInt32 = 0x1234_5678
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: concatenatedData(littleEndianData(invalidCtrlId), Data([0xCA, 0xFE]))
        )

        expect {
            _ = try HwpFieldControl.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidCtrlId(ctrlId) = error else {
                return fail("Expected invalidCtrlId, got \(error)")
            }
            expect(ctrlId) == invalidCtrlId
        })
    }

    func testInvalidFieldParameterTextPreservesRawPayloadAsGenericField() throws {
        let fixture = invalidFieldParameterRecord()

        let control = try HwpFieldControl.load(fixture.record)

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .field
        expect(control.isMemoField) == false
        expect(control.isRevisionField) == false
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(control.fieldParameterCharacterCount) == 1
        expect(control.fieldParameterLengthRawPayload) == Data([1, 0])
        expect(control.fieldParameter).to(beNil())
        expect(control.fieldParameterRawPayload).to(beNil())
        expect(control.fieldParameterRawTrailing).to(beNil())
        expect(control.memoParameter).to(beNil())
        expect(control.rawPayload) == fixture.rawPayload
        expect(control.rawTrailing) == fixture.rawTrailing
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xCC])),
        ]
    }

    func testParagraphPreservesInvalidFieldParameterTextAsGenericFieldControl() throws {
        let fixture = invalidFieldParameterRecord()
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
                fixture.record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .field(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected malformed field parameter to stay generic field")
        }

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .field
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(control.fieldParameterCharacterCount) == 1
        expect(control.fieldParameterLengthRawPayload) == Data([1, 0])
        expect(control.fieldParameter).to(beNil())
        expect(control.fieldParameterRawPayload).to(beNil())
        expect(control.fieldParameterRawTrailing).to(beNil())
        expect(control.memoParameter).to(beNil())
        expect(control.rawPayload) == fixture.rawPayload
        expect(control.rawTrailing) == fixture.rawTrailing
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xCC])),
        ]
    }

    func testByteSwappedFieldParameterLengthPreservesRawPayload() throws {
        let parameter = "OK"
        let rawTrailing = concatenatedData(
            littleEndianData(UInt32(0x8001)),
            littleEndianData(WORD(parameter.utf16.count).byteSwapped),
            byteSwappedUTF16Payload(parameter),
            Data([0xAA, 0xBB])
        )
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpFieldControl.load(record)

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .field
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(control.fieldParameterCharacterCount) == 2
        expect(control.fieldParameterLengthRawPayload) == Data([0, 2])
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawPayload) == byteSwappedUTF16Payload(parameter)
        expect(control.fieldParameterRawTrailing) == Data([0xAA, 0xBB])
        expect(control.memoParameter).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
    }

    func testByteSwappedFieldParameterWinsOverGarbledNaturalEndianCandidate() throws {
        let parameter = "M"
        let swappedPayload = byteSwappedUTF16Payload(parameter)
        let naturalCandidatePadding = Data(
            repeating: 0,
            count: Int(WORD(parameter.utf16.count).byteSwapped)
                * MemoryLayout<WCHAR>.size
                - swappedPayload.count
        )
        let rawTrailing = concatenatedData(
            littleEndianData(UInt32(0x8001)),
            littleEndianData(WORD(parameter.utf16.count).byteSwapped),
            swappedPayload,
            naturalCandidatePadding,
            Data([0xAA, 0xBB])
        )
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpFieldControl.load(record)

        expect(control.fieldParameterCharacterCount) == parameter.utf16.count
        expect(control.fieldParameterLengthRawPayload) == Data([0, 1])
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawPayload) == swappedPayload
        expect(control.fieldParameterRawTrailing) ==
            concatenatedData(naturalCandidatePadding, Data([0xAA, 0xBB]))
    }

    func testNaturalEndianFieldParameterWinsOverLongPrintableByteSwappedCandidate() throws {
        let parameter = "A"
        let naturalPayload = utf16Payload(parameter)
        let byteSwappedCandidatePadding = (0 ..< 255).reduce(into: Data()) { data, _ in
            data.append(littleEndianData(WCHAR(0x4200)))
        }
        let rawTrailing = concatenatedData(
            littleEndianData(UInt32(0x8001)),
            littleEndianData(WORD(parameter.utf16.count)),
            naturalPayload,
            byteSwappedCandidatePadding,
            Data([0xAA, 0xBB])
        )
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpFieldControl.load(record)

        expect(control.fieldParameterCharacterCount) == parameter.utf16.count
        expect(control.fieldParameterLengthRawPayload) == Data([1, 0])
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawPayload) == naturalPayload
        expect(control.fieldParameterRawTrailing) ==
            concatenatedData(byteSwappedCandidatePadding, Data([0xAA, 0xBB]))
    }

    func testFieldParameterWithNonZeroStartIndexPreservesMemoMetadata() throws {
        let parameter = "MEMO/1/2/3/4/writer/body"
        let rawTrailing = concatenatedData(fieldParameterTrailing(parameter), Data([0xAA, 0xBB]))
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: slicedPayload
        )

        let control = try HwpFieldControl.load(record)

        expect(control.ctrlId) == .unknown
        expect(control.semanticKind) == .memo
        expect(control.fieldParameterHeaderValue) == 0x8001
        expect(control.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(control.fieldParameterCharacterCount) == parameter.utf16.count
        expect(control.fieldParameterLengthRawPayload) ==
            littleEndianData(WORD(parameter.utf16.count))
        expect(control.fieldParameter) == parameter
        expect(control.fieldParameterRawPayload) == utf16Payload(parameter)
        expect(control.fieldParameterRawTrailing) == Data([0xAA, 0xBB])
        expect(control.memoParameter?.rawValue) == parameter
        expect(control.memoParameter?.rawPayload) == utf16Payload(parameter)
        expect(control.memoParameter?.components) == [
            "MEMO", "1", "2", "3", "4", "writer", "body",
        ]
        expect(control.memoParameter?.fields) == ["1", "2", "3", "4", "writer", "body"]
        expect(control.memoParameter?.author) == "writer"
        expect(control.memoParameter?.rawTrailing) == Data([0xAA, 0xBB])
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
    }

    func testMemoParameterRawPayloadSurvivesCodableRoundTrip() throws {
        let parameter = "MEMO/1/2/3/4/writer/body"
        let rawTrailing = concatenatedData(fieldParameterTrailing(parameter), Data([0xAA, 0xBB]))
        var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let decoded = try decodeRoundTrip(HwpFieldControl.load(record))

        expect(decoded.fieldParameter) == parameter
        expect(decoded.fieldParameterHeaderValue) == 0x8001
        expect(decoded.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
        expect(decoded.fieldParameterCharacterCount) == parameter.utf16.count
        expect(decoded.fieldParameterLengthRawPayload) ==
            littleEndianData(WORD(parameter.utf16.count))
        expect(decoded.fieldParameterRawPayload) == utf16Payload(parameter)
        expect(decoded.fieldParameterRawTrailing) == Data([0xAA, 0xBB])
        expect(decoded.memoParameter?.rawValue) == parameter
        expect(decoded.memoParameter?.rawPayload) == utf16Payload(parameter)
        expect(decoded.memoParameter?.rawTrailing) == Data([0xAA, 0xBB])
        expect(decoded.rawPayload) == rawPayload
        expect(decoded.rawTrailing) == rawTrailing
    }
}

private struct InvalidFieldParameterFixture {
    let record: HwpRecord
    let rawPayload: Data
    let rawTrailing: Data
}

private func invalidFieldParameterRecord() -> InvalidFieldParameterFixture {
    let rawTrailing = concatenatedData(
        littleEndianData(UInt32(0x8001)),
        littleEndianData(WORD(1)),
        littleEndianData(WCHAR(0xD800))
    )
    var rawPayload = littleEndianData(HwpFieldCtrlId.unknown.rawValue)
    rawPayload.append(rawTrailing)
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = [
        HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xCC])),
    ]
    return InvalidFieldParameterFixture(
        record: record,
        rawPayload: rawPayload,
        rawTrailing: rawTrailing
    )
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

private func byteSwappedUTF16Payload(_ string: String) -> Data {
    string.utf16.reduce(into: Data()) { data, codeUnit in
        data.append(littleEndianData(WCHAR(codeUnit).byteSwapped))
    }
}

private func utf16Payload(_ string: String) -> Data {
    string.utf16.reduce(into: Data()) { data, codeUnit in
        data.append(littleEndianData(WCHAR(codeUnit)))
    }
}

private func fieldParameterTrailing(_ parameter: String) -> Data {
    var data = littleEndianData(UInt32(0x8001))
    data.append(littleEndianData(WORD(parameter.utf16.count)))
    for codeUnit in parameter.utf16 {
        data.append(littleEndianData(WCHAR(codeUnit)))
    }
    return data
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}
