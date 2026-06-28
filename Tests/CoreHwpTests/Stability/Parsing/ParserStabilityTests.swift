@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParserStabilityTests: XCTestCase {
    func testTruncatedPrimitiveReadThrowsTypedError() {
        expect {
            var reader = DataReader(Data([0x01]))
            _ = try reader.read(UInt32.self)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 1
        })
    }

    func testNegativeByteReadLengthThrowsTypedError() {
        expect {
            var reader = DataReader(Data())
            _ = try reader.readBytes(Int(-1))
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })
    }

    func testOversizedByteReadLengthThrowsTypedError() {
        let oversizedLength = UInt64(Int.max) + 1

        expect {
            var reader = DataReader(Data())
            _ = try reader.readBytes(oversizedLength)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == String(oversizedLength)
        })
    }

    func testNegativeArrayReadLengthThrowsTypedError() {
        expect {
            var reader = DataReader(Data())
            _ = try reader.read(UInt16.self, Int(-1))
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })
    }

    func testArrayReadPreflightsRequiredBytes() throws {
        var reader = DataReader(Data([0x01, 0x02]))

        expect {
            _ = try reader.read(UInt16.self, 2)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 2
        })

        expect(try reader.read(UInt8.self)) == UInt8(0x01)
    }

    func testUnsupportedPrimitiveReadThrowsTypedError() {
        expect {
            var reader = DataReader(Data())
            _ = try reader.read(UInt64.self)
        }.to(throwError { error in
            guard case let HwpError.unsupportedDataReadType(type) = error else {
                return fail("Expected unsupportedDataReadType, got \(error)")
            }
            expect(type) == "UInt64"
        })
    }

    func testInvalidWCharThrowsTypedError() {
        expect {
            let value: WCHAR = 0xD800
            _ = try value.character
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }

    func testSectionPreservesUnknownTopLevelRecords() throws {
        var data = recordData(tagId: 0x2FE, level: 0, payload: Data([0xCA, 0xFE]))
        data.append(recordData(tagId: 0x2FD, level: 1, payload: Data([0xAA])))
        data.append(
            recordData(
                tagId: HwpSectionTag.paraHeader.rawValue,
                level: 0,
                payload: paragraphHeaderPayload()
            )
        )
        data.append(
            recordData(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data())
        )
        data.append(
            recordData(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data())
        )

        let section = try HwpSection.load(data, HwpVersion(5, 0, 1, 1))
        var sameSection = section
        sameSection.rawPayload = Data([0xFF])

        expect(section.rawPayload) == data
        expect(section.paragraph.count) == 1
        expect(section.unknownRecords) == [
            expectedTopLevelSectionUnknownRecord(),
        ]
        expect(sameSection) == section
    }

    func testSectionMissingParagraphHeaderThrowsTypedError() {
        let data = recordData(tagId: 0x2FE, level: 0, payload: Data([0xCA, 0xFE]))

        expectRecordDoesNotExist(tag: HwpSectionTag.paraHeader.rawValue) {
            _ = try HwpSection.load(data, HwpVersion(5, 0, 1, 1))
        }
    }

    func testParagraphMissingLineSegUsesEmptyLayoutCache() throws {
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphHeaderPayload()
        )
        paraHeader.children = [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
        ]

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        expect(paragraph.paraLineSeg.paraLineSegInternalArray).to(beEmpty())
    }

    func testUnknownControlPreservesRawPayloadAndChildren() throws {
        let ctrlId: UInt32 = 0x1234_5678
        var ctrlPayload = littleEndianData(ctrlId)
        ctrlPayload.append(contentsOf: [0xAA, 0xBB])

        let ctrlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        ctrlRecord.children.append(
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0x01, 0x02, 0x03]))
        )

        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphHeaderPayload()
        )
        paraHeader.children = [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ctrlRecord,
        ]

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        guard case let .unknown(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected unknown control")
        }

        expect(header.ctrlId) == ctrlId
        expect(header.rawPayload) == ctrlPayload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0x01, 0x02, 0x03])),
        ]
    }

    func testTableControlMissingTableChildThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue)
        )
        record.children.append(HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xAA])))

        expectRecordDoesNotExist(tag: HwpSectionTag.table.rawValue) {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testTableControlPreservesUnknownChildren() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue)
        )
        record.children.append(
            HwpRecord(tagId: 0x2FF, level: 2, payload: Data([0xAA, 0xBB]))
        )
        record.children.append(
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePropertyPayload()
            )
        )

        let table = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))

        expect(table.commonCtrlProperty.rawPayload) == record.payload
        expect(table.tableProperty.rowCount) == 0
        expect(table.tableProperty.rawPayload) == tablePropertyPayload()
        expect(table.tableProperty.rawTrailing).to(beEmpty())
        expect(table.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: Data([0xAA, 0xBB])),
        ]
    }

    func testTableControlParsesCellsAndParagraphs() throws {
        var tablePayload = commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue)
        let tableTrailing = Data([0xCA, 0xFE])
        tablePayload.append(tableTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: tablePayload
        )
        let paragraph = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 2,
            payload: paragraphHeaderPayload()
        )
        paragraph.children = [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 3, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 3, payload: Data()),
        ]
        record.children = [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePropertyPayload()
            ),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: tableCellHeaderPayload(paragraphCount: 1)
            ),
            paragraph,
        ]

        let table = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))

        expect(table.rawPayload) == record.payload
        expect(table.commonCtrlProperty.rawPayload) ==
            commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue)
        expect(table.rawTrailing) == tableTrailing
        expect(table.cellArray.count) == 1
        expect(table.cellArray.first?.header.paragraphCount) == 1
        expect(table.cellArray.first?.header.rawPayload) ==
            tableCellHeaderPayload(paragraphCount: 1)
        expect(table.cellArray.first?.header.rawTrailing) == Data(repeating: 0, count: 39)
        expect(table.cellArray.first?.paragraphArray.count) == 1
        expect(table.unknownChildren).to(beEmpty())
    }

    func testTableControlMissingCellParagraphThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: commonCtrlPropertyPayload(ctrlId: HwpCommonCtrlId.table.rawValue)
        )
        record.children = [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePropertyPayload()
            ),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: tableCellHeaderPayload(paragraphCount: 1)
            ),
        ]

        expect {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("table cell paragraph is missing"))
        })
    }

    func testSectionDefMissingRequiredChildTagThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: sectionDefPayload()
        )
        for _ in 0 ..< 6 {
            record.children.append(HwpRecord(tagId: 0x2FF, level: 2, payload: Data()))
        }

        expectRecordDoesNotExist(tag: HwpSectionTag.pageDef.rawValue) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testSectionDefPreservesUnknownChildren() throws {
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: sectionDefPayload()
        )
        record.children = sectionDefChildrenWithUnconsumedRecords()

        let sectionDef = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))

        expect(sectionDef.rawPayload) == record.payload
        expect(sectionDef.pageDef.width) == 0
        expect(sectionDef.unknownChildren) == expectedSectionDefUnknownChildren()
    }
}

private func expectRecordDoesNotExist(
    tag expectedTag: UInt32,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.recordDoesNotExist(tag) = error else {
            return fail("Expected recordDoesNotExist, got \(error)")
        }
        expect(tag) == expectedTag
    })
}

private func sectionDefChildrenWithUnconsumedRecords() -> [HwpRecord] {
    [
        sectionDefChild(.pageDef, pageDefPayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.footnoteShape, Data([0xF0])),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, Data([0xB0])),
        HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA, 0xFE])),
    ]
}

private func sectionDefChild(_ tag: HwpSectionTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 2, payload: payload)
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

private func tablePropertyPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(0)))
    return data
}

private func tableCellHeaderPayload(paragraphCount: Int32) -> Data {
    var data = Data()
    data.append(littleEndianData(paragraphCount))
    data.append(littleEndianData(UInt32(0)))
    data.append(Data(repeating: 0, count: 39))
    return data
}

private func sectionDefPayload() -> Data {
    var data = Data()
    data.append(littleEndianData(HwpOtherCtrlId.section.rawValue))
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

private func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = littleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
