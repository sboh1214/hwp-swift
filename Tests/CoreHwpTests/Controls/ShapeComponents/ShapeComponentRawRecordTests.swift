@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeComponentRawRecordTests: XCTestCase {
    func testBaseRawRecordPreservesRemainingPayloadAndChildren() throws {
        let payload = Data([0x10, 0x20, 0x30])
        let child = HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xCA, 0xFE]))
        var reader = DataReader(payload)

        let rawRecord = try HwpShapeComponentRawRecord(&reader, [child])

        expect(rawRecord.rawPayload) == payload
        expect(rawRecord.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xCA, 0xFE])),
        ]
        expect(reader.isEOF) == true
    }

    func testKnownRawChildRecordsPreservePayloadsAndChildren() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: littleEndianData(HwpCommonCtrlId.container.rawValue)
        )
        record.children = [
            rawShapeChild(.shapeComponentLine, payload: [0x11], childPayload: [0xA1]),
            rawShapeChild(.shapeComponentEllipse, payload: [0x22], childPayload: [0xA2]),
            rawShapeChild(.shapeComponentArc, payload: [0x33], childPayload: [0xA3]),
            rawShapeChild(.shapeComponentPolygon, payload: [0x44], childPayload: [0xA4]),
            rawShapeChild(.shapeComponentCurve, payload: [0x55], childPayload: [0xA5]),
            rawShapeChild(.shapeComponentContainer, payload: [0x66], childPayload: [0xA6]),
            rawShapeChild(.chartData, payload: [0x77], childPayload: [0xA7]),
            rawShapeChild(.shapeComponentTextart, payload: [0x88], childPayload: [0xA8]),
            rawShapeChild(.formObject, payload: [0x99], childPayload: [0xA9]),
            rawShapeChild(.memoShape, payload: [0xAA], childPayload: [0xAA]),
            rawShapeChild(.memoList, payload: [0xBB], childPayload: [0xAB]),
            rawShapeChild(.videoData, payload: [0xCC], childPayload: [0xAC]),
            rawShapeChild(.shapeComponentUnknown, payload: [0xDD], childPayload: [0xAD]),
            HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xEE])),
        ]

        let component = try HwpShapeComponent.load(record)

        assertKnownRawShapeComponentChildren(component)
    }

    func testShapeComponentPreservesShortPayloadWithoutControlId() throws {
        let rawPayload = Data([0xAA, 0xBB, 0xCC])
        let unknownChild = HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD]))
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: rawPayload
        )
        record.children = [unknownChild]

        let component = try HwpShapeComponent.load(record)

        expect(component.rawPayload) == rawPayload
        expect(component.rawCtrlId).to(beNil())
        expect(component.ctrlId).to(beNil())
        expect(component.ctrlIdName) == "unknown"
        expect(component.rawTrailing).to(beNil())
        expect(component.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD])),
        ]
    }

    func testShapeComponentPayloadWithNonZeroDataStartIndexExtractsControlId() throws {
        let rawPayload = concatenatedData(
            littleEndianData(HwpCommonCtrlId.ole.rawValue),
            Data([0xAA, 0xBB])
        )
        let slicedPayload = concatenatedData(Data([0xFE, 0xED]), rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: slicedPayload
        )

        let component = try HwpShapeComponent.load(record)

        expect(component.rawPayload) == slicedPayload
        expect(component.rawCtrlId) == HwpCommonCtrlId.ole.rawValue
        expect(component.ctrlId) == .ole
        expect(component.ctrlIdName) == "ole"
        expect(component.rawTrailing) == Data([0xAA, 0xBB])
    }

    func testReservedShapeComponentChildIsPreservedAsUnknownRecord() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: littleEndianData(HwpCommonCtrlId.container.rawValue)
        )
        record.children = [
            rawShapeChild(.reserved, payload: [0x01], childPayload: [0xA0]),
        ]

        let component = try HwpShapeComponent.load(record)

        expect(component.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.reserved.rawValue,
                level: 3,
                payload: Data([0x01]),
                children: [
                    expectedTestRecord(
                        tagId: 0x2FB,
                        level: 4,
                        payload: Data([0xA0])
                    ),
                ]
            ),
        ]
    }

    func testPictureComponentReadsBinaryDataIdAtMinimumPayloadLength() throws {
        let rawPayload = concatenatedData(
            Data(repeating: 0xAB, count: 71),
            littleEndianData(UInt16(42))
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentPicture.rawValue,
            level: 2,
            payload: rawPayload
        )

        let picture = try HwpShapeComponentPicture.load(record)

        assertPictureComponent(
            picture,
            rawPayload: rawPayload,
            binaryDataId: 42,
            rawTrailing: Data()
        )
    }

    func testPictureComponentPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawPayload = concatenatedData(
            Data(repeating: 0xAB, count: 71),
            littleEndianData(UInt16(43)),
            Data([0xC1, 0xC2])
        )
        let slicedPayload = concatenatedData(Data([0xFE, 0xED]), rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentPicture.rawValue,
            level: 2,
            payload: slicedPayload
        )

        let picture = try HwpShapeComponentPicture.load(record)

        assertPictureComponent(
            picture,
            rawPayload: slicedPayload,
            binaryDataId: 43,
            rawTrailing: Data([0xC1, 0xC2])
        )
    }

    func testPictureComponentPreservesShortPayloadWithoutBinaryDataId() throws {
        for length in [0, 1, 71, 72] {
            let rawPayload = Data(repeating: 0xAB, count: length)
            let record = HwpRecord(
                tagId: HwpSectionTag.shapeComponentPicture.rawValue,
                level: 2,
                payload: rawPayload
            )

            let picture = try HwpShapeComponentPicture.load(record)

            assertPictureComponent(
                picture,
                rawPayload: rawPayload,
                binaryDataId: nil,
                rawTrailing: nil
            )
        }
    }

    func testOLEComponentReadsBinaryDataIdAtMinimumPayloadLengthAndPreservesTrailing() throws {
        // 실제 layout: 속성 u32 + extent i32 x 2 + BinData id u16 @12
        let rawPayload = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(Int32(7200)),
            littleEndianData(Int32(7200)),
            littleEndianData(UInt16(42))
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: rawPayload
        )

        let ole = try HwpShapeComponentOLE.load(record)

        assertOLEComponent(
            ole,
            rawPayload: rawPayload,
            binaryDataId: 42,
            rawTrailing: Data(rawPayload.dropFirst(4))
        )
    }

    func testOLEComponentPayloadWithNonZeroDataStartIndexDoesNotTrap() throws {
        let rawPayload = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(Int32(0)),
            littleEndianData(Int32(0)),
            littleEndianData(UInt16(43)),
            Data([0xC3])
        )
        let slicedPayload = concatenatedData(Data([0xFE, 0xED]), rawPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: slicedPayload
        )

        let ole = try HwpShapeComponentOLE.load(record)

        assertOLEComponent(
            ole,
            rawPayload: slicedPayload,
            binaryDataId: 43,
            rawTrailing: Data(rawPayload.dropFirst(4))
        )
    }

    func testOLEComponentPreservesShortPayloadWithoutBinaryDataId() throws {
        for length in [0, 1, 2, 3] {
            let rawPayload = Data(repeating: 0xAB, count: length)
            let record = HwpRecord(
                tagId: HwpSectionTag.shapeComponentOle.rawValue,
                level: 2,
                payload: rawPayload
            )

            let ole = try HwpShapeComponentOLE.load(record)

            assertOLEComponent(
                ole,
                rawPayload: rawPayload,
                binaryDataId: nil,
                rawTrailing: nil
            )
        }
    }
}

private func assertKnownRawShapeComponentChildren(_ component: HwpShapeComponent) {
    expect(component.lineArray.map(\.rawPayload)) == [Data([0x11])]
    expect(component.ellipseArray.map(\.rawPayload)) == [Data([0x22])]
    expect(component.arcArray.map(\.rawPayload)) == [Data([0x33])]
    expect(component.polygonArray.map(\.rawPayload)) == [Data([0x44])]
    expect(component.curveArray.map(\.rawPayload)) == [Data([0x55])]
    expect(component.containerArray.map(\.rawPayload)) == [Data([0x66])]
    expect(component.chartDataArray.map(\.rawPayload)) == [Data([0x77])]
    expect(component.textartArray.map(\.rawPayload)) == [Data([0x88])]
    expect(component.formObjectArray.map(\.rawPayload)) == [Data([0x99])]
    expect(component.memoShapeArray.map(\.rawPayload)) == [Data([0xAA])]
    expect(component.memoListArray.map(\.rawPayload)) == [Data([0xBB])]
    expect(component.videoDataArray.map(\.rawPayload)) == [Data([0xCC])]
    expect(component.shapeComponentUnknownArray.map(\.rawPayload)) == [Data([0xDD])]
    expect(component.lineArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0xA1])),
    ]
    expect(component.chartDataArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0xA7])),
    ]
    expect(component.shapeComponentUnknownArray.first?.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0xAD])),
    ]
    expect(component.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xEE])),
    ]
}

private func assertPictureComponent(
    _ picture: HwpShapeComponentPicture,
    rawPayload: Data,
    binaryDataId: UInt16?,
    rawTrailing: Data?
) {
    expect(picture.rawPayload) == rawPayload
    if let binaryDataId {
        expect(picture.binaryDataId) == binaryDataId
    } else {
        expect(picture.binaryDataId).to(beNil())
    }
    assertRawTrailing(picture.rawTrailing, rawTrailing)
    expect(picture.unknownChildren).to(beEmpty())
}

private func assertOLEComponent(
    _ ole: HwpShapeComponentOLE,
    rawPayload: Data,
    binaryDataId: UInt32?,
    rawTrailing: Data?
) {
    expect(ole.rawPayload) == rawPayload
    if let binaryDataId {
        expect(ole.binaryDataId) == binaryDataId
    } else {
        expect(ole.binaryDataId).to(beNil())
    }
    assertRawTrailing(ole.rawTrailing, rawTrailing)
    expect(ole.unknownChildren).to(beEmpty())
}

private func assertRawTrailing(_ actual: Data?, _ expected: Data?) {
    if let expected {
        expect(actual) == expected
    } else {
        expect(actual).to(beNil())
    }
}

private func rawShapeChild(
    _ tag: HwpSectionTag,
    payload: [UInt8],
    childPayload: [UInt8]
) -> HwpRecord {
    let record = HwpRecord(tagId: tag.rawValue, level: 3, payload: Data(payload))
    record.children = [
        HwpRecord(tagId: 0x2FB, level: 4, payload: Data(childPayload)),
    ]
    return record
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
