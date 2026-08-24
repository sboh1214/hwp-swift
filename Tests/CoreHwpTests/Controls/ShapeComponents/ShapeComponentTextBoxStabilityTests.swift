@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeComponentTextBoxStabilityTests: XCTestCase {
    func testTextBoxNegativeParagraphCountThrowsTypedError() {
        let record = textBoxShapeComponentRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 3,
                payload: textBoxListHeaderPayload(paragraphCount: -1)
            ),
        ])

        expect {
            _ = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("text box paragraph count is negative: -1"))
        })
    }

    func testTextBoxUnexpectedParagraphTagThrowsTypedError() {
        let unexpectedTagId: UInt32 = 0x2FE
        let record = textBoxShapeComponentRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 3,
                payload: textBoxListHeaderPayload(paragraphCount: 1)
            ),
            HwpRecord(tagId: unexpectedTagId, level: 3, payload: Data([0xAA])),
        ])

        expect {
            _ = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("text box expected paragraph, got tag \(unexpectedTagId)"))
        })
    }

    func testTextBoxMissingDeclaredParagraphThrowsTypedError() {
        let record = textBoxShapeComponentRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 3,
                payload: textBoxListHeaderPayload(paragraphCount: 1)
            ),
        ])

        expect {
            _ = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "text box paragraph is missing"
        })
    }

    func testTextBoxConsumesDeclaredParagraphsAndPreservesUnknownChildren() throws {
        let headerUnknownChild = HwpRecord(tagId: 0x2FD, level: 4, payload: Data([0xCA]))
        headerUnknownChild.children = [
            HwpRecord(tagId: 0x2FC, level: 5, payload: Data([0xCB])),
        ]
        let listHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 3,
            payload: textBoxListHeaderPayload(
                paragraphCount: 1,
                rawTrailing: Data([0xCC])
            )
        )
        listHeader.children = [headerUnknownChild]
        let unknownSibling = HwpRecord(tagId: 0x2FE, level: 3, payload: Data([0xDD]))
        let record = textBoxShapeComponentRecord(children: [
            listHeader,
            textBoxParagraphRecord(),
            unknownSibling,
        ])

        let component = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))

        expect(component.textBoxListArray.count) == 1
        let list = try XCTUnwrap(component.textBoxListArray.first)
        expect(list.header.paragraphCount) == 1
        expect(list.header.rawTrailing) == Data([0xCC])
        expect(list.headerRawPayload) == listHeader.payload
        expect(list.headerUnknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2FD,
                level: 4,
                payload: Data([0xCA]),
                children: [
                    expectedTestRecord(tagId: 0x2FC, level: 5, payload: Data([0xCB])),
                ]
            ),
        ]
        expect(list.paragraphArray.count) == 1
        expect(list.paragraphArray.first?.paraHeader.rawPayload) == textBoxParagraphHeaderPayload()
        expect(component.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 3, payload: Data([0xDD])),
        ]
    }

    func testTextBoxConsumesTwoListsAndPreservesPerHeaderUnknownChildren() throws {
        let firstHeaderUnknownChild = HwpRecord(tagId: 0x2FD, level: 4, payload: Data([0xD1]))
        firstHeaderUnknownChild.children = [
            HwpRecord(tagId: 0x2FC, level: 5, payload: Data([0xD2])),
        ]
        let firstHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 3,
            payload: textBoxListHeaderPayload(paragraphCount: 1, rawTrailing: Data([0xC1]))
        )
        firstHeader.children = [firstHeaderUnknownChild]
        let secondHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 3,
            payload: textBoxListHeaderPayload(paragraphCount: 1, rawTrailing: Data([0xC2, 0xC3]))
        )
        secondHeader.children = [
            HwpRecord(tagId: 0x2FB, level: 4, payload: Data([0xD3])),
        ]
        let record = textBoxShapeComponentRecord(children: [
            firstHeader,
            textBoxParagraphRecord(
                unknownChild: HwpRecord(tagId: 0x2FA, level: 4, payload: Data([0xE1]))
            ),
            secondHeader,
            textBoxParagraphRecord(
                unknownChild: HwpRecord(tagId: 0x2F9, level: 4, payload: Data([0xE2]))
            ),
        ])

        let component = try HwpShapeComponent.load(record, HwpVersion(5, 0, 1, 1))

        expect(component.textBoxListArray.count) == 2
        expect(component.textBoxListArray.map(\.header.paragraphCount)) == [1, 1]
        expect(component.textBoxListArray.map(\.headerRawPayload)) == [
            firstHeader.payload,
            secondHeader.payload,
        ]
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
        expect(component.textBoxListArray.flatMap(\.paragraphArray).map(\.unknownChildren)) == [
            [
                expectedTestUnknownRecord(tagId: 0x2FA, level: 4, payload: Data([0xE1])),
            ],
            [
                expectedTestUnknownRecord(tagId: 0x2F9, level: 4, payload: Data([0xE2])),
            ],
        ]
    }
}

private func textBoxShapeComponentRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: textBoxLittleEndianData(HwpCommonCtrlId.rectangle.rawValue)
    )
    record.children = children
    return record
}

private func textBoxListHeaderPayload(
    paragraphCount: Int32,
    rawTrailing: Data = Data()
) -> Data {
    var data = Data()
    data.append(textBoxLittleEndianData(paragraphCount))
    data.append(textBoxLittleEndianData(UInt32(0)))
    data.append(rawTrailing)
    return data
}

private func textBoxParagraphRecord(unknownChild: HwpRecord? = nil) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 3,
        payload: textBoxParagraphHeaderPayload()
    )
    var children = [
        HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 4, payload: Data()),
    ]
    if let unknownChild {
        children.append(unknownChild)
    }
    record.children = children
    return record
}

private func textBoxParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(textBoxLittleEndianData(UInt32(0x8000_0000)))
    data.append(textBoxLittleEndianData(UInt32(0)))
    data.append(textBoxLittleEndianData(UInt16(0)))
    data.append(textBoxLittleEndianData(UInt8(0)))
    data.append(textBoxLittleEndianData(UInt8(0)))
    data.append(textBoxLittleEndianData(UInt16(0)))
    data.append(textBoxLittleEndianData(UInt16(0)))
    data.append(textBoxLittleEndianData(UInt16(0)))
    data.append(textBoxLittleEndianData(UInt32(1)))
    return data
}

private func textBoxLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
