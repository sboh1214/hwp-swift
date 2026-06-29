@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ParagraphRawPayloadStabilityTests: XCTestCase {
    func testParaHeaderInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawPayload = paraHeaderData(charCount: 17, paraId: 99, traceChange: 3)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let header = try HwpParaHeader(&reader, HwpVersion(5, 0, 3, 2))

        expect(header.rawPayload) == slicedPayload
        expect(header.charCount) == 17
        expect(header.paraId) == 99
        expect(header.isTraceChange) == 3
        expect(reader.isEOF) == true
    }

    func testParaTextInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let inlinePayload = controlPayload(HwpFieldCtrlId.memo.rawValue)
        let rawPayload = concatenatedData(
            littleEndianData(WCHAR(4)),
            inlinePayload,
            littleEndianData(WCHAR(65))
        )
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let text = try HwpParaText(&reader)

        expect(text.rawPayload) == slicedPayload
        expect(text.charArray.map(\.type)) == [.inline, .char]
        expect(text.charArray.first?.payload) == inlinePayload
        expect(reader.isEOF) == true
    }

    func testParaCharShapeInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawPayload = charShapeData(shapeId: 19)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let charShape = try HwpParaCharShape(&reader)

        expect(charShape.rawPayload) == slicedPayload
        expect(charShape.startingIndex) == [0]
        expect(charShape.shapeId) == [19]
        expect(reader.isEOF) == true
    }

    func testParaLineSegInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawPayload = lineSegData(textStartingIndex: 0, lineLocation: 100, width: 42520)
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let lineSeg = try HwpParaLineSeg(&reader)

        expect(lineSeg.rawPayload) == slicedPayload
        expect(lineSeg.paraLineSegInternalArray.map(\.textStartingIndex)) == [0]
        expect(lineSeg.paraLineSegInternalArray.map(\.lineLocation)) == [100]
        expect(reader.isEOF) == true
    }

    func testParaRangeTagInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let rawPayload = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(UInt32(9)),
            littleEndianData(UInt32(0xABCD))
        )
        let slicedPayload = concatenatedData(Data([0xEF]), rawPayload).dropFirst()
        var reader = DataReader(slicedPayload)

        let rangeTag = try HwpParaRangeTag(&reader)

        expect(rangeTag.rawPayload) == slicedPayload
        expect(rangeTag.start) == 1
        expect(rangeTag.end) == 9
        expect(rangeTag.tag) == 0xABCD
        expect(reader.isEOF) == true
    }
}

final class ParagraphTextControlCodeStabilityTests: XCTestCase {
    func testParaTextConsumesPayloadForEveryInlineControlCode() throws {
        for code in [WCHAR](4 ... 9) + [19, 20] {
            let payload = Data(repeating: UInt8(code), count: 14)
            let data = concatenatedData(
                littleEndianData(code),
                payload,
                littleEndianData(WCHAR(65))
            )

            let paraText = try HwpParaText.load(data)

            expect(paraText.rawPayload) == data
            expect(paraText.charArray.map(\.type)) == [.inline, .char]
            expect(paraText.charArray.map(\.value)) == [code, 65]
            expect(paraText.charArray.first?.payload) == payload
            expect(paraText.charArray.last?.payload).to(beNil())
        }
    }

    func testParaTextConsumesPayloadForEveryExtendedControlCode() throws {
        let extendedCodes = [WCHAR](2 ... 3) + [11, 12] + [WCHAR](14 ... 18) + [21, 22, 23]

        for code in extendedCodes {
            let payload = Data(repeating: UInt8(code), count: 14)
            let data = concatenatedData(
                littleEndianData(code),
                payload,
                littleEndianData(WCHAR(65))
            )

            let paraText = try HwpParaText.load(data)

            expect(paraText.rawPayload) == data
            expect(paraText.charArray.map(\.type)) == [.extended, .char]
            expect(paraText.charArray.map(\.value)) == [code, 65]
            expect(paraText.charArray.first?.payload) == payload
            expect(paraText.charArray.last?.payload).to(beNil())
        }
    }
}

final class ParagraphDataStabilityTests: XCTestCase {
    func testParaTextOddBytePayloadThrowsTypedError() {
        expect {
            _ = try HwpParaText.load(Data([0x00]))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 1
        })
    }

    func testParaTextTruncatedInlinePayloadThrowsTypedError() {
        let data = littleEndianData(WCHAR(4))

        expect {
            _ = try HwpParaText.load(data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 14
            expect(actual) == 0
        })
    }

    func testParaTextPreservesInlineAndExtendedPayloads() throws {
        let inlinePayload = Data(0 ..< 14)
        let extendedPayload = Data(14 ..< 28)
        let data = concatenatedData(
            littleEndianData(WCHAR(4)),
            inlinePayload,
            littleEndianData(WCHAR(2)),
            extendedPayload,
            littleEndianData(WCHAR(65))
        )

        let paraText = try HwpParaText.load(data)
        var sameParaText = paraText
        sameParaText.rawPayload = Data([0xFF])

        expect(paraText.rawPayload) == data
        expect(paraText.charArray.map(\.type)) == [.inline, .extended, .char]
        expect(paraText.charArray.map(\.value)) == [4, 2, 65]
        expect(paraText.charArray[0].payload) == inlinePayload
        expect(paraText.charArray[1].payload) == extendedPayload
        expect(paraText.charArray[2].payload).to(beNil())
        expect(paraText.charArray[2].inlineControl).to(beNil())
        expect(sameParaText) == paraText
    }

    func testParaTextControlCharactersDoNotConsumePayloadBytes() throws {
        let data = concatenatedData(
            littleEndianData(WCHAR(0)),
            littleEndianData(WCHAR(1)),
            littleEndianData(WCHAR(13))
        )

        let paraText = try HwpParaText.load(data)

        expect(paraText.rawPayload) == data
        expect(paraText.charArray.map(\.type)) == [.char, .char, .char]
        expect(paraText.charArray.map(\.value)) == [0, 1, 13]
        expect(paraText.charArray.map(\.payload)).to(allPass(beNil()))
        expect(paraText.charArray.map(\.inlineControl)).to(allPass(beNil()))
    }

    func testParaTextExposesInlineControlIdsFromPayloads() throws {
        let sectionPayload = controlPayload(HwpOtherCtrlId.section.rawValue)
        let columnPayload = controlPayload(HwpOtherCtrlId.column.rawValue)
        let data = concatenatedData(
            littleEndianData(WCHAR(2)),
            sectionPayload,
            littleEndianData(WCHAR(2)),
            columnPayload
        )

        let paraText = try HwpParaText.load(data)
        let controls = paraText.charArray.compactMap(\.inlineControl)

        expect(controls.map(\.rawPayload)) == [sectionPayload, columnPayload]
        expect(controls.compactMap(\.rawControlId)) == [
            HwpOtherCtrlId.section.rawValue,
            HwpOtherCtrlId.column.rawValue,
        ]
        expect(controls.compactMap(\.otherCtrlId)) == [.section, .column]
        expect(controls.map(\.ctrlIdName)) == ["section", "column"]
        expect(controls.map(\.rawTrailing.count)) == [10, 10]
    }

    func testParaTextInlineControlHandlesNonZeroStartIndexPayload() throws {
        let inlinePayload = controlPayload(HwpFieldCtrlId.memo.rawValue)
        let expectedData = concatenatedData(littleEndianData(WCHAR(4)), inlinePayload)
        let data = concatenatedData(Data([0xFF, 0xEE]), expectedData).dropFirst(2)

        let paraText = try HwpParaText.load(data)
        let control = paraText.charArray.first?.inlineControl

        expect(paraText.rawPayload) == expectedData
        expect(paraText.charArray.map(\.type)) == [.inline]
        expect(paraText.charArray.first?.payload) == inlinePayload
        expect(control?.rawPayload) == inlinePayload
        expect(control?.rawControlId) == HwpFieldCtrlId.memo.rawValue
        expect(control?.fieldCtrlId) == .memo
        expect(control?.ctrlIdName) == "memo"
        expect(control?.rawTrailing) == Data(repeating: 0, count: 10)
    }

    func testInlineControlClassifiesKnownUnknownAndShortPayloads() {
        let commonPayload = controlPayload(HwpCommonCtrlId.picture.rawValue)
        let fieldPayload = controlPayload(HwpFieldCtrlId.hyperLink.rawValue)
        let unknownPayload = concatenatedData(
            littleEndianData(UInt32(0x1234_5678)),
            Data([0xCA, 0xFE])
        )
        let shortPayload = Data([0xAA, 0xBB, 0xCC])

        let common = HwpInlineControl(rawPayload: commonPayload)
        let field = HwpInlineControl(rawPayload: fieldPayload)
        let unknown = HwpInlineControl(rawPayload: unknownPayload)
        let short = HwpInlineControl(rawPayload: shortPayload)

        expect(common.rawPayload) == commonPayload
        expect(common.rawControlId) == HwpCommonCtrlId.picture.rawValue
        expect(common.commonCtrlId) == .picture
        expect(common.ctrlIdName) == "picture"
        expect(common.rawTrailing.count) == 10

        expect(field.rawPayload) == fieldPayload
        expect(field.rawControlId) == HwpFieldCtrlId.hyperLink.rawValue
        expect(field.fieldCtrlId) == .hyperLink
        expect(field.ctrlIdName) == "hyperLink"
        expect(field.rawTrailing.count) == 10

        expect(unknown.rawPayload) == unknownPayload
        expect(unknown.rawControlId) == 0x1234_5678
        expect(unknown.ctrlIdName) == "unknown"
        expect(unknown.rawTrailing) == Data([0xCA, 0xFE])

        expect(short.rawPayload) == shortPayload
        expect(short.rawControlId).to(beNil())
        expect(short.ctrlIdName) == "unknown"
        expect(short.rawTrailing).to(beEmpty())
    }

    func testParagraphShortCtrlHeaderPayloadIsPreservedAsUnknownControl() throws {
        let ctrlPayload = Data([0xAA, 0xBB, 0xCC])
        let paragraph = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paraHeaderData(charCount: 0, paraId: 0, traceChange: nil)
        )
        paragraph.children = [
            HwpRecord(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: charShapeData(shapeId: 0)
            ),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: ctrlPayload
            ),
        ]

        let loaded = try HwpParagraph.load(paragraph, HwpVersion(5, 0, 3, 1))

        guard case let .unknown(header) = loaded.ctrlHeaderArray?.first else {
            return fail("Expected truncated control header to be preserved as unknown")
        }
        expect(header.ctrlId) == 0
        expect(header.rawPayload) == ctrlPayload
        expect(header.unknownChildren).to(beEmpty())
    }

    func testHwpCharPayloadDoesNotAffectEquality() {
        let first = HwpChar(type: .inline, value: 4, payload: Data([1, 2, 3]))
        let second = HwpChar(type: .inline, value: 4, payload: Data([9, 8, 7]))

        expect(first) == second
    }

    func testParaHeaderPreservesRawPayloadWithoutChangingEquality() throws {
        let data = paraHeaderData(charCount: 17, paraId: 99, traceChange: 3)

        let paraHeader = try HwpParaHeader.load(data, HwpVersion(5, 0, 3, 2))
        var sameParaHeader = paraHeader
        sameParaHeader.rawPayload = Data([0xFF])
        sameParaHeader.paraId = 100

        expect(paraHeader.rawPayload) == data
        expect(paraHeader.isLastInList) == true
        expect(paraHeader.charCount) == 17
        expect(paraHeader.paraId) == 99
        expect(paraHeader.isTraceChange) == 3
        expect(sameParaHeader) == paraHeader
    }

    func testParaHeaderOldVersionPreservesRawPayloadWithoutTraceChange() throws {
        let data = paraHeaderData(charCount: 4, paraId: 7, traceChange: nil)

        let paraHeader = try HwpParaHeader.load(data, HwpVersion(5, 0, 3, 1))

        expect(paraHeader.rawPayload) == data
        expect(paraHeader.charCount) == 4
        expect(paraHeader.paraId) == 7
        expect(paraHeader.isTraceChange).to(beNil())
    }

    func testParaHeaderRejectsTrailingBytesWithTypedError() {
        let data = concatenatedData(
            paraHeaderData(charCount: 4, paraId: 7, traceChange: nil),
            Data([0xFF])
        )

        expect {
            _ = try HwpParaHeader.load(data, HwpVersion(5, 0, 3, 1))
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpParaHeader"
            expect(remain) == 1
        })
    }

    func testParaCharShapePartialPairThrowsTypedError() {
        let data = littleEndianData(UInt32(0))

        expect {
            _ = try HwpParaCharShape.load(data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 0
        })
    }

    func testParaCharShapeRejectsNonZeroFirstStartingIndexWithTypedError() {
        let data = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(UInt32(19))
        )

        expect {
            _ = try HwpParaCharShape.load(data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("first starting index must be 0"))
            expect(reason).to(contain("got 1"))
        })
    }

    func testParaCharShapePreservesRawPayloadWithoutChangingEquality() throws {
        let data = concatenatedData(
            littleEndianData(UInt32(0)),
            littleEndianData(UInt32(19)),
            littleEndianData(UInt32(8)),
            littleEndianData(UInt32(20))
        )

        let paraCharShape = try HwpParaCharShape.load(data)
        var sameParaCharShape = paraCharShape
        sameParaCharShape.rawPayload = Data([0xFF])

        expect(paraCharShape.rawPayload) == data
        expect(paraCharShape.startingIndex) == [0, 8]
        expect(paraCharShape.shapeId) == [19, 20]
        expect(sameParaCharShape) == paraCharShape
    }

    func testParaLineSegPartialRecordThrowsTypedError() {
        let data = littleEndianData(UInt32(0))

        expect {
            _ = try HwpParaLineSeg.load(data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 0
        })
    }

    func testParaLineSegPreservesRawPayloadWithoutChangingEquality() throws {
        let data = concatenatedData(
            lineSegData(textStartingIndex: 0, lineLocation: 100, width: 42520),
            lineSegData(textStartingIndex: 12, lineLocation: 1200, width: 30000)
        )

        let paraLineSeg = try HwpParaLineSeg.load(data)
        var sameParaLineSeg = paraLineSeg
        sameParaLineSeg.rawPayload = Data([0xFF])

        expect(paraLineSeg.rawPayload) == data
        expect(paraLineSeg.paraLineSegInternalArray.map(\.textStartingIndex)) == [0, 12]
        expect(paraLineSeg.paraLineSegInternalArray.map(\.lineLocation)) == [100, 1200]
        expect(paraLineSeg.paraLineSegInternalArray.map(\.width)) == [42520, 30000]
        expect(sameParaLineSeg) == paraLineSeg
    }

    func testParaRangeTagPartialRecordThrowsTypedError() {
        let data = concatenatedData(littleEndianData(UInt32(1)), littleEndianData(UInt32(9)))

        expect {
            _ = try HwpParaRangeTag.load(data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 0
        })
    }

    func testParaRangeTagRejectsTrailingBytesWithTypedError() {
        let data = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(UInt32(9)),
            littleEndianData(UInt32(0xABCD)),
            Data([0xFF])
        )

        expect {
            _ = try HwpParaRangeTag.load(data)
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpParaRangeTag"
            expect(remain) == 1
        })
    }

    func testParaRangeTagPreservesRawPayloadWithoutChangingEquality() throws {
        let data = concatenatedData(
            littleEndianData(UInt32(1)),
            littleEndianData(UInt32(9)),
            littleEndianData(UInt32(0xABCD))
        )

        let rangeTag = try HwpParaRangeTag.load(data)
        var sameRangeTag = rangeTag
        sameRangeTag.rawPayload = Data([0xFF])

        expect(rangeTag.rawPayload) == data
        expect(rangeTag.start) == 1
        expect(rangeTag.end) == 9
        expect(rangeTag.tag) == 0xABCD
        expect(sameRangeTag) == rangeTag
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func controlPayload(_ ctrlId: UInt32) -> Data {
    concatenatedData(littleEndianData(ctrlId), Data(repeating: 0, count: 10))
}

private func charShapeData(shapeId: UInt32) -> Data {
    concatenatedData(littleEndianData(UInt32(0)), littleEndianData(shapeId))
}

private func paraHeaderData(charCount: UInt32, paraId: UInt32, traceChange: UInt16?) -> Data {
    var data = Data()
    data.append(littleEndianData(charCount | 0x8000_0000))
    data.append(littleEndianData(UInt32(4)))
    data.append(littleEndianData(UInt16(0)))
    data.append(contentsOf: [0])
    data.append(contentsOf: [3])
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(UInt16(0)))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(paraId))
    if let traceChange {
        data.append(littleEndianData(traceChange))
    }
    return data
}

private func lineSegData(textStartingIndex: UInt32, lineLocation: Int32, width: Int32) -> Data {
    var data = Data()
    data.append(littleEndianData(textStartingIndex))
    data.append(littleEndianData(lineLocation))
    data.append(littleEndianData(Int32(1000)))
    data.append(littleEndianData(Int32(1000)))
    data.append(littleEndianData(Int32(850)))
    data.append(littleEndianData(Int32(600)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(width))
    data.append(littleEndianData(UInt32(393_216)))
    return data
}
