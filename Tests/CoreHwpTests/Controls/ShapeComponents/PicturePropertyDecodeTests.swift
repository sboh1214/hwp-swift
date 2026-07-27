@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class PicturePropertyDecodeTests: XCTestCase {
    func testDecodeReadsBorderCornersCropMarginsAndBinItemId() {
        let property = HwpPictureProperty.decode(from: picturePropertyPayload(binItemId: 2))

        expect(property?.borderColor) == HwpColor(0x11, 0x22, 0x33)
        expect(property?.borderThickness) == 26
        expect(property?.borderProperty) == 7
        expect(property?.imageCorners) == [
            HwpShapePoint(x: 0, y: 0),
            HwpShapePoint(x: 200, y: 0),
            HwpShapePoint(x: 200, y: 150),
            HwpShapePoint(x: 0, y: 150),
        ]
        expect(property?.cropLeft) == 1
        expect(property?.cropTop) == 2
        expect(property?.cropRight) == 3
        expect(property?.cropBottom) == 4
        expect(property?.innerMarginArray) == [5, 6, 7, 8]
        expect(property?.brightness) == -3
        expect(property?.contrast) == 4
        expect(property?.effect) == 1
        expect(property?.binItemId) == 2
    }

    func testDecodeReturnsNilWhenPayloadIsShorterThan73Bytes() {
        let truncated = Data(picturePropertyPayload().dropLast())

        expect(HwpPictureProperty.decode(from: truncated)).to(beNil())
        expect(HwpPictureProperty.decode(from: Data())).to(beNil())
    }

    func testPictureComponentExposesPicturePropertyMatchingBinaryDataId() {
        var payload = picturePropertyPayload(binItemId: 3)
        payload.append(contentsOf: [0xDE, 0xAD]) // 가변 tail은 무시된다

        let picture = HwpShapeComponentPicture(
            rawPayload: payload,
            binaryDataId: 3,
            rawTrailing: nil,
            unknownChildren: []
        )

        expect(picture.pictureProperty).notTo(beNil())
        expect(picture.pictureProperty?.binItemId) == 3
        expect(picture.pictureProperty?.binItemId) == picture.binaryDataId
    }
}

private func picturePropertyPayload(binItemId: UInt16 = 2) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x0033_2211))) // border color
    data.append(littleEndianData(Int32(26))) // border thickness
    data.append(littleEndianData(UInt32(7))) // border property
    data.append(int32Payload([0, 0, 200, 0, 200, 150, 0, 150])) // corner (x,y) 쌍 4개
    data.append(int32Payload([1, 2, 3, 4])) // crop left/top/right/bottom
    for margin in [Int16(5), 6, 7, 8] { // inner margins
        data.append(littleEndianData(margin))
    }
    data.append(UInt8(bitPattern: -3)) // brightness
    data.append(UInt8(4)) // contrast
    data.append(UInt8(1)) // effect: gray scale
    data.append(littleEndianData(binItemId))
    return data
}

private func int32Payload(_ values: [Int32]) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(littleEndianData(value))
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
