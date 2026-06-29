// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TableControlRawPayloadStabilityTests: XCTestCase {
    func testTableInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = concatenatedData(tableStabilityCommonCtrlPropertyPayload(), rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        let tablePropertyPayload = tableStabilityTablePropertyPayload(
            rowCount: 1,
            columnCount: 1,
            rawTrailing: Data([0xAB])
        )
        let cellHeaderPayload = tableStabilityCellHeaderPayload(
            paragraphCount: 0,
            rawTrailing: Data([0xBC])
        )
        let expectedCellRawTrailing = concatenatedData(Data(repeating: 0, count: 39), Data([0xBC]))
        let unknownPayload = Data([0xDD])
        let unknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: unknownPayload)
        let cellHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: cellHeaderPayload
        )
        cellHeader.children = [
            HwpRecord(tagId: 0x2FD, level: 3, payload: Data([0xCD])),
        ]
        var reader = DataReader(slicedPayload)

        let table = try HwpTable(
            &reader,
            [
                unknownChild,
                HwpRecord(
                    tagId: HwpSectionTag.table.rawValue,
                    level: 2,
                    payload: tablePropertyPayload
                ),
                cellHeader,
            ],
            HwpVersion(5, 0, 1, 1)
        )

        expect(table.rawPayload) == slicedPayload
        expect(table.rawTrailing) == rawTrailing
        expect(table.tableProperty.rawPayload) == tablePropertyPayload
        expect(table.tableProperty.rawTrailing) == Data([0xAB])
        expect(table.cellArray.map(\.header.rawPayload)) == [cellHeaderPayload]
        expect(table.cellArray.map(\.header.rawTrailing)) == [expectedCellRawTrailing]
        expect(table.cellArray.first?.header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FD, level: 3, payload: Data([0xCD])),
        ]
        expect(table.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testTablePropertyInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        var rawPayload = tableStabilityTablePropertyPayload(
            rowCount: 1,
            columnCount: 1,
            zonePropertySize: 1
        )
        rawPayload.append(tableStabilityZonePropertyPayload(borderFillId: 7))
        rawPayload.append(rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let property = try HwpTableProperty(&reader, HwpVersion(5, 0, 1, 1))

        expect(property.rawPayload) == slicedPayload
        expect(property.rawTrailing) == rawTrailing
        expect(property.rowCount) == 1
        expect(property.columnCount) == 1
        expect(property.validZoneInfoSize) == 1
        expect(property.zonePropertyArray?.map(\.borderFillId)) == [7]
        expect(reader.isEOF) == true
    }

    func testTableCellHeaderInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = tableStabilityCellHeaderPayload(
            paragraphCount: 0,
            rawTrailing: rawTrailing
        )
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        let unknownPayload = Data([0xCD])
        var reader = DataReader(slicedPayload)

        let header = try HwpTableCellHeader(
            &reader,
            [HwpRecord(tagId: 0x2FE, level: 3, payload: unknownPayload)]
        )

        expect(header.rawPayload) == slicedPayload
        expect(header.rawTrailing) == concatenatedData(Data(repeating: 0, count: 39), rawTrailing)
        expect(header.paragraphCount) == 0
        expect(header.property) == 0
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 3, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }
}

final class TableControlStabilityTests: XCTestCase {
    func testParagraphPreservesTruncatedTableControlAsNotImplemented() throws {
        let rawPayload = tableStabilityLittleEndianData(HwpCommonCtrlId.table.rawValue)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        record.children = [
            HwpRecord(tagId: HwpSectionTag.table.rawValue, level: 2, payload: Data([0xAA])),
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB])),
        ]

        expect {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 0
        })

        let paragraph = try HwpParagraph.load(
            tableStabilityParagraphRecord(children: [
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
            return fail("Expected truncated table control to be preserved as notImplemented")
        }
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )
        guard case let .notImplemented(decodedHeader) = decoded.ctrlHeaderArray?.first else {
            return fail("Expected decoded truncated table control to stay notImplemented")
        }

        assertTruncatedTableControlHeader(header, rawPayload: rawPayload)
        expect(decodedHeader) == header
    }

    func testTableControlNegativeCellParagraphCountThrowsTypedError() {
        let record = tableStabilityControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tableStabilityTablePropertyPayload()
            ),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: tableStabilityCellHeaderPayload(paragraphCount: -1)
            ),
        ])

        expect {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("table cell paragraph count is negative: -1"))
        })
    }

    func testTablePropertyRejectsTruncatedZonePropertyArrayBeforeIterating() {
        var payload = tableStabilityTablePropertyPayload(zonePropertySize: 2)
        payload.append(tableStabilityZonePropertyPayload(borderFillId: 7))

        expect {
            _ = try HwpTableProperty.load(payload, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 20
            expect(actual) == 10
        })
    }

    func testTableCellHeaderPreservesUnknownChildRecords() throws {
        let unknownChild = HwpRecord(tagId: 0x2FE, level: 3, payload: Data([0xCA, 0xFE]))
        let cellHeader = HwpRecord(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 2,
            payload: tableStabilityCellHeaderPayload(paragraphCount: 0)
        )
        cellHeader.children = [unknownChild]
        let record = tableStabilityControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tableStabilityTablePropertyPayload()
            ),
            cellHeader,
        ])

        let table = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))

        expect(table.cellArray.count) == 1
        expect(table.cellArray.first?.header.rawPayload) ==
            tableStabilityCellHeaderPayload(paragraphCount: 0)
        expect(table.cellArray.first?.header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 3, payload: Data([0xCA, 0xFE])),
        ]
        expect(table.cellArray.first?.paragraphArray).to(beEmpty())
        expect(table.unknownChildren).to(beEmpty())
    }

    func testTableControlUnexpectedCellParagraphTagThrowsTypedError() {
        let unexpectedTagId: UInt32 = 0x2FE
        let record = tableStabilityControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tableStabilityTablePropertyPayload()
            ),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: tableStabilityCellHeaderPayload(paragraphCount: 1)
            ),
            HwpRecord(tagId: unexpectedTagId, level: 2, payload: Data([0xAA])),
        ])

        expect {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("table cell expected paragraph, got tag \(unexpectedTagId)"))
        })
    }

    func testParagraphDoesNotHideMissingTablePropertyAsNotImplemented() {
        let record = tableStabilityControlRecord(children: [
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xAA])),
        ])

        expect {
            _ = try HwpParagraph.load(
                tableStabilityParagraphRecord(children: [
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
        }.to(throwError { error in
            guard case let HwpError.recordDoesNotExist(tag) = error else {
                return fail("Expected recordDoesNotExist, got \(error)")
            }
            expect(tag) == HwpSectionTag.table.rawValue
        })
    }

    func testParagraphDoesNotHideMissingTableCellHeaderAsNotImplemented() {
        let record = tableStabilityControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tableStabilityTablePropertyPayload(rowCount: 1, columnCount: 1)
            ),
            HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xAA])),
        ])

        expectRecordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue) {
            _ = try HwpTable.load(record, HwpVersion(5, 0, 1, 1))
        }
        expectRecordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue) {
            _ = try HwpParagraph.load(
                tableStabilityParagraphRecord(children: [
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
        }
    }

    func testParagraphDoesNotHideInvalidTableCellTreeAsNotImplemented() {
        let record = tableStabilityControlRecord(children: [
            HwpRecord(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tableStabilityTablePropertyPayload()
            ),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: tableStabilityCellHeaderPayload(paragraphCount: 1)
            ),
        ])

        expect {
            _ = try HwpParagraph.load(
                tableStabilityParagraphRecord(children: [
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
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason) == "table cell paragraph is missing"
        })
    }
}

private func assertTruncatedTableControlHeader(
    _ header: HwpCtrlHeader,
    rawPayload: Data
) {
    expect(header.ctrlId) == HwpCommonCtrlId.table.rawValue
    expect(header.rawPayload) == rawPayload
    expect(header.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: Data([0xAA])
        ),
        expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB])),
    ]
}

private func tableStabilityControlRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: tableStabilityCommonCtrlPropertyPayload()
    )
    record.children = children
    return record
}

private func tableStabilityParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: tableStabilityParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func tableStabilityCommonCtrlPropertyPayload() -> Data {
    var data = Data()
    data.append(tableStabilityLittleEndianData(HwpCommonCtrlId.table.rawValue))
    data.append(tableStabilityLittleEndianData(UInt32(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT(0)))
    data.append(tableStabilityLittleEndianData(Int32(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(UInt32(0)))
    data.append(tableStabilityLittleEndianData(Int32(0)))
    data.append(tableStabilityLittleEndianData(WORD(0)))
    return data
}

private func tableStabilityTablePropertyPayload(zonePropertySize: UInt16 = 0) -> Data {
    tableStabilityTablePropertyPayload(
        rowCount: 0,
        columnCount: 0,
        zonePropertySize: zonePropertySize
    )
}

private func tableStabilityTablePropertyPayload(
    rowCount: UInt16,
    columnCount: UInt16,
    zonePropertySize: UInt16 = 0,
    rawTrailing: Data = Data()
) -> Data {
    var data = Data()
    data.append(tableStabilityLittleEndianData(UInt32(0)))
    data.append(tableStabilityLittleEndianData(rowCount))
    data.append(tableStabilityLittleEndianData(columnCount))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    data.append(tableStabilityLittleEndianData(HWPUNIT16(0)))
    for _ in 0 ..< rowCount {
        data.append(tableStabilityLittleEndianData(UInt16(0)))
    }
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(zonePropertySize))
    data.append(rawTrailing)
    return data
}

private func tableStabilityZonePropertyPayload(borderFillId: UInt16) -> Data {
    var data = Data()
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(borderFillId))
    return data
}

private func tableStabilityCellHeaderPayload(
    paragraphCount: Int32,
    rawTrailing: Data = Data()
) -> Data {
    var data = Data()
    data.append(tableStabilityLittleEndianData(paragraphCount))
    data.append(tableStabilityLittleEndianData(UInt32(0)))
    data.append(Data(repeating: 0, count: 39))
    data.append(rawTrailing)
    return data
}

private func tableStabilityParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(tableStabilityLittleEndianData(UInt32(0x8000_0000)))
    data.append(tableStabilityLittleEndianData(UInt32(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt8(0)))
    data.append(tableStabilityLittleEndianData(UInt8(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt16(0)))
    data.append(tableStabilityLittleEndianData(UInt32(1)))
    return data
}

private func tableStabilityLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
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
