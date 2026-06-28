@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileParagraphDuplicateAssemblyTests: XCTestCase {
    func testParagraphDuplicateTextAndLineSegSingletonsSurviveAsUnknownChildrenThroughCodable()
        throws
    {
        let base = try openHwp(#file, "plain-text-minimal")
        let baseSection = try XCTUnwrap(base.sectionArray.first)
        let baseParagraph = try XCTUnwrap(baseSection.paragraph.last)
        let duplicate = DuplicateTextAndLineSegRecords()
        let sectionData = baseSection.rawPayload
            + paragraphRecordData(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: duplicate.textPayload
            )
            + paragraphRecordData(tagId: 0x2FA, level: 2, payload: duplicate.textChildPayload)
            + paragraphRecordData(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: duplicate.lineSegPayload
            )
            + paragraphRecordData(tagId: 0x2F9, level: 2, payload: duplicate.lineSegChildPayload)

        let hwp = try HwpFile(
            fileHeader: base.fileHeader,
            docInfo: base.docInfo,
            sectionDataArray: [sectionData]
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        assertDuplicateTextAndLineSegRecordsPreserved(
            in: hwp,
            baseParagraph: baseParagraph,
            sectionData: sectionData,
            duplicate: duplicate
        )
        assertDuplicateTextAndLineSegRecordsPreserved(
            in: decoded,
            baseParagraph: baseParagraph,
            sectionData: sectionData,
            duplicate: duplicate
        )
    }

    func testParagraphDuplicateSingletonSurvivesAsUnknownChildThroughCodable() throws {
        let base = try openHwp(#file, "plain-text-minimal")
        let baseSection = try XCTUnwrap(base.sectionArray.first)
        let baseParagraph = try XCTUnwrap(baseSection.paragraph.last)
        let duplicatePayload = Data([0xC5, 0xC6, 0xC7, 0xC8])
        let duplicateChildPayload = Data([0xD1, 0xD2])
        let sectionData = baseSection.rawPayload
            + paragraphRecordData(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: duplicatePayload
            )
            + paragraphRecordData(tagId: 0x2FA, level: 2, payload: duplicateChildPayload)

        let hwp = try HwpFile(
            fileHeader: base.fileHeader,
            docInfo: base.docInfo,
            sectionDataArray: [sectionData]
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        assertDuplicateParagraphRecordPreserved(
            in: hwp,
            baseParagraph: baseParagraph,
            sectionData: sectionData,
            duplicatePayload: duplicatePayload,
            duplicateChildPayload: duplicateChildPayload
        )
        assertDuplicateParagraphRecordPreserved(
            in: decoded,
            baseParagraph: baseParagraph,
            sectionData: sectionData,
            duplicatePayload: duplicatePayload,
            duplicateChildPayload: duplicateChildPayload
        )
    }
}

private struct DuplicateTextAndLineSegRecords {
    let textPayload = Data([0x41, 0x00])
    let textChildPayload = Data([0xA1])
    let lineSegPayload = Data([0xB1, 0xB2, 0xB3])
    let lineSegChildPayload = Data([0xC1, 0xC2])
}

private func assertDuplicateTextAndLineSegRecordsPreserved(
    in hwp: HwpFile,
    baseParagraph: HwpParagraph,
    sectionData: Data,
    duplicate: DuplicateTextAndLineSegRecords
) {
    expect(hwp.sectionArray.map(\.rawPayload)) == [sectionData]
    let paragraph = hwp.sectionArray.first?.paragraph.last
    let unknownChildren = paragraph?.unknownChildren ?? []
    expect(paragraph?.paraText?.rawPayload) == baseParagraph.paraText?.rawPayload
    expect(paragraph?.paraLineSeg.rawPayload) == baseParagraph.paraLineSeg.rawPayload
    expect(Array(unknownChildren.suffix(2))) == [
        expectedTestUnknownRecord(
            tagId: HwpSectionTag.paraText.rawValue,
            level: 1,
            payload: duplicate.textPayload,
            children: [
                expectedTestRecord(tagId: 0x2FA, level: 2, payload: duplicate.textChildPayload),
            ]
        ),
        expectedTestUnknownRecord(
            tagId: HwpSectionTag.paraLineSeg.rawValue,
            level: 1,
            payload: duplicate.lineSegPayload,
            children: [
                expectedTestRecord(
                    tagId: 0x2F9,
                    level: 2,
                    payload: duplicate.lineSegChildPayload
                ),
            ]
        ),
    ]
}

private func assertDuplicateParagraphRecordPreserved(
    in hwp: HwpFile,
    baseParagraph: HwpParagraph,
    sectionData: Data,
    duplicatePayload: Data,
    duplicateChildPayload: Data
) {
    expect(hwp.sectionArray.map(\.rawPayload)) == [sectionData]
    let paragraph = hwp.sectionArray.first?.paragraph.last
    expect(paragraph?.paraCharShape.rawPayload) == baseParagraph.paraCharShape.rawPayload
    expect(paragraph?.unknownChildren.last) == expectedTestUnknownRecord(
        tagId: HwpSectionTag.paraCharShape.rawValue,
        level: 1,
        payload: duplicatePayload,
        children: [
            expectedTestRecord(tagId: 0x2FA, level: 2, payload: duplicateChildPayload),
        ]
    )
}

private func paragraphRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = littleEndianParagraphRecordHeader(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func littleEndianParagraphRecordHeader(_ value: UInt32) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
