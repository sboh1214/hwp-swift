@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParagraphPreservationTests: XCTestCase {
    func testParagraphUsesFirstSingletonRecordsAndPreservesDuplicatesAsUnknown() throws {
        let fixture = DuplicateParagraphSingletonFixture()

        let paragraph = try HwpParagraph.load(fixture.record, HwpVersion(5, 0, 1, 1))

        expect(paragraph.paraText?.rawPayload) == fixture.firstTextPayload
        expect(paragraph.paraText?.charArray.map(\.value)) == [0x0041]
        expect(paragraph.paraCharShape.rawPayload) == fixture.firstCharShapePayload
        expect(paragraph.paraCharShape.shapeId) == [19]
        expect(paragraph.paraLineSeg.rawPayload) == fixture.firstLineSegPayload
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.map(\.lineLocation)) == [100]
        expect(paragraph.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: fixture.duplicateTextPayload
            ),
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: fixture.duplicateCharShapePayload
            ),
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: fixture.duplicateLineSegPayload
            ),
        ]
    }

    func testParagraphPreservesUnknownChildren() throws {
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphHeaderPayload()
        )
        paraHeader.children = paragraphChildrenWithDuplicateSingletons()

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        expect(paragraph.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: Data([0x10]),
                children: [
                    expectedTestRecord(tagId: 0x2FB, level: 2, payload: Data([0x11])),
                ]
            ),
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: Data([0x20])
            ),
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: Data([0x30])
            ),
            expectedTestUnknownRecord(
                tagId: 0x2FD,
                level: 1,
                payload: Data([0xCA, 0xFE]),
                children: [
                    expectedTestRecord(tagId: 0x2FC, level: 2, payload: Data([0xAA])),
                ]
            ),
        ]
    }
}

private struct DuplicateParagraphSingletonFixture {
    let firstTextPayload = littleEndianData(WCHAR(0x0041))
    let duplicateTextPayload = littleEndianData(WCHAR(0x0042))
    let firstCharShapePayload = paragraphCharShapePayload(shapeId: 19)
    let duplicateCharShapePayload = paragraphCharShapePayload(shapeId: 20)
    let firstLineSegPayload = paragraphLineSegPayload(lineLocation: 100)
    let duplicateLineSegPayload = paragraphLineSegPayload(lineLocation: 200)

    var record: HwpRecord {
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphHeaderPayload(
                charCount: 1,
                charShapeInfoCount: 1,
                alignInfoCount: 1
            )
        )
        paraHeader.children = [
            HwpRecord(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: firstTextPayload
            ),
            HwpRecord(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: duplicateTextPayload
            ),
            HwpRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: firstCharShapePayload
            ),
            HwpRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: duplicateCharShapePayload
            ),
            HwpRecord(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: firstLineSegPayload
            ),
            HwpRecord(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: duplicateLineSegPayload
            ),
        ]
        return paraHeader
    }
}

private func paragraphChildrenWithDuplicateSingletons() -> [HwpRecord] {
    let duplicateParaText = HwpRecord(
        tagId: HwpSectionTag.paraText.rawValue,
        level: 1,
        payload: Data([0x10])
    )
    duplicateParaText.children = [
        HwpRecord(tagId: 0x2FB, level: 2, payload: Data([0x11])),
    ]
    let duplicateCharShape = HwpRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: Data([0x20])
    )
    let duplicateLineSeg = HwpRecord(
        tagId: HwpSectionTag.paraLineSeg.rawValue,
        level: 1,
        payload: Data([0x30])
    )
    let unknownChild = HwpRecord(tagId: 0x2FD, level: 1, payload: Data([0xCA, 0xFE]))
    unknownChild.children = [
        HwpRecord(tagId: 0x2FC, level: 2, payload: Data([0xAA])),
    ]
    return [
        HwpRecord(tagId: HwpSectionTag.paraText.rawValue, level: 1, payload: Data()),
        duplicateParaText,
        HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
        duplicateCharShape,
        HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
        duplicateLineSeg,
        unknownChild,
    ]
}

private func paragraphHeaderPayload(
    charCount: UInt32 = 0,
    charShapeInfoCount: UInt16 = 0,
    rangeTagInfoCount: UInt16 = 0,
    alignInfoCount: UInt16 = 0
) -> Data {
    var data = Data()
    data.append(littleEndianData(charCount | 0x8000_0000))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(charShapeInfoCount))
    data.append(littleEndianData(rangeTagInfoCount))
    data.append(littleEndianData(alignInfoCount))
    data.append(littleEndianData(UInt32(1)))
    return data
}

private func paragraphCharShapePayload(shapeId: UInt32) -> Data {
    littleEndianData(UInt32(0)) + littleEndianData(shapeId)
}

private func paragraphLineSegPayload(lineLocation: Int32) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(lineLocation))
    data.append(littleEndianData(Int32(1000)))
    data.append(littleEndianData(Int32(1000)))
    data.append(littleEndianData(Int32(850)))
    data.append(littleEndianData(Int32(600)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(Int32(42520)))
    data.append(littleEndianData(UInt32(393_216)))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
