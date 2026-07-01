@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ColumnControlStabilityTests: XCTestCase {
    func testColumnInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = columnPayload(rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        let unknownPayload = Data([0xCD])
        let unknownChild = HwpRecord(tagId: 0x2FA, level: 2, payload: unknownPayload)
        var reader = DataReader(slicedPayload)

        let column = try HwpColumn(&reader, [unknownChild])

        expect(column.rawPayload) == slicedPayload
        expect(column.rawTrailing) == rawTrailing
        expect(column.rawTrailingWords) == [UInt16(0xFECA)]
        expect(column.unknown) == rawTrailing
        expect(column.otherCtrlId) == .column
        expect(column.property.rawValue) == 4100
        expect(column.property.count) == 1
        expect(column.spacing) == 0x1122
        expect(column.property2) == 0x3344
        expect(column.dividerType) == 0x55
        expect(column.dividerThickness) == 0x66
        expect(column.widthArray).to(beNil())
        expect(column.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testParagraphPreservesTruncatedColumnControlAsGenericOtherControl() throws {
        let rawPayload = concatenatedData(
            columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue),
            Data([0xAA])
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xCD])))

        expect {
            _ = try HwpColumn.load(record)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
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

        guard case let .other(other) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated column to be preserved as other")
        }

        expect(other.ctrlId) == .column
        expect(other.rawPayload) == rawPayload
        expect(other.rawTrailing) == Data([0xAA])
        expect(other.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xCD])),
        ]
    }

    func testParagraphPreservesColumnWithUnknownPropertyEnumAsGenericOtherControl() throws {
        let rawPayload = columnPayloadWithUnknownType()
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children.append(HwpRecord(tagId: 0x2FA, level: 2, payload: Data([0xCD])))

        expect {
            _ = try HwpColumn.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidRawValueForEnum(model, rawValue) = error else {
                return fail("Expected invalidRawValueForEnum, got \(error)")
            }
            expect(String(describing: model)) == "HwpColumnType"
            expect(rawValue) == 3
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

        guard case let .other(other) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected column with unknown property enum to be preserved as other")
        }

        expect(other.ctrlId) == .column
        expect(other.rawPayload) == rawPayload
        expect(other.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
        expect(other.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: Data([0xCD])),
        ]
    }

    func testVariableWidthColumnPreservesWidthArrayAndTrailingBytes() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = variableWidthColumnPayload(
            widths: [0x1111, 0x2222],
            gaps: [0x3333, 0x4444],
            property2: 0xABCD,
            rawTrailing: rawTrailing
        )
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let column = try HwpColumn.load(record)

        expect(column.property.rawValue) == variableWidthColumnProperty(count: 2)
        expect(column.property.count) == 2
        expect(column.property.isSameWidth) == false
        expect(column.property2) == 0xABCD
        expect(column.widthArray) == [0x1111, 0x2222]
        expect(column.gapArray) == [0x3333, 0x4444]
        expect(column.spacing).to(beNil())
        expect(column.rawPayload) == rawPayload
        expect(column.rawTrailing) == rawTrailing
        expect(column.rawTrailingWords) == [UInt16(0xFECA)]
        expect(column.unknown) == rawTrailing
    }

    func testColumnOddTrailingBytesRemainRawOnly() throws {
        let rawTrailing = Data([0xCA])
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: columnPayload(rawTrailing: rawTrailing)
        )

        let column = try HwpColumn.load(record)

        expect(column.rawTrailing) == rawTrailing
        expect(column.rawTrailingWords).to(beNil())
        expect(column.unknown) == rawTrailing
    }

    func testVariableWidthColumnRejectsWidthCountMismatchBeforeReadingDivider() {
        var rawPayload = Data()
        rawPayload.append(columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue))
        rawPayload.append(columnStabilityLittleEndianData(variableWidthColumnProperty(count: 3)))
        rawPayload.append(columnStabilityLittleEndianData(UInt16(0)))
        rawPayload.append(columnStabilityLittleEndianData(WORD(0x1111)))
        rawPayload.append(columnStabilityLittleEndianData(WORD(0x0101)))
        rawPayload.append(columnStabilityLittleEndianData(WORD(0x2222)))
        rawPayload.append(columnStabilityLittleEndianData(WORD(0x0202)))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        expect {
            _ = try HwpColumn.load(record)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 0
        })
    }

    func testVariableWidthColumnRejectsOversizedWidthCountBeforeIterating() {
        var rawPayload = Data()
        rawPayload.append(columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue))
        rawPayload.append(columnStabilityLittleEndianData(variableWidthColumnProperty(count: 255)))
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        expect {
            _ = try HwpColumn.load(record)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == MemoryLayout<UInt16>.size
            expect(actual) == 0
        })
    }
}

private func columnPayloadWithUnknownType() -> Data {
    var data = Data()
    data.append(columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue))
    data.append(columnStabilityLittleEndianData(UInt16(3)))
    data.append(columnStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(columnStabilityLittleEndianData(UInt16(0)))
    data.append(columnStabilityLittleEndianData(UInt8(0)))
    data.append(columnStabilityLittleEndianData(UInt8(0)))
    data.append(columnStabilityLittleEndianData(COLORREF(0)))
    return data
}

private func columnPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    data.append(columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue))
    data.append(columnStabilityLittleEndianData(UInt16(4100)))
    data.append(columnStabilityLittleEndianData(HWPUNIT16(0x1122)))
    data.append(columnStabilityLittleEndianData(UInt16(0x3344)))
    data.append(columnStabilityLittleEndianData(UInt8(0x55)))
    data.append(columnStabilityLittleEndianData(UInt8(0x66)))
    data.append(columnStabilityLittleEndianData(COLORREF(0x7788_99AA)))
    data.append(rawTrailing)
    return data
}

private func variableWidthColumnPayload(
    widths: [WORD],
    gaps: [WORD],
    property2: UInt16 = 0,
    rawTrailing: Data = Data()
) -> Data {
    var data = Data()
    data.append(columnStabilityLittleEndianData(HwpOtherCtrlId.column.rawValue))
    data.append(columnStabilityLittleEndianData(variableWidthColumnProperty(count: widths.count)))
    data.append(columnStabilityLittleEndianData(property2))
    for (width, gap) in zip(widths, gaps) {
        data.append(columnStabilityLittleEndianData(width))
        data.append(columnStabilityLittleEndianData(gap))
    }
    data.append(columnStabilityLittleEndianData(UInt8(0x55)))
    data.append(columnStabilityLittleEndianData(UInt8(0x66)))
    data.append(columnStabilityLittleEndianData(COLORREF(0x7788_99AA)))
    data.append(rawTrailing)
    return data
}

private func variableWidthColumnProperty(count: Int) -> UInt16 {
    UInt16(count << 2)
}

private func paragraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: columnStabilityParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func columnStabilityParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(columnStabilityLittleEndianData(UInt32(0x8000_0000)))
    data.append(columnStabilityLittleEndianData(UInt32(0)))
    data.append(columnStabilityLittleEndianData(UInt16(0)))
    data.append(columnStabilityLittleEndianData(UInt8(0)))
    data.append(columnStabilityLittleEndianData(UInt8(0)))
    data.append(columnStabilityLittleEndianData(UInt16(0)))
    data.append(columnStabilityLittleEndianData(UInt16(0)))
    data.append(columnStabilityLittleEndianData(UInt16(0)))
    data.append(columnStabilityLittleEndianData(UInt32(1)))
    return data
}

private func columnStabilityLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
