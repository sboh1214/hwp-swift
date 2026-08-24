@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class GenShapeObjectPreservationTests: XCTestCase {
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

    func testGenShapeObjectLoadPreservesRawPayloadsAndNestedChildren() throws {
        let fixture = try genShapeFixture()
        let object = fixture.object

        expect(object.commonCtrlProperty.rawPayload) == fixture.commonPayload
        expect(object.rawPayload) == fixture.rawPayload
        expect(object.rawTrailing) == fixture.rawTrailing
        expect(object.shapeComponentArray.map(\.rawPayload)) == [
            fixture.componentPayload,
        ]
        expect(object.shapeComponentArray.map(\.ctrlId)) == [.rectangle]
        expect(object.ctrlDataRecords.map(\.rawPayload)) == [Data([0xEE])]
        expect(object.ctrlDataRecords.first?.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FC, level: 3, payload: Data([0x50])),
        ]
        expect(object.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xFF])),
        ]

        assertGenShapeComponent(object.shapeComponentArray.first, fixture: fixture)
    }
}

private struct GenShapeFixture {
    let commonPayload: Data
    let rawPayload: Data
    let rawTrailing: Data
    let componentPayload: Data
    let rectanglePayload: Data
    let object: HwpGenShapeObject
}

private func genShapeFixture() throws -> GenShapeFixture {
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

    return GenShapeFixture(
        commonPayload: commonPayload,
        rawPayload: concatenatedData(commonPayload, rawTrailing),
        rawTrailing: rawTrailing,
        componentPayload: componentPayload,
        rectanglePayload: rectanglePayload,
        object: object
    )
}

private func assertGenShapeComponent(
    _ component: HwpShapeComponent?,
    fixture: GenShapeFixture
) {
    expect(component?.rectangleArray.map(\.rawPayload)) == [fixture.rectanglePayload]
    expect(component?.rectangleArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0x20])),
    ]
    expect(component?.ctrlDataRecords.map(\.rawPayload)) == [Data([0xCC])]
    expect(component?.ctrlDataRecords.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FC, level: 4, payload: Data([0x30])),
    ]
    expect(component?.unknownChildren) == [
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
