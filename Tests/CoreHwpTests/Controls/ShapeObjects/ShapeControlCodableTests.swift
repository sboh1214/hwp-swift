@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeControlCodableTests: XCTestCase {
    func testPictureShapeControlPreservesRawPayloadsThroughCtrlIdCodableRoundTrip() throws {
        let fixture = try shapeCodableFixture()
        let encoded = try JSONEncoder().encode(fixture.control)
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        expect(decoded) == fixture.control

        guard case let .picture(decodedControl) = decoded else {
            return fail("Expected picture shape control after Codable round trip")
        }

        assertDecodedShapeControl(decodedControl, fixture: fixture)
    }

    func testShortShapeControlPreservesRawFallbackThroughCtrlIdCodableRoundTrip() throws {
        let rawTrailing = Data([0xAA, 0xBB, 0xCC])
        var rawPayload = littleEndianShapeCodableData(HwpCommonCtrlId.picture.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: Data([0xDD])),
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]
        let control = HwpCtrlId.picture(try HwpShapeControl.load(record))
        let encoded = try JSONEncoder().encode(control)
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        expect(decoded) == control

        guard case let .picture(decodedControl) = decoded else {
            return fail("Expected picture shape control after Codable round trip")
        }

        expect(decodedControl.ctrlId) == .picture
        expect(decodedControl.commonCtrlProperty).to(beNil())
        expect(decodedControl.rawPayload) == rawPayload
        expect(decodedControl.rawTrailing) == rawTrailing
        expect(decodedControl.ctrlDataRecords.map(\.rawPayload)) == [Data([0xDD])]
        expect(decodedControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]
    }

    func testParsedShapeControlPreservesRawTrailingThroughCtrlIdCodableRoundTrip() throws {
        let commonPayload = shapeCodableCommonCtrlPropertyPayload(
            ctrlId: HwpCommonCtrlId.picture.rawValue
        )
        let rawTrailing = Data([0xDE, 0xAD])
        let rawPayload = commonPayload + rawTrailing
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        let control = HwpCtrlId.picture(try HwpShapeControl.load(record))
        let encoded = try JSONEncoder().encode(control)
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        expect(decoded) == control

        guard case let .picture(decodedControl) = decoded else {
            return fail("Expected picture shape control after Codable round trip")
        }

        expect(decodedControl.commonCtrlProperty?.rawPayload) == commonPayload
        expect(decodedControl.rawPayload) == rawPayload
        expect(decodedControl.rawTrailing) == rawTrailing
    }
}

private struct ShapeCodableFixture {
    let commonPayload: Data
    let componentPayload: Data
    let picturePayload: Data
    let olePayload: Data
    let control: HwpCtrlId
}

private func shapeCodableFixture() throws -> ShapeCodableFixture {
    let commonPayload = shapeCodableCommonCtrlPropertyPayload(
        ctrlId: HwpCommonCtrlId.picture.rawValue
    )
    let componentPayload = shapeCodableComponentPayload(
        ctrlId: HwpCommonCtrlId.picture.rawValue
    )
    let picturePayload = shapeCodablePicturePayload(binaryDataId: 7)
    let olePayload = littleEndianShapeCodableData(UInt32(9)) + Data([0xAB])
    let record = shapeCodableRecord(
        commonPayload: commonPayload,
        componentPayload: componentPayload,
        picturePayload: picturePayload,
        olePayload: olePayload
    )
    let shapeControl = try HwpShapeControl.load(record, HwpVersion(5, 0, 1, 1))

    return ShapeCodableFixture(
        commonPayload: commonPayload,
        componentPayload: componentPayload,
        picturePayload: picturePayload,
        olePayload: olePayload,
        control: HwpCtrlId.picture(shapeControl)
    )
}

private func assertDecodedShapeControl(
    _ decodedControl: HwpShapeControl,
    fixture: ShapeCodableFixture
) {
    expect(decodedControl.rawPayload) == fixture.commonPayload
    expect(decodedControl.commonCtrlProperty?.rawPayload) == fixture.commonPayload
    expect(decodedControl.shapeComponentArray.map(\.rawPayload)) == [fixture.componentPayload]
    expect(decodedControl.shapeComponentArray.map(\.rawCtrlId)) == [
        HwpCommonCtrlId.picture.rawValue,
    ]
    expect(decodedControl.shapeComponentArray.map(\.ctrlId)) == [.picture]
    expect(decodedControl.shapeComponentArray.map(\.rawTrailing)) == [Data([0xA0, 0xA1])]

    assertDecodedShapeComponent(decodedControl.shapeComponentArray.first, fixture: fixture)
    assertDecodedShapeControlChildren(decodedControl)
}

private func assertDecodedShapeComponent(
    _ decodedComponent: HwpShapeComponent?,
    fixture: ShapeCodableFixture
) {
    expect(decodedComponent?.pictureArray.map(\.rawPayload)) == [fixture.picturePayload]
    expect(decodedComponent?.pictureArray.map(\.binaryDataId)) == [7]
    expect(decodedComponent?.pictureArray.map(\.rawTrailing)) == [Data([0])]
    expect(decodedComponent?.pictureArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0x10])),
    ]
    expect(decodedComponent?.oleArray.map(\.rawPayload)) == [fixture.olePayload]
    expect(decodedComponent?.oleArray.map(\.binaryDataId)) == [9]
    expect(decodedComponent?.oleArray.map(\.rawTrailing)) == [Data([0xAB])]
    expect(decodedComponent?.oleArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0x20])),
    ]
    expect(decodedComponent?.oleRecords.map(\.payload)) == [fixture.olePayload]
    expect(decodedComponent?.oleRecords.first?.children) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0x20])),
    ]
    expect(decodedComponent?.ctrlDataRecords.map(\.rawPayload)) == [Data([0xCC])]
    expect(decodedComponent?.ctrlDataRecords.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FC, level: 4, payload: Data([0x30])),
    ]
    expect(decodedComponent?.chartDataArray.map(\.rawPayload)) == [Data([0x41])]
    expect(decodedComponent?.textartArray.map(\.rawPayload)) == [Data([0x42])]
    expect(decodedComponent?.formObjectArray.map(\.rawPayload)) == [Data([0x43])]
    expect(decodedComponent?.memoShapeArray.map(\.rawPayload)) == [Data([0x44])]
    expect(decodedComponent?.memoListArray.map(\.rawPayload)) == [Data([0x45])]
    expect(decodedComponent?.videoDataArray.map(\.rawPayload)) == [Data([0x46])]
    expect(decodedComponent?.shapeComponentUnknownArray.map(\.rawPayload)) == [Data([0x47])]
    expect(decodedComponent?.shapeComponentUnknownArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2F7, level: 4, payload: Data([0x77])),
    ]
    expect(decodedComponent?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FD, level: 3, payload: Data([0xDD])),
    ]
}

private func assertDecodedShapeControlChildren(_ decodedControl: HwpShapeControl) {
    expect(decodedControl.eqEditArray.map(\.rawPayload)) == [Data([0xAB])]
    expect(decodedControl.eqEditArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2F9, level: 3, payload: Data([0x40])),
    ]
    expect(decodedControl.eqEditRecords.map(\.payload)) == [Data([0xAB])]
    expect(decodedControl.ctrlDataRecords.map(\.rawPayload)) == [Data([0xEE])]
    expect(decodedControl.ctrlDataRecords.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2F8, level: 3, payload: Data([0x50])),
    ]
    expect(decodedControl.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xFF])),
    ]
}

private func shapeCodableRecord(
    commonPayload: Data,
    componentPayload: Data,
    picturePayload: Data,
    olePayload: Data
) -> HwpRecord {
    let componentRecord = shapeCodableComponentRecord(
        componentPayload: componentPayload,
        picturePayload: picturePayload,
        olePayload: olePayload
    )
    let eqEditRecord = HwpRecord(
        tagId: HwpSectionTag.eqEdit.rawValue,
        level: 2,
        payload: Data([0xAB])
    )
    eqEditRecord.children = [
        HwpRecord(tagId: 0x2F9, level: 3, payload: Data([0x40])),
    ]
    let topLevelCtrlData = HwpRecord(
        tagId: HwpSectionTag.ctrlData.rawValue,
        level: 2,
        payload: Data([0xEE])
    )
    topLevelCtrlData.children = [
        HwpRecord(tagId: 0x2F8, level: 3, payload: Data([0x50])),
    ]
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: commonPayload
    )
    record.children = [
        componentRecord,
        eqEditRecord,
        topLevelCtrlData,
        HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xFF])),
    ]
    return record
}

private func shapeCodableComponentRecord(
    componentPayload: Data,
    picturePayload: Data,
    olePayload: Data
) -> HwpRecord {
    let componentRecord = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: componentPayload
    )
    let pictureRecord = HwpRecord(
        tagId: HwpSectionTag.shapeComponentPicture.rawValue,
        level: 3,
        payload: picturePayload
    )
    pictureRecord.children = [
        HwpRecord(tagId: 0x2FA, level: 4, payload: Data([0x10])),
    ]
    let oleRecord = HwpRecord(
        tagId: HwpSectionTag.shapeComponentOle.rawValue,
        level: 3,
        payload: olePayload
    )
    oleRecord.children = [
        HwpRecord(tagId: 0x2FB, level: 4, payload: Data([0x20])),
    ]
    let nestedCtrlData = HwpRecord(
        tagId: HwpSectionTag.ctrlData.rawValue,
        level: 3,
        payload: Data([0xCC])
    )
    nestedCtrlData.children = [
        HwpRecord(tagId: 0x2FC, level: 4, payload: Data([0x30])),
    ]
    componentRecord.children = [
        pictureRecord,
        oleRecord,
        nestedCtrlData,
        shapeCodableRawChildRecord(.chartData, payload: Data([0x41])),
        shapeCodableRawChildRecord(.shapeComponentTextart, payload: Data([0x42])),
        shapeCodableRawChildRecord(.formObject, payload: Data([0x43])),
        shapeCodableRawChildRecord(.memoShape, payload: Data([0x44])),
        shapeCodableRawChildRecord(.memoList, payload: Data([0x45])),
        shapeCodableRawChildRecord(.videoData, payload: Data([0x46])),
        shapeCodableRawChildRecord(
            .shapeComponentUnknown,
            payload: Data([0x47]),
            childPayload: Data([0x77])
        ),
        HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xDD])),
    ]
    return componentRecord
}

private func shapeCodableRawChildRecord(
    _ tag: HwpSectionTag,
    payload: Data,
    childPayload: Data? = nil
) -> HwpRecord {
    let record = HwpRecord(tagId: tag.rawValue, level: 3, payload: payload)
    if let childPayload {
        record.children = [
            HwpRecord(tagId: 0x2F7, level: 4, payload: childPayload),
        ]
    }
    return record
}

private func shapeCodableCommonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianShapeCodableData(ctrlId))
    data.append(littleEndianShapeCodableData(UInt32(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT(0)))
    data.append(littleEndianShapeCodableData(Int32(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT16(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT16(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT16(0)))
    data.append(littleEndianShapeCodableData(HWPUNIT16(0)))
    data.append(littleEndianShapeCodableData(UInt32(0)))
    data.append(littleEndianShapeCodableData(Int32(0)))
    data.append(littleEndianShapeCodableData(WORD(0)))
    return data
}

private func shapeCodableComponentPayload(ctrlId: UInt32) -> Data {
    littleEndianShapeCodableData(ctrlId) + Data([0xA0, 0xA1])
}

private func shapeCodablePicturePayload(binaryDataId: UInt16) -> Data {
    var data = Data(repeating: 0, count: 74)
    let idBytes = littleEndianShapeCodableData(binaryDataId)
    data[71] = idBytes[0]
    data[72] = idBytes[1]
    return data
}

private func littleEndianShapeCodableData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
