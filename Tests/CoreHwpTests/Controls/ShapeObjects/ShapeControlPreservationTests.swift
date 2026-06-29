@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable type_body_length
final class ShapeControlPreservationTests: XCTestCase {
    func testCommonShapeControlPreservesShortPropertyPayload() throws {
        let rawTrailing = Data([0xAA, 0xBB, 0xCC])
        var rawPayload = littleEndianData(HwpCommonCtrlId.picture.rawValue)
        rawPayload.append(rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 2, payload: Data([0xDD]))
        )
        record.children.append(
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE]))
        )

        let shapeControl = try HwpShapeControl.load(record)

        expect(shapeControl.ctrlId) == .picture
        expect(shapeControl.commonCtrlProperty).to(beNil())
        expect(shapeControl.rawPayload) == rawPayload
        expect(shapeControl.rawTrailing) == rawTrailing
        expect(shapeControl.eqEditArray).to(beEmpty())
        expect(shapeControl.eqEditRecords).to(beEmpty())
        expect(shapeControl.ctrlDataRecords.map(\.rawPayload)) == [Data([0xDD])]
        expect(shapeControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]
    }

    func testEquationEditPreservesRawPayloadAndExtractsEquationText() throws {
        let rawPayload = concatenatedData(equationEditPayload(text: "x=1"), Data([0xAA, 0xBB]))
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])))

        let edit = try HwpEquationEdit.load(record)

        expect(edit.rawPayload) == rawPayload
        expect(edit.equationTextLength) == 3
        expect(edit.equationTextLengthRawPayload) == Data([0x03, 0x00])
        expect(edit.equationText) == "x=1"
        expect(edit.equationTextRawPayload) == Data([0x78, 0x00, 0x3D, 0x00, 0x31, 0x00])
        expect(edit.rawTrailing) == Data([0xAA, 0xBB])
        expect(edit.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])),
        ]
    }

    func testEquationEditPreservesTruncatedTextAsRawPayload() throws {
        let rawPayload = concatenatedData(
            Data([0x00, 0x00, 0x00, 0x00]),
            littleEndianData(UInt16(4)),
            littleEndianData(WCHAR(0x0078))
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )

        let edit = try HwpEquationEdit.load(record)

        expect(edit.rawPayload) == rawPayload
        expect(edit.equationTextLength) == 4
        expect(edit.equationTextLengthRawPayload) == Data([0x04, 0x00])
        expect(edit.equationText).to(beNil())
        expect(edit.equationTextRawPayload).to(beNil())
        expect(edit.rawTrailing).to(beNil())
    }

    func testEquationEditPreservesInvalidUtf16TextAsRawPayload() throws {
        let rawPayload = concatenatedData(
            Data([0x00, 0x00, 0x00, 0x00]),
            littleEndianData(UInt16(1)),
            littleEndianData(WCHAR(0xD800)),
            Data([0xCA, 0xFE])
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: rawPayload
        )

        let edit = try HwpEquationEdit.load(record)

        expect(edit.rawPayload) == rawPayload
        expect(edit.equationTextLength) == 1
        expect(edit.equationTextLengthRawPayload) == Data([0x01, 0x00])
        expect(edit.equationText).to(beNil())
        expect(edit.equationTextRawPayload) == littleEndianData(WCHAR(0xD800))
        expect(edit.rawTrailing) == Data([0xCA, 0xFE])
    }

    func testParagraphClassifiesEquationShapeControlSemantically() throws {
        let rawPayload = commonShapeControlPayload(ctrlId: HwpCommonCtrlId.equation.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(
                tagId: HwpSectionTag.eqEdit.rawValue,
                level: 2,
                payload: equationEditPayload(text: "x=1")
            ),
        ]

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .equation(control) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected equation shape control")
        }

        expect(control.ctrlId) == .equation
        expect(control.rawPayload) == rawPayload
        expect(control.eqEditArray.map(\.equationText)) == ["x=1"]
    }

    func testShapeComponentPicturePreservesShortPayloadWithoutBinaryDataId() throws {
        let rawPayload = Data(repeating: 0xAB, count: 72)
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentPicture.rawValue,
            level: 2,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])))

        let picture = try HwpShapeComponentPicture.load(record)

        expect(picture.rawPayload) == rawPayload
        expect(picture.binaryDataId).to(beNil())
        expect(picture.rawTrailing).to(beNil())
        expect(picture.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])),
        ]
    }

    func testShapeComponentRectanglePreservesRawPayloadAndChildren() throws {
        let rawPayload = Data([0xCA, 0xFE])
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentRectangle.rawValue,
            level: 3,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 4, payload: Data([0xCD])))

        let rectangle = try HwpShapeComponentRectangle.load(record)

        expect(rectangle.rawPayload) == rawPayload
        expect(rectangle.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0xCD])),
        ]
    }

    func testShapeComponentExposesControlIdMetadataAndPreservesChildren() throws {
        let rawPayload = concatenatedData(
            littleEndianData(HwpCommonCtrlId.ole.rawValue),
            Data([0xAA, 0xBB])
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.ctrlData.rawValue, level: 3, payload: Data([0xCC])),
            HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD])),
        ]

        let component = try HwpShapeComponent.load(record)

        expect(component.rawPayload) == rawPayload
        expect(component.rawCtrlId) == HwpCommonCtrlId.ole.rawValue
        expect(component.ctrlId) == .ole
        expect(component.ctrlIdName) == "ole"
        expect(component.rawTrailing) == Data([0xAA, 0xBB])
        expect(component.ctrlDataRecords.map(\.rawPayload)) == [Data([0xCC])]
        expect(component.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xDD])),
        ]
    }

    func testShapeComponentParsesTextBoxListParagraphsWhenVersionIsProvided() throws {
        let rawPayload = concatenatedData(
            littleEndianData(HwpCommonCtrlId.rectangle.rawValue),
            Data([0xAA])
        )
        let listHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 3,
            payload: concatenatedData(listHeaderPayload(paragraphCount: 1), Data([0xEE]))
        )
        let rectangleChild = HwpRecord(
            tagId: HwpSectionTag.shapeComponentRectangle.rawValue,
            level: 3,
            payload: Data([0xCA, 0xFE])
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: rawPayload
        )
        record.children = [
            listHeader,
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 4,
                    payload: Data()
                ),
            ]),
            rectangleChild,
        ]

        let component = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))

        expect(component.rawPayload) == rawPayload
        expect(component.rawCtrlId) == HwpCommonCtrlId.rectangle.rawValue
        expect(component.ctrlId) == .rectangle
        expect(component.rawTrailing) == Data([0xAA])
        expect(component.textBoxListArray.count) == 1
        expect(component.textBoxListArray.first?.header.paragraphCount) == 1
        expect(component.textBoxListArray.first?.headerRawPayload) == listHeader.payload
        expect(component.textBoxListArray.first?.paragraphArray.count) == 1
        expect(component.rectangleArray.map(\.rawPayload)) == [Data([0xCA, 0xFE])]
        expect(component.unknownChildren).to(beEmpty())
    }

    func testShapeComponentPreservesShortPayloadWithoutControlIdMetadata() throws {
        let rawPayload = Data([0xAA, 0xBB, 0xCC])
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: rawPayload
        )

        let component = try HwpShapeComponent.load(record)

        expect(component.rawPayload) == rawPayload
        expect(component.rawCtrlId).to(beNil())
        expect(component.ctrlId).to(beNil())
        expect(component.ctrlIdName) == "unknown"
        expect(component.rawTrailing).to(beNil())
    }

    func testShapeComponentOLEPreservesRawPayloadAndOptionalBinaryDataId() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: concatenatedData(littleEndianData(UInt32(3)), Data([0xAA, 0xBB]))
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])))

        let ole = try HwpShapeComponentOLE.load(record)

        expect(ole.rawPayload) == concatenatedData(littleEndianData(UInt32(3)), Data([0xAA, 0xBB]))
        expect(ole.binaryDataId) == 3
        expect(ole.rawTrailing) == Data([0xAA, 0xBB])
        expect(ole.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 3, payload: Data([0xCD])),
        ]
    }

    func testShapeComponentOLEPreservesShortPayloadWithoutBinaryDataId() throws {
        let rawPayload = Data([0xAA, 0xBB, 0xCC])
        let record = HwpRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 2,
            payload: rawPayload
        )

        let ole = try HwpShapeComponentOLE.load(record)

        expect(ole.rawPayload) == rawPayload
        expect(ole.binaryDataId).to(beNil())
        expect(ole.rawTrailing).to(beNil())
    }

    func testParagraphPreservesShortGenShapeObjectAsNotImplemented() throws {
        let rawPayload = rawControlPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: Data([0xAA])
            ),
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xBB])),
        ]

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .notImplemented(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected short genShapeObject to be preserved as notImplemented")
        }

        expect(header.ctrlId) == HwpCommonCtrlId.genShapeObject.rawValue
        expect(header.rawPayload) == rawPayload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: Data([0xAA])
            ),
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0xBB])),
        ]
    }

    func testParagraphPreservesMalformedGenShapeObjectTextBoxAsNotImplemented() throws {
        let record = malformedGenShapeObjectTextBoxRecord()

        expect {
            _ = try HwpGenShapeObject.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("text box paragraph is missing"))
        })

        let paragraph = try HwpParagraph.load(
            paragraphRecord(children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: Data()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: Data()
                ),
                record,
            ]),
            HwpVersion(5, 0, 1, 1)
        )

        guard case let .notImplemented(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected malformed genShapeObject to be preserved as notImplemented")
        }

        expect(header.ctrlId) == HwpCommonCtrlId.genShapeObject.rawValue
        expect(header.rawPayload) == record.payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: littleEndianData(HwpCommonCtrlId.rectangle.rawValue),
                children: [
                    expectedTestRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: listHeaderPayload(paragraphCount: 1)
                    ),
                ]
            ),
        ]
    }
}

// swiftlint:enable type_body_length

private func rawControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(contentsOf: [0xAA, 0xBB])
    return data
}

private func malformedGenShapeObjectTextBoxRecord() -> HwpRecord {
    let listHeader = HwpRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 3,
        payload: listHeaderPayload(paragraphCount: 1)
    )
    let shapeComponent = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: littleEndianData(HwpCommonCtrlId.rectangle.rawValue)
    )
    shapeComponent.children = [listHeader]
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: commonShapeControlPayload(ctrlId: HwpCommonCtrlId.genShapeObject.rawValue)
    )
    record.children = [shapeComponent]
    return record
}

private func commonShapeControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(WORD(0)))
    return data
}

private func equationEditPayload(text: String) -> Data {
    var data = Data([0x00, 0x00, 0x00, 0x00])
    data.append(littleEndianData(UInt16(text.utf16.count)))
    for codeUnit in text.utf16 {
        data.append(littleEndianData(codeUnit))
    }
    return data
}

private func paragraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: paragraphHeaderPayload()
    )
    record.children = children
    return record
}

private func paragraphHeaderPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0x8000_0000)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt32(1)))
    return data
}

private func listHeaderPayload(paragraphCount: Int32) -> Data {
    var data = Data()
    data.append(littleEndianData(paragraphCount))
    data.append(littleEndianData(UInt32(0)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
