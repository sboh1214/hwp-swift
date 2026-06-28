@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SpecializedControlValidationTests: XCTestCase {
    func testTableControlRejectsMismatchedCommonControlId() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.picture.rawValue)
        )

        expectInvalidCtrlId(HwpCommonCtrlId.picture.rawValue) {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testGenShapeObjectRejectsMismatchedCommonControlId() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.picture.rawValue)
        )

        expectInvalidCtrlId(HwpCommonCtrlId.picture.rawValue) {
            _ = try HwpGenShapeObject.load(record)
        }
    }

    func testColumnControlRejectsMismatchedOtherControlId() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: littleEndianData(HwpOtherCtrlId.pageHide.rawValue)
        )

        expectInvalidCtrlId(HwpOtherCtrlId.pageHide.rawValue) {
            _ = try HwpColumn.load(record)
        }
    }

    func testOtherControlRejectsUnknownOtherControlId() {
        let invalidCtrlId = UInt32(0x1234_5678)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: littleEndianData(invalidCtrlId)
        )

        expectInvalidCtrlId(invalidCtrlId) {
            _ = try HwpOtherControl.load(record)
        }
    }

    func testHyperlinkRejectsMismatchedFieldControlId() {
        let ctrlId = HwpFieldCtrlId.privateInfoSecurity.rawValue
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: littleEndianData(ctrlId)
        )

        expectInvalidCtrlId(ctrlId) {
            _ = try HwpHyperlink.load(record)
        }
    }

    func testSectionDefRejectsMismatchedOtherControlId() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: sectionDefPayload(ctrlId: HwpOtherCtrlId.pageHide.rawValue)
        )
        record.children = sectionDefChildren()

        expectInvalidCtrlId(HwpOtherCtrlId.pageHide.rawValue) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }
}

private func expectInvalidCtrlId(_ expected: UInt32, _ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidCtrlId(actual) = error else {
            return fail("Expected invalidCtrlId, got \(error)")
        }
        expect(actual) == expected
    })
}

private func commonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
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

private func sectionDefPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    return data
}

private func sectionDefChildren() -> [HwpRecord] {
    [
        sectionDefChild(.pageDef, pageDefPayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
    ]
}

private func sectionDefChild(_ tag: HwpSectionTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

private func pageDefPayload() -> Data {
    var data = Data()
    for _ in 0 ..< 9 {
        data.append(littleEndianData(HWPUNIT(0)))
    }
    data.append(littleEndianData(UInt32(0)))
    return data
}

private func footnoteShapePayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(COLORREF(0)))
    data.append(contentsOf: [0, 0])
    return data
}

private func pageBorderFillPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt16(0)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
