@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlNumberingTests: XCTestCase {
    func testAutoAndNewNumberControlsExposeParsedNumberingInfo() throws {
        for ctrlId in [HwpOtherCtrlId.autoNumber, .newNumber] {
            let rawTrailing = littleEndianData(UInt32(2))
                + littleEndianData(UInt32(7))
                + littleEndianData(UInt32(0x0029_0000))
            var rawPayload = littleEndianData(ctrlId.rawValue)
            rawPayload.append(rawTrailing)
            let record = HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: rawPayload
            )

            let control = try HwpOtherControl.load(record)

            expect(control.ctrlId) == ctrlId
            expect(control.numberingInfo?.kind) == 2
            expect(control.numberingInfo?.number) == 7
            expect(control.numberingInfo?.format) == 0x0029_0000
            expect(control.numberingInfo?.rawTrailing) == Data()
            expect(control.rawPayload) == rawPayload
            expect(control.rawTrailing) == rawTrailing
        }
    }

    func testShortNumberingPayloadIsPreservedWithoutParsedNumberingInfo() throws {
        let rawTrailing = littleEndianData(UInt32(2)) + Data([0xAA, 0xBB])
        var rawPayload = littleEndianData(HwpOtherCtrlId.autoNumber.rawValue)
        rawPayload.append(rawTrailing)
        let unknownChild = HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xCC]))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [unknownChild]

        let control = try HwpOtherControl.load(record)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(HwpCtrlId.autoNumber(control))
        )

        expect(control.ctrlId) == .autoNumber
        expect(control.numberingInfo).to(beNil())
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xCC])),
        ]

        guard case let .autoNumber(roundTripped) = decoded else {
            return fail("Expected autoNumber after Codable round-trip")
        }
        expect(roundTripped.numberingInfo).to(beNil())
        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
        expect(roundTripped.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xCC])),
        ]
    }

    func testNumberingInfoPreservesExtraTrailingBytes() throws {
        let extraTrailing = Data([0xAA, 0xBB])
        let rawTrailing = littleEndianData(UInt32(2))
            + littleEndianData(UInt32(7))
            + littleEndianData(UInt32(0x0029_0000))
            + extraTrailing
        var rawPayload = littleEndianData(HwpOtherCtrlId.autoNumber.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let control = try HwpOtherControl.load(record)

        expect(control.numberingInfo?.kind) == 2
        expect(control.numberingInfo?.number) == 7
        expect(control.numberingInfo?.format) == 0x0029_0000
        expect(control.numberingInfo?.rawTrailing) == extraTrailing
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
    }

    func testNumberingInfoWithNonZeroStartIndexPayloadPreservesParsedFields() throws {
        let rawTrailing = littleEndianData(UInt32(4))
            + littleEndianData(UInt32(15))
            + littleEndianData(UInt32(0x0031_0000))
        let rawPayload = littleEndianData(HwpOtherCtrlId.autoNumber.rawValue) + rawTrailing
        let slicedPayload = (Data([0xFF, 0xEE]) + rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: slicedPayload
        )

        let control = try HwpOtherControl.load(record)

        expect(control.ctrlId) == .autoNumber
        expect(control.numberingInfo?.kind) == 4
        expect(control.numberingInfo?.number) == 15
        expect(control.numberingInfo?.format) == 0x0031_0000
        expect(control.numberingInfo?.rawTrailing) == Data()
        expect(control.rawPayload) == rawPayload
        expect(control.rawTrailing) == rawTrailing
    }

    func testParagraphDispatchPreservesShortNumberingControlsAsTypedOtherControls() throws {
        for ctrlId in [HwpOtherCtrlId.autoNumber, .newNumber] {
            let rawTrailing = littleEndianData(UInt32(2)) + Data([0xAA, 0xBB])
            var rawPayload = littleEndianData(ctrlId.rawValue)
            rawPayload.append(rawTrailing)
            let controlRecord = HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: rawPayload
            )
            controlRecord.children = [
                HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xCC])),
            ]

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
                    controlRecord,
                ]),
                HwpVersion(5, 0, 1, 1)
            )
            let control = try extractedNumberingControl(
                from: paragraph.ctrlHeaderArray?.first,
                expected: ctrlId
            )

            expect(control.ctrlId) == ctrlId
            expect(control.numberingInfo).to(beNil())
            expect(control.rawPayload) == rawPayload
            expect(control.rawTrailing) == rawTrailing
            expect(control.unknownChildren) == [
                expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xCC])),
            ]
        }
    }

    func testParagraphDispatchAndCodablePreserveParsedNumberingInfo() throws {
        for ctrlId in [HwpOtherCtrlId.autoNumber, .newNumber] {
            let extraTrailing = Data([0xAA, 0xBB, 0xCC])
            let rawTrailing = littleEndianData(UInt32(3))
                + littleEndianData(UInt32(12))
                + littleEndianData(UInt32(0x0031_0000))
                + extraTrailing
            let roundTrip = try parsedAndRoundTrippedNumberingControl(
                ctrlId: ctrlId,
                rawTrailing: rawTrailing
            )
            expectParsedNumberingInfo(
                roundTrip.control,
                rawPayload: roundTrip.rawPayload,
                rawTrailing: rawTrailing
            )
            expectParsedNumberingInfo(
                roundTrip.roundTripped,
                rawPayload: roundTrip.rawPayload,
                rawTrailing: rawTrailing
            )
        }
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func extractedNumberingControl(
    from ctrlId: HwpCtrlId?,
    expected expectedCtrlId: HwpOtherCtrlId
) throws -> HwpOtherControl {
    switch (expectedCtrlId, ctrlId) {
    case let (.autoNumber, .some(.autoNumber(control))),
         let (.newNumber, .some(.newNumber(control))):
        return control
    default:
        fail("Expected \(expectedCtrlId) control, got \(String(describing: ctrlId))")
        throw HwpError.invalidCtrlId(ctrlId: expectedCtrlId.rawValue)
    }
}

private struct NumberingRoundTrip {
    let control: HwpOtherControl
    let roundTripped: HwpOtherControl
    let rawPayload: Data
}

private func parsedAndRoundTrippedNumberingControl(
    ctrlId: HwpOtherCtrlId,
    rawTrailing: Data
) throws -> NumberingRoundTrip {
    var rawPayload = littleEndianData(ctrlId.rawValue)
    rawPayload.append(rawTrailing)
    let controlRecord = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    controlRecord.children = [
        HwpRecord(tagId: 0x2FD, level: 2, payload: Data([0xDD])),
    ]

    let paragraph = try HwpParagraph.load(
        paragraphRecord(children: paragraphChildRecords(with: controlRecord)),
        HwpVersion(5, 0, 1, 1)
    )
    let encoded = try JSONEncoder().encode(paragraph.ctrlHeaderArray?.first)
    let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

    return try NumberingRoundTrip(
        control: extractedNumberingControl(
            from: paragraph.ctrlHeaderArray?.first,
            expected: ctrlId
        ),
        roundTripped: extractedNumberingControl(from: decoded, expected: ctrlId),
        rawPayload: rawPayload
    )
}

private func paragraphChildRecords(with controlRecord: HwpRecord) -> [HwpRecord] {
    [
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
        controlRecord,
    ]
}

private func expectParsedNumberingInfo(
    _ control: HwpOtherControl,
    rawPayload: Data,
    rawTrailing: Data
) {
    expect(control.numberingInfo?.kind) == 3
    expect(control.numberingInfo?.number) == 12
    expect(control.numberingInfo?.format) == 0x0031_0000
    expect(control.numberingInfo?.rawTrailing) == Data([0xAA, 0xBB, 0xCC])
    expect(control.rawPayload) == rawPayload
    expect(control.rawTrailing) == rawTrailing
    expect(control.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FD, level: 2, payload: Data([0xDD])),
    ]
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
