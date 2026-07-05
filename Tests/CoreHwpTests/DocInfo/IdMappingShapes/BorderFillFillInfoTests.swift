@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BorderFillFillInfoTests: XCTestCase {
    func testFillDecodesSolidFillColorsFromFillInfoBytes() throws {
        let borderFill = try HwpBorderFill.load(borderFillPayload(fillInfo: solidFillInfo()))

        expect(borderFill.fill?.type) == 1
        expect(borderFill.fill?.hasSolidFill) == true
        expect(borderFill.fill?.solidBackgroundColor) == HwpColor(0, 0, 255)
        expect(borderFill.fill?.solidPatternColor) == HwpColor(255, 0, 0)
        expect(borderFill.fill?.solidPatternType) == -1
    }

    func testFillIsNilWhenFillInfoIsEmpty() throws {
        let borderFill = try HwpBorderFill.load(borderFillPayload(fillInfo: Data()))

        expect(borderFill.fillInfo) == []
        expect(borderFill.fill).to(beNil())
    }

    func testSolidColorsAreNilWhenSolidTailIsTruncated() throws {
        // type flag는 단색이지만 색상 payload가 없는 경우
        let borderFill = try HwpBorderFill.load(
            borderFillPayload(fillInfo: littleEndianData(UInt32(1)))
        )

        expect(borderFill.fill?.type) == 1
        expect(borderFill.fill?.hasSolidFill) == true
        expect(borderFill.fill?.solidBackgroundColor).to(beNil())
        expect(borderFill.fill?.solidPatternColor).to(beNil())
        expect(borderFill.fill?.solidPatternType).to(beNil())
    }

    func testBorderThicknessPointsConvertsIndexThroughMillimeters() {
        // index 0 = 0.1 mm, 7 = 0.5 mm, 15 = 5.0 mm (1 mm = 72/25.4 pt)
        expect(HwpBorderFill.borderThicknessPoints(at: 0)).to(beCloseTo(0.2835, within: 0.0001))
        expect(HwpBorderFill.borderThicknessPoints(at: 7)).to(beCloseTo(1.4173, within: 0.0001))
        expect(HwpBorderFill.borderThicknessPoints(at: 15)).to(beCloseTo(14.1732, within: 0.001))
    }

    func testBorderThicknessPointsFallsBackToFirstIndexWhenOutOfRange() {
        expect(HwpBorderFill.borderThicknessPoints(at: 16))
            == HwpBorderFill.borderThicknessPoints(at: 0)
        expect(HwpBorderFill.borderThicknessPoints(at: 255))
            == HwpBorderFill.borderThicknessPoints(at: 0)
    }
}

private func borderFillPayload(fillInfo: Data) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt16(0))) // property
    for _ in 0 ..< 4 { // 4방향 테두리선
        data.append(UInt8(0)) // type
        data.append(UInt8(0)) // thickness
        data.append(littleEndianData(UInt32(0))) // color
    }
    data.append(UInt8(1)) // diagonal type
    data.append(UInt8(0)) // diagonal thickness
    data.append(littleEndianData(UInt32(0))) // diagonal color
    data.append(fillInfo)
    return data
}

private func solidFillInfo() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(1))) // 단색 채우기 flag
    data.append(littleEndianData(UInt32(0x00FF_0000))) // background (blue 255)
    data.append(littleEndianData(UInt32(0x0000_00FF))) // pattern (red 255)
    data.append(littleEndianData(Int32(-1))) // 무늬 없음
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
