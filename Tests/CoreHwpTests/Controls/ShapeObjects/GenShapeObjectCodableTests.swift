@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class GenShapeObjectCodableTests: XCTestCase {
    func testGenShapeObjectInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let commonPayload = genShapeCommonPropertyPayload()
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = concatenatedData(commonPayload, rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        let unknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xDD]))
        var reader = DataReader(slicedPayload)

        let object = try HwpGenShapeObject(
            &reader,
            [unknownChild],
            HwpVersion(5, 0, 1, 1)
        )

        expect(object.rawPayload) == slicedPayload
        expect(object.rawTrailing) == rawTrailing
        expect(object.commonCtrlProperty.rawPayload) == commonPayload
        expect(object.shapeComponentArray).to(beEmpty())
        expect(object.ctrlDataRecords).to(beEmpty())
        expect(object.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xDD])),
        ]
        expect(reader.isEOF) == true
    }

    func testGenShapeObjectPreservesRawPayloadsThroughCtrlIdCodableRoundTrip() throws {
        let fixture = try genShapeCodableFixture()
        let encoded = try JSONEncoder().encode(fixture.control)
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        expect(decoded) == fixture.control

        guard case let .genShapeObject(decodedObject) = decoded else {
            return fail("Expected genShapeObject after Codable round trip")
        }

        expect(decodedObject.commonCtrlProperty.rawPayload) == fixture.commonPayload
        expect(decodedObject.rawPayload) == fixture.rawPayload
        expect(decodedObject.rawTrailing) == fixture.rawTrailing
        expect(decodedObject.shapeComponentArray.map(\.rawPayload)) == [
            fixture.componentPayload,
        ]
        expect(decodedObject.shapeComponentArray.map(\.ctrlId)) == [.rectangle]
        expect(decodedObject.ctrlDataRecords.map(\.rawPayload)) == [Data([0xEE])]
        expect(decodedObject.ctrlDataRecords.first?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FC, level: 3, payload: Data([0x50])),
        ]
        expect(decodedObject.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xFF])),
        ]

        assertDecodedGenShapeComponent(decodedObject.shapeComponentArray.first, fixture: fixture)
    }
}

private struct GenShapeCodableFixture {
    let commonPayload: Data
    let rawPayload: Data
    let rawTrailing: Data
    let componentPayload: Data
    let rectanglePayload: Data
    let control: HwpCtrlId
}

private func genShapeCodableFixture() throws -> GenShapeCodableFixture {
    let commonPayload = genShapeCommonPropertyPayload()
    let rawTrailing = Data([0xDE, 0xAD])
    let componentPayload = concatenatedData(
        littleEndianGenShapeData(HwpCommonCtrlId.rectangle.rawValue),
        Data([0xA0, 0xA1])
    )
    let rectanglePayload = Data([0x10, 0x11])
    let record = genShapeRecord(
        commonPayload: commonPayload,
        rawTrailing: rawTrailing,
        componentPayload: componentPayload,
        rectanglePayload: rectanglePayload
    )
    let object = try HwpGenShapeObject.load(record, HwpVersion(5, 0, 1, 1))

    return GenShapeCodableFixture(
        commonPayload: commonPayload,
        rawPayload: concatenatedData(commonPayload, rawTrailing),
        rawTrailing: rawTrailing,
        componentPayload: componentPayload,
        rectanglePayload: rectanglePayload,
        control: HwpCtrlId.genShapeObject(object)
    )
}

private func assertDecodedGenShapeComponent(
    _ decodedComponent: HwpShapeComponent?,
    fixture: GenShapeCodableFixture
) {
    expect(decodedComponent?.rectangleArray.map(\.rawPayload)) == [fixture.rectanglePayload]
    expect(decodedComponent?.rectangleArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0x20])),
    ]
    expect(decodedComponent?.ctrlDataRecords.map(\.rawPayload)) == [Data([0xCC])]
    expect(decodedComponent?.ctrlDataRecords.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FC, level: 4, payload: Data([0x30])),
    ]
    expect(decodedComponent?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FD, level: 3, payload: Data([0xDD])),
    ]
}

private func genShapeRecord(
    commonPayload: Data,
    rawTrailing: Data,
    componentPayload: Data,
    rectanglePayload: Data
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: concatenatedData(commonPayload, rawTrailing)
    )
    record.children = [
        genShapeComponentRecord(
            componentPayload: componentPayload,
            rectanglePayload: rectanglePayload
        ),
        genShapeCtrlDataRecord(payload: Data([0xEE]), childPayload: Data([0x50]), level: 2),
        HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xFF])),
    ]
    return record
}

private func genShapeComponentRecord(
    componentPayload: Data,
    rectanglePayload: Data
) -> HwpRecord {
    let componentRecord = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: componentPayload
    )
    let rectangleRecord = HwpRecord(
        tagId: HwpSectionTag.shapeComponentRectangle.rawValue,
        level: 3,
        payload: rectanglePayload
    )
    rectangleRecord.children = [
        HwpRecord(tagId: 0x2FA, level: 4, payload: Data([0x20])),
    ]
    componentRecord.children = [
        rectangleRecord,
        genShapeCtrlDataRecord(payload: Data([0xCC]), childPayload: Data([0x30]), level: 3),
        HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xDD])),
    ]
    return componentRecord
}

private func genShapeCtrlDataRecord(
    payload: Data,
    childPayload: Data,
    level: UInt32
) -> HwpRecord {
    let record = HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: level, payload: payload)
    record.children = [
        HwpRecord(tagId: 0x2FC, level: level + 1, payload: childPayload),
    ]
    return record
}

private func genShapeCommonPropertyPayload() -> Data {
    var data = Data()
    data.append(littleEndianGenShapeData(HwpCommonCtrlId.genShapeObject.rawValue))
    data.append(littleEndianGenShapeData(UInt32(0)))
    data.append(littleEndianGenShapeData(HWPUNIT(0)))
    data.append(littleEndianGenShapeData(HWPUNIT(0)))
    data.append(littleEndianGenShapeData(HWPUNIT(0)))
    data.append(littleEndianGenShapeData(HWPUNIT(0)))
    data.append(littleEndianGenShapeData(Int32(0)))
    data.append(littleEndianGenShapeData(HWPUNIT16(0)))
    data.append(littleEndianGenShapeData(HWPUNIT16(0)))
    data.append(littleEndianGenShapeData(HWPUNIT16(0)))
    data.append(littleEndianGenShapeData(HWPUNIT16(0)))
    data.append(littleEndianGenShapeData(UInt32(0)))
    data.append(littleEndianGenShapeData(Int32(0)))
    data.append(littleEndianGenShapeData(WORD(0)))
    return data
}

private func littleEndianGenShapeData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
