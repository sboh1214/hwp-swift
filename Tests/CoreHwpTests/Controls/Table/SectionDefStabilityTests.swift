@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SectionDefStabilityTests: XCTestCase {
    func testSectionDefInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = concatenatedData(sectionDefPayload(), rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        let unknownPayload = Data([0xDD])
        let unknownChild = HwpRecord(tagId: 0x2FE, level: 2, payload: unknownPayload)
        var reader = DataReader(slicedPayload)

        let sectionDef = try HwpSectionDef(
            &reader,
            requiredSectionDefChildren() + [unknownChild],
            HwpVersion(5, 0, 1, 1)
        )

        expect(sectionDef.rawPayload) == slicedPayload
        expect(sectionDef.unknown) == rawTrailing
        expect(sectionDef.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: unknownPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testPageDefInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = pageDefPayload(rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let pageDef = try HwpPageDef(&reader)

        expect(pageDef.rawPayload) == slicedPayload
        expect(pageDef.rawTrailing) == rawTrailing
        expect(reader.isEOF) == true
    }

    func testFootnoteShapeInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0x00, 0x00, 0xCA, 0xFE])
        let rawPayload = footnoteShapePayload(rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let shape = try HwpFootnoteShape(&reader)

        expect(shape.rawPayload) == slicedPayload
        expect(shape.rawTrailing) == rawTrailing
        expect(shape.unknown) == rawTrailing
        expect(reader.isEOF) == true
    }

    func testPageBorderFillInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawTrailing = Data([0xCA, 0xFE])
        let rawPayload = pageBorderFillPayload(rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let fill = try HwpPageBorderFill(&reader)

        expect(fill.rawPayload) == slicedPayload
        expect(fill.rawTrailing) == rawTrailing
        expect(reader.isEOF) == true
    }

    func testParagraphPreservesTruncatedSectionDefAsGenericOtherControl() throws {
        let rawPayload = littleEndianData(HwpOtherCtrlId.section.rawValue)
        let record = sectionDefRecord(
            rawPayload: rawPayload,
            children: requiredSectionDefChildren()
        )
        record.children.append(HwpRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB])))

        expect {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 0
        })

        let paragraph = try HwpParagraph.load(
            sectionDefParagraphRecord(children: [
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
            return fail("Expected truncated section definition to be preserved as other")
        }

        expect(other.ctrlId) == .section
        expect(other.rawPayload) == rawPayload
        expect(other.rawTrailing).to(beEmpty())
        expect(other.unknownChildren) == expectedTruncatedSectionDefFallbackChildren()
    }

    func testParagraphDoesNotHideMissingSectionDefRequiredChild() {
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, pageDefPayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        ])

        expect {
            _ = try HwpParagraph.load(
                sectionDefParagraphRecord(children: [
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
            expect(tag) == HwpSectionTag.footnoteShape.rawValue
        })
    }

    func testFootnoteShapePreservesRawPayloadAndTrailingBytes() throws {
        let trailing = Data([0x00, 0x00, 0xCA, 0xFE])
        let payload = footnoteShapePayload(rawTrailing: trailing)
        let shape = try HwpFootnoteShape.load(payload)

        expect(shape.rawPayload) == payload
        expect(shape.rawTrailing) == trailing
        expect(shape.unknown) == trailing
    }

    func testFootnoteShapeRejectsTruncatedTrailingBytesWithTypedError() {
        let payload = footnoteShapePayload(rawTrailing: Data([0x00]))

        expect {
            _ = try HwpFootnoteShape.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })
    }

    func testSectionDefPreservesFootnoteShapeRawPayloads() throws {
        let pagePayload = pageDefPayload(rawTrailing: Data([0xD0, 0xD1]))
        let footnotePayload = footnoteShapePayload(rawTrailing: Data([0x00, 0x00, 0xAA]))
        let endnotePayload = footnoteShapePayload(rawTrailing: Data([0x00, 0x00, 0xBB]))
        let bothBorderPayload = pageBorderFillPayload(rawTrailing: Data([0xA0]))
        let evenBorderPayload = pageBorderFillPayload(rawTrailing: Data([0xB0, 0xB1]))
        let oddBorderPayload = pageBorderFillPayload(rawTrailing: Data([0xC0, 0xC1, 0xC2]))
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, pagePayload),
            sectionDefChild(.footnoteShape, footnotePayload),
            sectionDefChild(.footnoteShape, endnotePayload),
            sectionDefChild(.pageBorderFill, bothBorderPayload),
            sectionDefChild(.pageBorderFill, evenBorderPayload),
            sectionDefChild(.pageBorderFill, oddBorderPayload),
        ])

        let sectionDef = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))

        expect(sectionDef.pageDef.rawPayload) == pagePayload
        expect(sectionDef.pageDef.rawTrailing) == Data([0xD0, 0xD1])
        expect(sectionDef.footNoteShape.rawPayload) == footnotePayload
        expect(sectionDef.footNoteShape.rawTrailing) == Data([0x00, 0x00, 0xAA])
        expect(sectionDef.endNoteShape.rawPayload) == endnotePayload
        expect(sectionDef.endNoteShape.rawTrailing) == Data([0x00, 0x00, 0xBB])
        expect(sectionDef.pageBorderFillBoth.rawPayload) == bothBorderPayload
        expect(sectionDef.pageBorderFillBoth.rawTrailing) == Data([0xA0])
        expect(sectionDef.pageBorderFillEven.rawPayload) == evenBorderPayload
        expect(sectionDef.pageBorderFillEven.rawTrailing) == Data([0xB0, 0xB1])
        expect(sectionDef.pageBorderFillOdd.rawPayload) == oddBorderPayload
        expect(sectionDef.pageBorderFillOdd.rawTrailing) == Data([0xC0, 0xC1, 0xC2])
    }

    func testSectionDefRejectsTruncatedPageDefChildWithTypedError() {
        var truncatedPageDef = pageDefPayload()
        truncatedPageDef.removeLast()
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, truncatedPageDef),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        ])

        expectTruncatedData(expected: 4, actual: 3) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testParagraphPreservesTruncatedSectionDefChildAsGenericOtherControl() throws {
        var truncatedPageDef = pageDefPayload()
        truncatedPageDef.removeLast()
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, truncatedPageDef),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        ])

        expectTruncatedData(expected: 4, actual: 3) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }

        let paragraph = try HwpParagraph.load(
            sectionDefParagraphRecord(children: [
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
            return fail("Expected truncated section definition child to be preserved as other")
        }

        expect(other.ctrlId) == .section
        expect(other.rawPayload) == record.payload
        expect(other.rawTrailing) == Data(record.payload.dropFirst(MemoryLayout<UInt32>.size))
        expect(other.unknownChildren) == expectedUnknownRecords(from: record.children)
    }

    func testSectionDefRejectsTruncatedPageBorderFillChildWithTypedError() {
        var truncatedPageBorderFill = pageBorderFillPayload()
        truncatedPageBorderFill.removeLast()
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, pageDefPayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, truncatedPageBorderFill),
        ])

        expectTruncatedData(expected: 2, actual: 1) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testSectionDefPreservesDuplicateRequiredChildrenAsUnknownRecords() throws {
        let duplicatePageDefPayload = pageDefPayload(rawTrailing: Data([0xA1]))
        let duplicateFootnotePayload = footnoteShapePayload(rawTrailing: Data([0x00, 0x00, 0xB1]))
        let duplicateBorderFillPayload = pageBorderFillPayload(rawTrailing: Data([0xC1]))
        let record = sectionDefRecord(children: requiredSectionDefChildren() + [
            sectionDefChild(.pageDef, duplicatePageDefPayload),
            sectionDefChild(.footnoteShape, duplicateFootnotePayload),
            sectionDefChild(.pageBorderFill, duplicateBorderFillPayload),
        ])

        let sectionDef = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))

        expect(sectionDef.unknownChildren) == [
            expectedSectionDefUnknownChild(.pageDef, duplicatePageDefPayload),
            expectedSectionDefUnknownChild(.footnoteShape, duplicateFootnotePayload),
            expectedSectionDefUnknownChild(.pageBorderFill, duplicateBorderFillPayload),
        ]
    }

    func testMissingSecondFootnoteShapeThrowsTypedError() {
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, pageDefPayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        ])

        expectRecordDoesNotExist(tag: HwpSectionTag.footnoteShape.rawValue) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testMissingThirdPageBorderFillThrowsTypedError() {
        let record = sectionDefRecord(children: [
            sectionDefChild(.pageDef, pageDefPayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.footnoteShape, footnoteShapePayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
            sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        ])

        expectRecordDoesNotExist(tag: HwpSectionTag.pageBorderFill.rawValue) {
            _ = try HwpSectionDef.load(record, HwpVersion(5, 0, 1, 1))
        }
    }
}

private func expectTruncatedData(
    expected expectedBytes: Int,
    actual actualBytes: Int,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.truncatedData(expected, actual) = error else {
            return fail("Expected truncatedData, got \(error)")
        }
        expect(expected) == expectedBytes
        expect(actual) == actualBytes
    })
}

private func sectionDefRecord(children: [HwpRecord]) -> HwpRecord {
    sectionDefRecord(rawPayload: sectionDefPayload(), children: children)
}

private func sectionDefRecord(rawPayload: Data, children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: rawPayload
    )
    record.children = children
    return record
}

private func requiredSectionDefChildren() -> [HwpRecord] {
    [
        sectionDefChild(.pageDef, pageDefPayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.footnoteShape, footnoteShapePayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
        sectionDefChild(.pageBorderFill, pageBorderFillPayload()),
    ]
}

private func sectionDefParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: sectionDefParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func sectionDefParagraphHeaderPayload() -> Data {
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

private func sectionDefChild(_ tag: HwpSectionTag, _ payload: Data) -> HwpRecord {
    HwpRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

private func expectedTruncatedSectionDefFallbackChildren() -> [HwpUnknownRecord] {
    expectedUnknownRecords(from: requiredSectionDefChildren())
        + [expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xBB]))]
}

private func expectedSectionDefUnknownChild(
    _ tag: HwpSectionTag,
    _ payload: Data
) -> HwpUnknownRecord {
    expectedTestUnknownRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

private func expectedUnknownRecords(from records: [HwpRecord]) -> [HwpUnknownRecord] {
    records.map {
        expectedTestUnknownRecord(
            tagId: $0.tagId,
            level: $0.level,
            payload: $0.payload,
            children: $0.children
        )
    }
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

private func pageDefPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    for _ in 0 ..< 9 {
        data.append(littleEndianData(HWPUNIT(0)))
    }
    data.append(littleEndianData(UInt32(0)))
    data.append(rawTrailing)
    return data
}

private func footnoteShapePayload(
    userSymbol: WCHAR = 0,
    decorationHead: WCHAR = 0,
    decorationTail: WCHAR = 0,
    rawTrailing: Data = Data([0, 0])
) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(userSymbol))
    data.append(littleEndianData(decorationHead))
    data.append(littleEndianData(decorationTail))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(COLORREF(0)))
    data.append(rawTrailing)
    return data
}

private func pageBorderFillPayload(rawTrailing: Data = Data()) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    for _ in 0 ..< 5 {
        data.append(littleEndianData(UInt16(0)))
    }
    data.append(rawTrailing)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
