@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class CommonShapeControlFallbackTests: XCTestCase {
    func testShapeControlPreservesMalformedCommonPropertyAsRawPayload() throws {
        let rawPayload = malformedCommonShapeFallbackControlPayload(
            ctrlId: HwpCommonCtrlId.picture.rawValue
        )
        var propertyReader = DataReader(rawPayload)

        expect {
            _ = try HwpCommonCtrlProperty(&propertyReader)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })

        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA])),
        ]

        let shapeControl = try HwpShapeControl.load(record, HwpVersion(5, 0, 1, 1))

        expect(shapeControl.ctrlId) == .picture
        expect(shapeControl.commonCtrlProperty).to(beNil())
        expect(shapeControl.rawPayload) == rawPayload
        expect(shapeControl.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(shapeControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA])),
        ]
    }

    func testParagraphPreservesMalformedCommonPropertyAsTypedShapeControl() throws {
        let rawPayload = malformedCommonShapeFallbackControlPayload(
            ctrlId: HwpCommonCtrlId.picture.rawValue
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA])),
        ]

        let paragraph = try HwpParagraph.load(
            commonShapeFallbackParagraphRecord(children: [
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

        guard case let .picture(shapeControl) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected malformed common property to stay typed picture control")
        }

        expect(shapeControl.ctrlId) == .picture
        expect(shapeControl.commonCtrlProperty).to(beNil())
        expect(shapeControl.rawPayload) == rawPayload
        expect(shapeControl.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(shapeControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA])),
        ]
    }

    func testParagraphPreservesShortCommonPropertyAsTypedShapeControl() throws {
        let rawTrailing = Data([0xAA, 0xBB, 0xCC])
        var rawPayload = commonShapeFallbackLittleEndianData(HwpCommonCtrlId.picture.rawValue)
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

        let paragraph = try HwpParagraph.load(
            commonShapeFallbackParagraphRecord(children: [
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

        guard case let .picture(shapeControl) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected short common property to stay typed picture control")
        }

        expect(shapeControl.ctrlId) == .picture
        expect(shapeControl.commonCtrlProperty).to(beNil())
        expect(shapeControl.rawPayload) == rawPayload
        expect(shapeControl.rawTrailing) == rawTrailing
        expect(shapeControl.ctrlDataRecords.map(\.rawPayload)) == [Data([0xDD])]
        expect(shapeControl.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xEE])),
        ]
    }

    func testParagraphPreservesMalformedCommonShapeTextBoxAsNotImplemented() throws {
        let record = malformedCommonShapeTextBoxRecord(ctrlId: .picture)

        expect {
            _ = try HwpShapeControl.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("text box paragraph is missing"))
        })

        let paragraph = try HwpParagraph.load(
            commonShapeFallbackParagraphRecord(children: [
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
            return fail("Expected malformed common shape to be preserved as notImplemented")
        }

        expect(header.ctrlId) == HwpCommonCtrlId.picture.rawValue
        expect(header.rawPayload) == record.payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: commonShapeFallbackLittleEndianData(HwpCommonCtrlId.rectangle.rawValue),
                children: [
                    expectedTestRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: commonShapeFallbackListHeaderPayload(paragraphCount: 1)
                    ),
                ]
            ),
        ]
    }
}

private func malformedCommonShapeTextBoxRecord(ctrlId: HwpCommonCtrlId) -> HwpRecord {
    let listHeader = HwpRecord(
        tagId: HwpSectionTag.listHeader.rawValue,
        level: 3,
        payload: commonShapeFallbackListHeaderPayload(paragraphCount: 1)
    )
    let shapeComponent = HwpRecord(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: commonShapeFallbackLittleEndianData(HwpCommonCtrlId.rectangle.rawValue)
    )
    shapeComponent.children = [listHeader]
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: commonShapeFallbackControlPayload(ctrlId: ctrlId.rawValue)
    )
    record.children = [shapeComponent]
    return record
}

private func commonShapeFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: commonShapeFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func commonShapeFallbackControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(commonShapeFallbackLittleEndianData(ctrlId))
    data.append(commonShapeFallbackLittleEndianData(UInt32(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(commonShapeFallbackLittleEndianData(Int32(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(commonShapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt32(0)))
    data.append(commonShapeFallbackLittleEndianData(Int32(0)))
    data.append(commonShapeFallbackLittleEndianData(WORD(0)))
    return data
}

private func malformedCommonShapeFallbackControlPayload(ctrlId: UInt32) -> Data {
    var data = commonShapeFallbackControlPayload(ctrlId: ctrlId)
    data.removeLast(MemoryLayout<WORD>.size)
    data.append(commonShapeFallbackLittleEndianData(WORD(1)))
    data.append(commonShapeFallbackLittleEndianData(WCHAR(0xD800)))
    return data
}

private func commonShapeFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(commonShapeFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(commonShapeFallbackLittleEndianData(UInt32(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt16(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt8(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt8(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt16(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt16(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt16(0)))
    data.append(commonShapeFallbackLittleEndianData(UInt32(1)))
    return data
}

private func commonShapeFallbackListHeaderPayload(paragraphCount: Int32) -> Data {
    concatenatedData(
        commonShapeFallbackLittleEndianData(paragraphCount),
        commonShapeFallbackLittleEndianData(UInt32(0))
    )
}

private func commonShapeFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
