@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParaShapeRawPayloadTests: XCTestCase {
    func testParaShapePreservesRawPayloadWithoutChangingEquality() throws {
        let payload = paraShapePayload()

        let paraShape = try HwpParaShape.load(payload, HwpVersion())
        var sameParaShape = paraShape
        sameParaShape.rawPayload = Data([0xCA, 0xFE])

        expect(paraShape.rawPayload) == payload
        expect(paraShape.property1) == 0x0102_0304
        expect(paraShape.marginLeft) == 10
        expect(paraShape.tabDefId) == 3
        expect(paraShape.lineSpacing2) == 170
        expect(paraShape.unknown) == 0x0A0B_0C0D
        expect(sameParaShape) == paraShape
    }

    func testParaShapeInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = paraShapePayload()
        let slicedPayload = (Data([0xFF, 0xEE]) + payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let paraShape = try HwpParaShape(&reader, HwpVersion())

        expect(paraShape.rawPayload) == slicedPayload
        expect(paraShape.property1) == 0x0102_0304
        expect(paraShape.unknown) == 0x0A0B_0C0D
        expect(reader.isEOF) == true
    }

    func testParaShapeRejectsTrailingBytesWithTypedError() {
        let payload = paraShapePayload() + Data([0xFF])

        expect {
            _ = try HwpParaShape.load(payload, HwpVersion())
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpParaShape"
            expect(remain) == 1
        })
    }
}

private func paraShapePayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x0102_0304)))
    data.append(littleEndianData(Int32(10)))
    data.append(littleEndianData(Int32(20)))
    data.append(littleEndianData(Int32(-30)))
    data.append(littleEndianData(Int32(40)))
    data.append(littleEndianData(Int32(50)))
    data.append(littleEndianData(Int32(160)))
    data.append(littleEndianData(UInt16(3)))
    data.append(littleEndianData(UInt16(4)))
    data.append(littleEndianData(UInt16(5)))
    data.append(littleEndianData(Int16(6)))
    data.append(littleEndianData(Int16(7)))
    data.append(littleEndianData(Int16(8)))
    data.append(littleEndianData(Int16(9)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(170)))
    data.append(littleEndianData(UInt32(0x0A0B_0C0D)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
