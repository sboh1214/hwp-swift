@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OtherControlCodablePreservationTests: XCTestCase {
    func testOtherControlInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        var payload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        payload.append(rawTrailing)
        var prefixedPayload = Data([0xEF])
        prefixedPayload.append(payload)
        let slicedPayload = prefixedPayload.dropFirst()
        let ctrlDataPayload = Data([0xAA, 0xBB])
        let ctrlData = HwpRecord(
            tagId: HwpSectionTag.ctrlData.rawValue,
            level: 2,
            payload: ctrlDataPayload
        )
        let unknownPayload = Data([0xCC])
        let unknownChild = HwpRecord(tagId: 0x2FF, level: 2, payload: unknownPayload)
        var reader = DataReader(slicedPayload)

        let control = try HwpOtherControl(&reader, [ctrlData, unknownChild])

        expect(control.ctrlId) == .bookmark
        expect(control.rawPayload) == slicedPayload
        expect(control.rawTrailing) == rawTrailing
        expect(control.ctrlDataRecords.map(\.rawPayload)) == [ctrlDataPayload]
        expect(control.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testCtrlDataChildrenSurviveCtrlIdCodableRoundTrip() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        var rawPayload = littleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        rawPayload.append(rawTrailing)
        let ctrlData = HwpRecord(
            tagId: HwpSectionTag.ctrlData.rawValue,
            level: 2,
            payload: Data([0xAA, 0xBB])
        )
        ctrlData.children = [HwpRecord(tagId: 0x2FE, level: 3, payload: Data([0xCC]))]
        let unknownChild = HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xDD]))
        unknownChild.children = [HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xEE]))]
        let ctrlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        ctrlRecord.children = [ctrlData, unknownChild]

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                ctrlRecord,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .bookmark(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected bookmark control")
        }

        let roundTripped = try roundTrippedBookmarkControl(control)

        expect(roundTripped.rawPayload) == rawPayload
        expect(roundTripped.rawTrailing) == rawTrailing
        expect(roundTripped.ctrlDataRecords.map(\.rawPayload)) == [Data([0xAA, 0xBB])]
        expect(roundTripped.ctrlDataRecords.first?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 3, payload: Data([0xCC])),
        ]
        expect(roundTripped.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2FF,
                level: 2,
                payload: Data([0xDD]),
                children: [
                    expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xEE])),
                ]
            ),
        ]
    }
}

private func roundTrippedBookmarkControl(_ control: HwpOtherControl) throws -> HwpOtherControl {
    let decoded = try JSONDecoder().decode(
        HwpCtrlId.self,
        from: JSONEncoder().encode(HwpCtrlId.bookmark(control))
    )
    guard case let .bookmark(roundTripped) = decoded else {
        throw HwpError.invalidCtrlId(ctrlId: control.ctrlId.rawValue)
    }
    return roundTripped
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
