@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class CharShapeTests: XCTestCase {
    func testCharShape() throws {
        let hwp = try openHwp(#file, "CharShape")
        let array = hwp.docInfo.idMappings.charShapeArray

        expect(array[0].faceId) == [0, 0, 0, 0, 0, 0, 0]
        expect(array[9].faceScaleX) == Array(repeating: 70, count: 7)
        expect(array[8].faceSpacing) == Array(repeating: 50, count: 7)
        expect(array[10].faceRelativeSize) == Array(repeating: 170, count: 7)
        expect(array[11].faceLocation) == Array(repeating: 30, count: 7)
        expect(array[12].shadowIntervalX) == 10
        expect(array[13].shadowIntervalY) == 10
        expect(array[14].faceColor) == HwpColor(255, 0, 0)
        expect(array[15].underlineColor) == HwpColor(0, 255, 0)
        expect(array[16].shadeColor) == HwpColor(0, 0, 255)
        expect(array[17].shadowColor) == HwpColor(255, 255, 0)
        expect(array[18].strikethroughColor) == HwpColor(0, 255, 255)
    }

    func testCharShapeProperty() throws {
        let hwp = try openHwp(#file, "CharShapeProperty")
        let array = hwp.docInfo.idMappings.charShapeArray

        expect(array[0].property.rawValue) == 0
        expect(array[7].property.isItalic) == true
        expect(array[7].property.rawValue) == 1
        expect(array[8].property.isBold) == true
        expect(array[8].property.rawValue) == 2
        expect(array[9].property.underlineType) == .under
        expect(array[10].property.borderlineType) == .line
        expect(array[11].property.shadowType) == .discontinuous
        expect(array[12].property.shadowType) == .continuous
        expect(array[13].property.isRelief) == true
        expect(array[14].property.isCounterRelief) == true
        expect(array[15].property.isSuperscript) == true
        expect(array[16].property.isSubscript) == true
        expect(array[18].property.rawValue) == 262_152
        // raw 2 — 스펙 미정의 값. 글자 위(3)가 아니다 (#149).
        expect(array[18].property.underlineType) == .undefined2
        expect(array[18].property.strikethrough) == 1
        expect(array[19].property.emphasisType) == .filledCircle
        expect(array[20].property.doesAdjustBlank) == true
        expect(array[21].property.isKerning) == true
    }

    func testCharShapePreservesRawPayloadWithoutChangingEquality() throws {
        let payload = charShapePayload()

        let charShape = try HwpCharShape.load(payload, HwpVersion())
        var sameCharShape = charShape
        sameCharShape.rawPayload = Data([0xCA, 0xFE])

        expect(charShape.rawPayload) == payload
        expect(charShape.faceId) == Array(repeating: 0, count: 7)
        expect(charShape.faceScaleX) == Array(repeating: 100, count: 7)
        expect(charShape.borderFillId) == 2
        expect(charShape.strikethroughColor) == HwpColor(0, 255, 255)
        expect(sameCharShape) == charShape
    }

    func testCharShapeInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let payload = charShapePayload()
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), payload).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let charShape = try HwpCharShape(&reader, HwpVersion())

        expect(charShape.rawPayload) == slicedPayload
        expect(charShape.faceScaleX) == Array(repeating: 100, count: 7)
        expect(charShape.strikethroughColor) == HwpColor(0, 255, 255)
        expect(reader.isEOF) == true
    }

    func testCharShapeRejectsTrailingBytesWithTypedError() {
        let payload = concatenatedData(charShapePayload(), Data([0xFF]))

        expect {
            _ = try HwpCharShape.load(payload, HwpVersion())
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpCharShape"
            expect(remain) == 1
        })
    }
}

private func charShapePayload() -> Data {
    var data = Data()
    for _ in 0 ..< 7 {
        data.append(littleEndianData(WORD(0)))
    }
    data.append(Data(repeating: 100, count: 7))
    data.append(Data(repeating: 0, count: 7))
    data.append(Data(repeating: 100, count: 7))
    data.append(Data(repeating: 0, count: 7))
    data.append(littleEndianData(Int32(1000)))
    data.append(littleEndianData(UInt32(0)))
    data.append(contentsOf: [10, 10])
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt32(0x0000_FF00)))
    data.append(littleEndianData(UInt32(0x00FF_0000)))
    data.append(littleEndianData(UInt32(0x0000_FFFF)))
    data.append(littleEndianData(UInt16(2)))
    data.append(littleEndianData(UInt32(0x00FF_FF00)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
