@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeComponentTextBoxCodableTests: XCTestCase {
    func testTextBoxListsSurviveShapeControlCodableRoundTrip() throws {
        let fixture = textBoxCodableFixture()
        let shapeControl = try HwpShapeControl.load(fixture.record, HwpVersion(5, 0, 1, 1))
        let control = HwpCtrlId.rectangle(shapeControl)
        let decoded = try JSONDecoder().decode(
            HwpCtrlId.self,
            from: JSONEncoder().encode(control)
        )

        guard case let .rectangle(decodedControl) = decoded else {
            return fail("Expected rectangle shape control after Codable round-trip")
        }

        assertTextBoxShapeControl(shapeControl, fixture: fixture)
        assertTextBoxShapeControl(decodedControl, fixture: fixture)
    }
}

private struct TextBoxCodableFixture {
    let record: HwpRecord
    let controlPayload: Data
    let componentPayload: Data
    let listHeaderPayloads: [Data]
}

private func assertTextBoxShapeControl(
    _ control: HwpShapeControl,
    fixture: TextBoxCodableFixture
) {
    expect(control.ctrlId) == .rectangle
    expect(control.rawPayload) == fixture.controlPayload
    expect(control.rawTrailing) == Data([0xAB])
    expect(control.shapeComponentArray.count) == 1
    expect(control.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEF])),
    ]

    guard let component = control.shapeComponentArray.first else {
        return fail("Expected text box shape component")
    }

    expect(component.rawPayload) == fixture.componentPayload
    expect(component.rawCtrlId) == HwpCommonCtrlId.rectangle.rawValue
    expect(component.ctrlId) == .rectangle
    expect(component.rawTrailing) == Data([0xA0])
    expect(component.textBoxListArray.count) == 2
    expect(component.textBoxListArray.map(\.header.paragraphCount)) == [1, 1]
    expect(component.textBoxListArray.map(\.headerRawPayload)) == fixture.listHeaderPayloads
    expect(component.textBoxListArray.map(\.header.rawTrailing)) == [
        Data([0xC1]),
        Data([0xC2, 0xC3]),
    ]
    expect(component.textBoxListArray.first?.headerUnknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FD,
            level: 4,
            payload: Data([0xD1]),
            children: [
                expectedTestRecord(tagId: 0x2FC, level: 5, payload: Data([0xD2])),
            ]
        ),
    ]
    expect(component.textBoxListArray.last?.headerUnknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2FB, level: 4, payload: Data([0xD3])),
    ]
    expect(component.textBoxListArray.flatMap(\.paragraphArray).map(\.paraHeader.rawPayload)) == [
        textBoxCodableParagraphHeaderPayload(),
        textBoxCodableParagraphHeaderPayload(),
    ]
    expect(component.textBoxListArray.flatMap(\.paragraphArray).map(\.unknownChildren)) == [
        [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0xE1])),
        ],
        [
            expectedTestUnknownRecord(tagId: 0x2F9, level: 4, payload: Data([0xE2])),
        ],
    ]
    expect(component.unknownChildren) == [
        expectedTestUnknownRecord(tagId: 0x2F8, level: 3, payload: Data([0xF8])),
    ]
}

private func textBoxCodableFixture() -> TextBoxCodableFixture {
    let controlPayload = concatenatedData(
        textBoxCodableLittleEndianData(HwpCommonCtrlId.rectangle.rawValue),
        Data([0xAB])
    )
    let componentPayload = concatenatedData(
        textBoxCodableLittleEndianData(HwpCommonCtrlId.rectangle.rawValue),
        Data([0xA0])
    )
    let firstHeaderPayload = textBoxCodableListHeaderPayload(rawTrailing: Data([0xC1]))
    let secondHeaderPayload = textBoxCodableListHeaderPayload(rawTrailing: Data([0xC2, 0xC3]))

    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: controlPayload
    )
    record.children = [
        textBoxCodableShapeComponentRecord(
            payload: componentPayload,
            firstHeaderPayload: firstHeaderPayload,
            secondHeaderPayload: secondHeaderPayload
        ),
        HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xEF])),
    ]
    return TextBoxCodableFixture(
        record: record,
        controlPayload: controlPayload,
        componentPayload: componentPayload,
        listHeaderPayloads: [firstHeaderPayload, secondHeaderPayload]
    )
}

private func textBoxCodableShapeComponentRecord(
    payload: Data,
    firstHeaderPayload: Data,
    secondHeaderPayload: Data
) -> HwpRecord {
    let firstHeader = HwpRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 3,
        payload: firstHeaderPayload
    )
    firstHeader.children = [
        textBoxCodableNestedChildRecord(
            tagId: 0x2FD,
            level: 4,
            payload: Data([0xD1]),
            nestedTagId: 0x2FC,
            nestedPayload: Data([0xD2])
        ),
    ]
    let secondHeader = HwpRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 3,
        payload: secondHeaderPayload
    )
    secondHeader.children = [
        HwpRecord(tagId: 0x2FB, level: 4, payload: Data([0xD3])),
    ]
    let record = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: payload
    )
    record.children = [
        firstHeader,
        textBoxCodableParagraphRecord(unknownTagId: 0x2FA, unknownPayload: Data([0xE1])),
        secondHeader,
        textBoxCodableParagraphRecord(unknownTagId: 0x2F9, unknownPayload: Data([0xE2])),
        HwpRecord(tagId: 0x2F8, level: 3, payload: Data([0xF8])),
    ]
    return record
}

private func textBoxCodableNestedChildRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    nestedTagId: UInt32,
    nestedPayload: Data
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = [
        HwpRecord(tagId: nestedTagId, level: level + 1, payload: nestedPayload),
    ]
    return record
}

private func textBoxCodableParagraphRecord(
    unknownTagId: UInt32,
    unknownPayload: Data
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 3,
        payload: textBoxCodableParagraphHeaderPayload()
    )
    record.children = [
        HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 4, payload: Data()),
        HwpRecord(tagId: unknownTagId, level: 4, payload: unknownPayload),
    ]
    return record
}

private func textBoxCodableListHeaderPayload(rawTrailing: Data) -> Data {
    var data = Data()
    data.append(textBoxCodableLittleEndianData(Int32(1)))
    data.append(textBoxCodableLittleEndianData(UInt32(0)))
    data.append(rawTrailing)
    return data
}

private func textBoxCodableParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(textBoxCodableLittleEndianData(UInt32(0x8000_0000)))
    data.append(textBoxCodableLittleEndianData(UInt32(0)))
    data.append(textBoxCodableLittleEndianData(UInt16(0)))
    data.append(textBoxCodableLittleEndianData(UInt8(0)))
    data.append(textBoxCodableLittleEndianData(UInt8(0)))
    data.append(textBoxCodableLittleEndianData(UInt16(0)))
    data.append(textBoxCodableLittleEndianData(UInt16(0)))
    data.append(textBoxCodableLittleEndianData(UInt16(0)))
    data.append(textBoxCodableLittleEndianData(UInt32(1)))
    return data
}

private func textBoxCodableLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
