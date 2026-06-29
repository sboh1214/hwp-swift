@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParagraphRequiredRecordStabilityTests: XCTestCase {
    func testMissingRequiredCharShapeThrowsTypedError() {
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: requiredParagraphHeaderPayload()
        )
        paraHeader.children = [
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
        ]

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.recordDoesNotExist(tag) = error else {
                return fail("Expected recordDoesNotExist, got \(error)")
            }
            expect(tag) == HwpSectionTag.paraCharShape.rawValue
        })
    }

    func testMissingParaTextIsAllowedAsOptionalParagraphRecord() throws {
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(charCount: 1),
            children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ]
        )

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        expect(paragraph.paraHeader.charCount) == 1
        expect(paragraph.paraText).to(beNil())
    }

    func testInvalidRangeTagChildThrowsTypedErrorFromParagraphDispatch() {
        let invalidRangeTagPayload = concatenatedData(
            requiredParagraphLittleEndianData(UInt32(1)),
            requiredParagraphLittleEndianData(UInt32(9)),
            requiredParagraphLittleEndianData(UInt32(0xABCD)),
            Data([0xFF])
        )
        let paraHeader = requiredParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(
                tagId: HwpSectionTag.paraRangeTag.rawValue,
                level: 1,
                payload: invalidRangeTagPayload
            ),
        ])

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpParaRangeTag"
            expect(remain) == 1
        })
    }

    func testCharShapeInfoCountMismatchThrowsTypedError() {
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(charShapeInfoCount: 2),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraCharShape.rawValue,
                    level: 1,
                    payload: requiredParagraphCharShapePayload(shapeId: 19)
                ),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ]
        )

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("paragraph char shape count mismatch"))
            expect(reason).to(contain("header declares 2"))
            expect(reason).to(contain("contains 1"))
        })
    }

    func testParaTextCountMismatchThrowsTypedError() {
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(charCount: 2),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraText.rawValue,
                    level: 1,
                    payload: requiredParagraphLittleEndianData(WCHAR(0xAC00))
                ),
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ]
        )

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("paragraph text count mismatch"))
            expect(reason).to(contain("header declares 2"))
            expect(reason).to(contain("contains 1"))
        })
    }

    func testParaTextCountUsesRawTextUnitsForInlineControls() throws {
        let inlinePayload = Data(repeating: 0xAA, count: 14)
        let paraTextPayload = concatenatedData(
            requiredParagraphLittleEndianData(WCHAR(4)),
            inlinePayload
        )
        let rawTextUnitCount = UInt32(paraTextPayload.count / MemoryLayout<WCHAR>.size)
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(charCount: rawTextUnitCount),
            children: [
                HwpRecord(
                    tagId: HwpSectionTag.paraText.rawValue,
                    level: 1,
                    payload: paraTextPayload
                ),
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ]
        )

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        expect(paragraph.paraHeader.charCount) == 8
        expect(paragraph.paraText?.rawPayload) == paraTextPayload
        expect(paragraph.paraText?.charArray.count) == 1
        expect(paragraph.paraText?.charArray.first?.type) == .inline
        expect(paragraph.paraText?.charArray.first?.payload) == inlinePayload
    }

    func testLineSegInfoCountMismatchThrowsTypedError() {
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(alignInfoCount: 2),
            children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(
                    tagId: HwpSectionTag.paraLineSeg.rawValue,
                    level: 1,
                    payload: requiredParagraphLineSegPayload()
                ),
            ]
        )

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("paragraph line segment count mismatch"))
            expect(reason).to(contain("header declares 2"))
            expect(reason).to(contain("contains 1"))
        })
    }

    func testRangeTagInfoCountMismatchThrowsTypedError() {
        let paraHeader = requiredParagraphRecord(
            headerPayload: requiredParagraphHeaderPayload(rangeTagInfoCount: 2),
            children: [
                HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
                HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
                HwpRecord(
                    tagId: HwpSectionTag.paraRangeTag.rawValue,
                    level: 1,
                    payload: requiredParagraphRangeTagPayload()
                ),
            ]
        )

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("paragraph range tag count mismatch"))
            expect(reason).to(contain("header declares 2"))
            expect(reason).to(contain("contains 1"))
        })
    }

    func testInvalidListHeaderChildThrowsTypedErrorFromParagraphDispatch() {
        let paraHeader = requiredParagraphRecord(children: [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 1,
                payload: Data([0xAA])
            ),
        ])

        expect {
            _ = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == MemoryLayout<Int32>.size
            expect(actual) == 1
        })
    }
}

private func requiredParagraphRecord(
    headerPayload: Data = requiredParagraphHeaderPayload(),
    children: [HwpRecord]
) -> HwpRecord {
    let paraHeader = HwpRecord(
        tagId: HwpSectionTag.paraHeader.rawValue,
        level: 0,
        payload: headerPayload
    )
    paraHeader.children = children
    return paraHeader
}

private func requiredParagraphHeaderPayload(
    charCount: UInt32 = 0,
    charShapeInfoCount: UInt16 = 0,
    rangeTagInfoCount: UInt16 = 0,
    alignInfoCount: UInt16 = 0
) -> Data {
    var data = Data()
    data.append(requiredParagraphLittleEndianData(charCount | 0x8000_0000))
    data.append(requiredParagraphLittleEndianData(UInt32(0)))
    data.append(requiredParagraphLittleEndianData(UInt16(0)))
    data.append(requiredParagraphLittleEndianData(UInt8(0)))
    data.append(requiredParagraphLittleEndianData(UInt8(0)))
    data.append(requiredParagraphLittleEndianData(charShapeInfoCount))
    data.append(requiredParagraphLittleEndianData(rangeTagInfoCount))
    data.append(requiredParagraphLittleEndianData(alignInfoCount))
    data.append(requiredParagraphLittleEndianData(UInt32(1)))
    return data
}

private func requiredParagraphCharShapePayload(shapeId: UInt32) -> Data {
    concatenatedData(
        requiredParagraphLittleEndianData(UInt32(0)),
        requiredParagraphLittleEndianData(shapeId)
    )
}

private func requiredParagraphLineSegPayload() -> Data {
    var data = Data()
    data.append(requiredParagraphLittleEndianData(UInt32(0)))
    data.append(requiredParagraphLittleEndianData(Int32(100)))
    data.append(requiredParagraphLittleEndianData(Int32(1000)))
    data.append(requiredParagraphLittleEndianData(Int32(1000)))
    data.append(requiredParagraphLittleEndianData(Int32(850)))
    data.append(requiredParagraphLittleEndianData(Int32(600)))
    data.append(requiredParagraphLittleEndianData(Int32(0)))
    data.append(requiredParagraphLittleEndianData(Int32(42520)))
    data.append(requiredParagraphLittleEndianData(UInt32(393_216)))
    return data
}

private func requiredParagraphRangeTagPayload() -> Data {
    concatenatedData(
        requiredParagraphLittleEndianData(UInt32(1)),
        requiredParagraphLittleEndianData(UInt32(9)),
        requiredParagraphLittleEndianData(UInt32(0xABCD))
    )
}

private func requiredParagraphLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
