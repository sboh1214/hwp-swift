@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeComponentDetailDecodeTests: XCTestCase {
    func testDecodeReadsElementMatricesBorderLineAndFillAfterSingleCtrlId() {
        var payload = littleEndianData(UInt32(0x2464_6F24)) // ctrl id 1회 기록
        payload.append(elementPayload(flipProperty: 0b11))
        payload.append(littleEndianData(UInt16(1))) // matrix pair count
        payload.append(matrixPayload([1, 0, 10, 0, 1, 20]))
        payload.append(matrixPayload([2, 0, 0, 0, 2, 0]))
        payload.append(matrixPayload([0.5, -0.5, 0, 0.5, 0.5, 0]))
        payload.append(borderLinePayload())
        payload.append(solidFillPayload())

        let detail = HwpShapeComponentDetail.decode(from: payload)

        expect(detail?.groupOffsetX) == -100
        expect(detail?.groupOffsetY) == 200
        expect(detail?.groupCount) == 1
        expect(detail?.localFileVersion) == 2
        expect(detail?.initialWidth) == 4000
        expect(detail?.initialHeight) == 3000
        expect(detail?.currentWidth) == 8000
        expect(detail?.currentHeight) == 6000
        expect(detail?.isHorizontallyFlipped) == true
        expect(detail?.isVerticallyFlipped) == true
        expect(detail?.rotationAngle) == -45
        expect(detail?.rotationCenterX) == 123
        expect(detail?.rotationCenterY) == -456
        expect(detail?.translationMatrix) == [1, 0, 10, 0, 1, 20]
        expect(detail?.scaleRotationMatrixPairs.count) == 1
        expect(detail?.scaleRotationMatrixPairs.first?.scale) == [2, 0, 0, 0, 2, 0]
        expect(detail?.scaleRotationMatrixPairs.first?.rotation) == [0.5, -0.5, 0, 0.5, 0.5, 0]
        expect(detail?.borderLine?.color) == HwpColor(0x40, 0x80, 0xFF)
        expect(detail?.borderLine?.width) == 5
        expect(detail?.borderLine?.property) == 2
        expect(detail?.borderLine?.lineType) == 2
        expect(detail?.borderLine?.outlineStyle) == 1
        expect(detail?.fill?.hasSolidFill) == true
        expect(detail?.fill?.solidBackgroundColor) == HwpColor(255, 0, 0)
        expect(detail?.fill?.solidPatternColor) == HwpColor(0, 255, 0)
        expect(detail?.fill?.solidPatternType) == -1
    }

    func testDecodeSkipsEightBytesWhenCtrlIdIsDoubled() {
        var payload = littleEndianData(UInt32(0x6C69_6E24))
        payload.append(littleEndianData(UInt32(0x6C69_6E24))) // gso 소유 요소는 2회 기록
        payload.append(elementPayload(flipProperty: 0b10))

        let detail = HwpShapeComponentDetail.decode(from: payload)

        expect(detail?.groupOffsetX) == -100
        expect(detail?.groupOffsetY) == 200
        expect(detail?.isHorizontallyFlipped) == false
        expect(detail?.isVerticallyFlipped) == true
        expect(detail?.translationMatrix) == []
        expect(detail?.scaleRotationMatrixPairs) == []
        expect(detail?.borderLine).to(beNil())
        expect(detail?.fill).to(beNil())
    }

    func testDecodeReturnsNilWhenElementIsTruncated() {
        var payload = littleEndianData(UInt32(0x6C69_6E24))
        payload.append(Data(repeating: 0, count: 41)) // 표 83은 42 byte 필요

        expect(HwpShapeComponentDetail.decode(from: payload)).to(beNil())
    }

    func testDecodeKeepsElementWhenMatrixPairsAreMissing() {
        var payload = littleEndianData(UInt32(0x6C69_6E24))
        payload.append(elementPayload(flipProperty: 0))
        payload.append(littleEndianData(UInt16(2))) // pair 2개를 예고하지만
        payload.append(matrixPayload([1, 0, 0, 0, 1, 0])) // translation만 존재

        let detail = HwpShapeComponentDetail.decode(from: payload)

        expect(detail).notTo(beNil())
        expect(detail?.translationMatrix) == [1, 0, 0, 0, 1, 0]
        expect(detail?.scaleRotationMatrixPairs) == []
        expect(detail?.borderLine).to(beNil())
        expect(detail?.fill).to(beNil())
    }
}

private func elementPayload(flipProperty: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(Int32(-100))) // group offset x
    data.append(littleEndianData(Int32(200))) // group offset y
    data.append(littleEndianData(UInt16(1))) // group count
    data.append(littleEndianData(UInt16(2))) // local file version
    data.append(littleEndianData(UInt32(4000))) // initial width
    data.append(littleEndianData(UInt32(3000))) // initial height
    data.append(littleEndianData(UInt32(8000))) // current width
    data.append(littleEndianData(UInt32(6000))) // current height
    data.append(littleEndianData(flipProperty))
    data.append(littleEndianData(Int16(-45))) // rotation angle
    data.append(littleEndianData(Int32(123))) // rotation center x
    data.append(littleEndianData(Int32(-456))) // rotation center y
    return data
}

private func matrixPayload(_ values: [Double]) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(littleEndianData(value.bitPattern))
    }
}

private func borderLinePayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x00FF_8040))) // color (r 0x40, g 0x80, b 0xFF)
    data.append(littleEndianData(Int32(5))) // width (INT32; 표 86의 INT16는 오기)
    data.append(littleEndianData(UInt32(2))) // property (line type 2)
    data.append(UInt8(1)) // outline style
    return data
}

private func solidFillPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(1))) // 단색 채우기 flag
    data.append(littleEndianData(UInt32(0x0000_00FF))) // background (red 255)
    data.append(littleEndianData(UInt32(0x0000_FF00))) // pattern (green 255)
    data.append(littleEndianData(Int32(-1))) // 무늬 없음
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
