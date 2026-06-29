@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class PageNumberPositionFallbackCodableTests: XCTestCase {
    func testTruncatedPageNumberPositionFallbackPreservesNestedChildrenThroughParagraphCodable()
        throws
    {
        let rawPayload = pageNumberPositionFallbackTruncatedPayload()
        let unknownChild = pageNumberPositionFallbackNestedChildRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            nestedTagId: 0x2FD,
            nestedPayload: Data([0xCC])
        )
        let controlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )
        controlRecord.children = [unknownChild]

        expect {
            _ = try HwpPageNumberPosition.load(controlRecord)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })

        let paragraph = try HwpParagraph.load(
            pageNumberPositionFallbackParagraphRecord(children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                controlRecord,
            ]),
            HwpVersion(5, 0, 1, 1)
        )
        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(paragraph)
        )

        assertPageNumberPositionFallbackControl(
            paragraph.ctrlHeaderArray?.first,
            rawPayload: rawPayload
        )
        assertPageNumberPositionFallbackControl(
            decoded.ctrlHeaderArray?.first,
            rawPayload: rawPayload
        )
    }
}

private func assertPageNumberPositionFallbackControl(
    _ control: HwpCtrlId?,
    rawPayload: Data
) {
    guard case let .other(other) = control else {
        return fail("Expected truncated page number position to be preserved as other")
    }

    expect(other.ctrlId) == .pageNumberPosition
    expect(other.rawPayload) == rawPayload
    expect(other.rawTrailing) == Data(rawPayload.dropFirst(MemoryLayout<UInt32>.size))
    expect(other.ctrlDataRecords).to(beEmpty())
    expect(other.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x2FE,
            level: 2,
            payload: Data([0xBB]),
            children: [
                expectedTestRecord(tagId: 0x2FD, level: 3, payload: Data([0xCC])),
            ]
        ),
    ]
}

private func pageNumberPositionFallbackNestedChildRecord(
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

private func pageNumberPositionFallbackParagraphRecord(children: [HwpRecord]) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: pageNumberPositionFallbackParagraphHeaderPayload()
    )
    record.children = children
    return record
}

private func pageNumberPositionFallbackParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(pageNumberPositionFallbackLittleEndianData(UInt32(0x8000_0000)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt32(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt16(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt8(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt8(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt16(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt16(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt16(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt32(1)))
    return data
}

private func pageNumberPositionFallbackTruncatedPayload() -> Data {
    var data = Data()
    let ctrlId = HwpOtherCtrlId.pageNumberPosition.rawValue
    data.append(pageNumberPositionFallbackLittleEndianData(ctrlId))
    data.append(pageNumberPositionFallbackLittleEndianData(UInt32(0x0102_0304)))
    data.append(pageNumberPositionFallbackLittleEndianData(WCHAR(0)))
    data.append(pageNumberPositionFallbackLittleEndianData(WCHAR(45)))
    data.append(pageNumberPositionFallbackLittleEndianData(WCHAR(45)))
    data.append(0xAA)
    return data
}

private func pageNumberPositionFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
