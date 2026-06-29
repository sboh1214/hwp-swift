@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeControlDirectLoaderTests: XCTestCase {
    func testShapeControlWithoutVersionParsesShapeComponentChildren() throws {
        let rawPayload = directCommonShapeControlPayload(ctrlId: HwpCommonCtrlId.picture.rawValue)
        let componentPayload = concatenatedData(
            directLittleEndianData(HwpCommonCtrlId.picture.rawValue),
            Data([0xCA])
        )
        let picturePayload = concatenatedData(
            Data(repeating: 0xAB, count: 71),
            directLittleEndianData(UInt16(9))
        )
        let componentRecord = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: componentPayload
        )
        componentRecord.children = [
            HwpRecord(
                tagId: HwpSectionTag.shapeComponentPicture.rawValue,
                level: 3,
                payload: picturePayload
            ),
            HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD])),
        ]
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            componentRecord,
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]

        let shapeControl = try HwpShapeControl.load(record)

        expect(shapeControl.ctrlId) == .picture
        expect(shapeControl.rawPayload) == rawPayload
        expect(shapeControl.commonCtrlProperty?.commonCtrlId) == .picture
        expect(shapeControl.shapeComponentArray.count) == 1
        let component = shapeControl.shapeComponentArray.first
        expect(component?.ctrlId) == .picture
        expect(component?.rawPayload) == componentPayload
        expect(component?.pictureArray.map(\.rawPayload)) == [picturePayload]
        expect(component?.pictureArray.map(\.binaryDataId)) == [9]
        expect(component?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD])),
        ]
        expect(shapeControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]
    }
}

private func directCommonShapeControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(directLittleEndianData(ctrlId))
    data.append(directLittleEndianData(UInt32(0)))
    data.append(directLittleEndianData(HWPUNIT(0)))
    data.append(directLittleEndianData(HWPUNIT(0)))
    data.append(directLittleEndianData(HWPUNIT(0)))
    data.append(directLittleEndianData(HWPUNIT(0)))
    data.append(directLittleEndianData(Int32(0)))
    data.append(directLittleEndianData(HWPUNIT16(0)))
    data.append(directLittleEndianData(HWPUNIT16(0)))
    data.append(directLittleEndianData(HWPUNIT16(0)))
    data.append(directLittleEndianData(HWPUNIT16(0)))
    data.append(directLittleEndianData(UInt32(0)))
    data.append(directLittleEndianData(Int32(0)))
    data.append(directLittleEndianData(WORD(0)))
    return data
}

private func directLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
