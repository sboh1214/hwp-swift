@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParagraphCodableTests: XCTestCase {
    func testParagraphUnknownChildrenAndControlsSurviveCodableRoundTrip() throws {
        let unknownChildPayload = Data([0x11, 0x12])
        let nestedUnknownPayload = Data([0x21])
        let ctrlId: UInt32 = 0x1234_5678
        let ctrlTrailing = Data([0xCA, 0xFE])
        let ctrlPayload = concatenatedData(paragraphCodableLittleEndianData(ctrlId), ctrlTrailing)
        let ctrlChildPayload = Data([0xDD])

        let record = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphCodableParaHeaderPayload()
        )
        let unknownChild = HwpRecord(tagId: 0x2FC, level: 1, payload: unknownChildPayload)
        unknownChild.children = [
            HwpRecord(tagId: 0x2FB, level: 2, payload: nestedUnknownPayload),
        ]
        let ctrlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        ctrlRecord.children = [
            HwpRecord(tagId: 0x2FF, level: 2, payload: ctrlChildPayload),
        ]
        record.children = [
            HwpRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: paragraphCodableParaCharShapePayload()
            ),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            unknownChild,
            ctrlRecord,
        ]

        let paragraph = try HwpParagraph.load(record, HwpVersion(5, 0, 3, 2))
        let decoded = try paragraphCodableRoundTrip(paragraph)

        expect(decoded.paraHeader.rawPayload) == record.payload
        expect(decoded.paraCharShape.rawPayload) == paragraphCodableParaCharShapePayload()
        expect(decoded.unknownChildren) == paragraphCodableUnknownChildren(
            payload: unknownChildPayload,
            nestedPayload: nestedUnknownPayload
        )

        guard case let .unknown(header) = decoded.ctrlHeaderArray?.first else {
            return fail("Expected unknown control after Codable round-trip")
        }
        expect(header.ctrlId) == ctrlId
        expect(header.rawPayload) == ctrlPayload
        expect(header.unknownChildren) == paragraphCodableControlUnknownChildren(
            payload: ctrlChildPayload
        )
    }

    func testParagraphTextAndInlineControlSurviveCodableRoundTrip() throws {
        let inlineControlTrailing = Data(0x01 ... 0x0A)
        let inlineControlPayload = concatenatedData(
            paragraphCodableLittleEndianData(HwpOtherCtrlId.section.rawValue),
            inlineControlTrailing
        )
        let paraTextPayload = concatenatedData(
            paragraphCodableLittleEndianData(WCHAR(4)),
            inlineControlPayload,
            paragraphCodableLittleEndianData(WCHAR(65))
        )
        let charCount = UInt32(paraTextPayload.count / MemoryLayout<WCHAR>.size)

        let paragraph = try HwpParagraph.load(
            paragraphCodableRecord(
                headerPayload: paragraphCodableParaHeaderPayload(charCount: charCount),
                children: [
                    HwpRecord(
                        tagId: HwpSectionTag.paraText.rawValue,
                        level: 1,
                        payload: paraTextPayload
                    ),
                    HwpRecord(
                        tagId: HwpSectionTag.paraCharShape.rawValue,
                        level: 1,
                        payload: paragraphCodableParaCharShapePayload()
                    ),
                    HwpRecord(
                        tagId: HwpSectionTag.paraLineSeg.rawValue,
                        level: 1,
                        payload: Data()
                    ),
                ]
            ),
            HwpVersion(5, 0, 3, 2)
        )
        let decoded = try paragraphCodableRoundTrip(paragraph)

        expect(decoded.paraText?.rawPayload) == paraTextPayload
        expect(decoded.paraText?.charArray.map(\.type)) == [.inline, .char]
        expect(decoded.paraText?.charArray.first?.payload) == inlineControlPayload
        expect(decoded.paraText?.charArray.first?.inlineControl?.rawControlId) ==
            HwpOtherCtrlId.section.rawValue
        expect(decoded.paraText?.charArray.first?.inlineControl?.rawTrailing) ==
            inlineControlTrailing
    }

    func testDuplicateSingletonChildrenSurviveCodableRoundTripAsUnknownChildren() throws {
        let fixture = ParagraphDuplicateFixture()
        let paragraph = try HwpParagraph.load(
            fixture.record,
            HwpVersion(5, 0, 3, 2)
        )
        let decoded = try paragraphCodableRoundTrip(paragraph)

        expect(decoded.paraText?.rawPayload) == fixture.firstTextPayload
        expect(decoded.paraCharShape.rawPayload) == paragraphCodableParaCharShapePayload()
        expect(decoded.paraLineSeg.rawPayload) == Data()
        expect(decoded.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: fixture.duplicateTextPayload,
                children: [
                    expectedTestRecord(
                        tagId: 0x2FA,
                        level: 2,
                        payload: fixture.duplicateTextChildPayload
                    ),
                ]
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
}

private func paragraphCodableUnknownChildren(
    payload: Data,
    nestedPayload: Data
) -> [HwpUnknownRecord] {
    [
        expectedTestUnknownRecord(
            tagId: 0x2FC,
            level: 1,
            payload: payload,
            children: [
                expectedTestRecord(tagId: 0x2FB, level: 2, payload: nestedPayload),
            ]
        ),
    ]
}

private func paragraphCodableControlUnknownChildren(payload: Data) -> [HwpUnknownRecord] {
    [
        expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: payload),
    ]
}

private func paragraphCodableRoundTrip(_ paragraph: HwpParagraph) throws -> HwpParagraph {
    try JSONDecoder().decode(HwpParagraph.self, from: JSONEncoder().encode(paragraph))
}

private struct ParagraphDuplicateFixture {
    let firstTextPayload = paragraphCodableLittleEndianData(WCHAR(0x0041))
    let duplicateTextPayload = paragraphCodableLittleEndianData(WCHAR(0x0042))
    let duplicateTextChildPayload = Data([0xA1])
    let duplicateCharShapePayload = concatenatedData(
        paragraphCodableLittleEndianData(UInt32(0)),
        paragraphCodableLittleEndianData(UInt32(1))
    )
    let duplicateLineSegPayload = Data([0xB1, 0xB2])

    var record: HwpRecord {
        paragraphCodableRecord(
            headerPayload: paragraphCodableParaHeaderPayload(charCount: 1),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraText.rawValue,
                    level: 1,
                    payload: firstTextPayload
                ),
                duplicateText,
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: paragraphCodableParaCharShapePayload()
                ),
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: duplicateCharShapePayload
                ),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: duplicateLineSegPayload
                ),
            ]
        )
    }

    private var duplicateText: HwpRecord {
        let record = HwpRecord(
            tagId: HwpSectionTag.paraText.rawValue,
            level: 1,
            payload: duplicateTextPayload
        )
        record.children = [
            HwpRecord(tagId: 0x2FA, level: 2, payload: duplicateTextChildPayload),
        ]
        return record
    }
}

private func paragraphCodableRecord(
    headerPayload: Data = paragraphCodableParaHeaderPayload(),
    children: [HwpRecord]
) -> HwpRecord {
    let record = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: headerPayload
    )
    record.children = children
    return record
}

private func paragraphCodableParaHeaderPayload(charCount: UInt32 = 0) -> Data {
    var data = Data()
    data.append(paragraphCodableLittleEndianData(charCount | 0x8000_0000))
    data.append(paragraphCodableLittleEndianData(UInt32(0)))
    data.append(paragraphCodableLittleEndianData(UInt16(0)))
    data.append(contentsOf: [0, 0])
    data.append(paragraphCodableLittleEndianData(UInt16(1)))
    data.append(paragraphCodableLittleEndianData(UInt16(0)))
    data.append(paragraphCodableLittleEndianData(UInt16(0)))
    data.append(paragraphCodableLittleEndianData(UInt32(0)))
    data.append(paragraphCodableLittleEndianData(UInt16(0)))
    return data
}

private func paragraphCodableParaCharShapePayload() -> Data {
    concatenatedData(
        paragraphCodableLittleEndianData(UInt32(0)),
        paragraphCodableLittleEndianData(UInt32(0))
    )
}

private func paragraphCodableLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
