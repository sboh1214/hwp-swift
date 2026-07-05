@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeControlOLEPreservationTests: XCTestCase {
    func testShapeComponentOLEPreservesRawPayloadAndOptionalBinaryDataId() throws {
        let payload = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(Int32(0)),
            littleEndianData(Int32(0)),
            littleEndianData(UInt16(3)),
            Data([0xAA, 0xBB])
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: payload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])))

        let ole = try HwpShapeComponentOLE.load(record)

        expect(ole.rawPayload) == payload
        expect(ole.binaryDataId) == 3
        expect(ole.rawTrailing) == Data(payload.dropFirst(4))
        expect(ole.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])),
        ]
    }

    func testShapeComponentOLEPreservesShortPayloadWithoutBinaryDataId() throws {
        let rawPayload = Data([0xAA, 0xBB, 0xCC])
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: rawPayload
        )

        let ole = try HwpShapeComponentOLE.load(record)

        expect(ole.rawPayload) == rawPayload
        expect(ole.binaryDataId).to(beNil())
        expect(ole.rawTrailing).to(beNil())
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
