@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ControlHeaderStabilityTests: XCTestCase {
    func testControlHeaderLoaderPreservesValidPayloadAndUnknownChildren() throws {
        let payload = concatenatedData(
            controlHeaderLittleEndianData(HwpOtherCtrlId.bookmark.rawValue),
            Data([0xAA, 0xBB])
        )
        let childPayload = Data([0x01, 0x02, 0x03])
        let grandchildPayload = Data([0x04, 0x05])
        let child = HwpRecord(tagId: 0x2FF, level: 2, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x2FE, level: 3, payload: grandchildPayload),
        ]
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: payload
        )
        record.children = [child]

        let header = try HwpCtrlHeader.load(record)

        expect(header.ctrlId) == HwpOtherCtrlId.bookmark.rawValue
        expect(header.rawPayload) == payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(
                tagId: 0x2FF,
                level: 2,
                payload: childPayload,
                children: [
                    expectedTestRecord(tagId: 0x2FE, level: 3, payload: grandchildPayload),
                ]
            ),
        ]
    }

    func testControlHeaderLoaderHandlesPayloadWithNonZeroDataStartIndex() throws {
        let payload = controlHeaderLittleEndianData(HwpOtherCtrlId.pageHide.rawValue)
        let slicedPayload = concatenatedData(Data([0xEE, 0xFF]), payload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: slicedPayload
        )

        let header = try HwpCtrlHeader.load(record)

        expect(header.ctrlId) == HwpOtherCtrlId.pageHide.rawValue
        expect(header.rawPayload) == slicedPayload
    }

    func testControlHeaderLoaderPreservesAllShortPayloadsAsUnknownControlIds() throws {
        for length in 0 ..< MemoryLayout<UInt32>.size {
            let payload = Data(repeating: 0xAB, count: length)
            let childPayload = Data([UInt8(length)])
            let record = HwpRecord(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            )
            record.children = [
                HwpRecord(tagId: 0x2FF, level: 2, payload: childPayload),
            ]

            let header = try HwpCtrlHeader.load(record)

            expect(header.ctrlId) == 0
            expect(header.rawPayload) == payload
            expect(header.unknownChildren) == [
                expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: childPayload),
            ]
        }
    }

    func testControlHeaderInitializerConsumesAndPreservesRawTrailingBytesAndChildren() throws {
        let payload = concatenatedData(
            controlHeaderLittleEndianData(HwpOtherCtrlId.comment.rawValue),
            Data([0xAA, 0xBB])
        )
        let childPayload = Data([0xCC])
        let child = HwpRecord(tagId: 0x2FF, level: 2, payload: childPayload)
        var reader = DataReader(payload)

        let header = try HwpCtrlHeader(&reader, [child])

        expect(header.ctrlId) == HwpOtherCtrlId.comment.rawValue
        expect(header.rawPayload) == payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: childPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testControlHeaderInitializerPreservesShortPayloadsAndConsumesToEnd() throws {
        for length in 0 ..< MemoryLayout<UInt32>.size {
            let payload = Data(repeating: 0xAB, count: length)
            let childPayload = Data([UInt8(length)])
            let child = HwpRecord(tagId: 0x2FE, level: 2, payload: childPayload)
            var reader = DataReader(payload)

            let header = try HwpCtrlHeader(&reader, [child])

            expect(header.ctrlId) == 0
            expect(header.rawPayload) == payload
            expect(header.unknownChildren) == [
                expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: childPayload),
            ]
            expect(reader.isEOF) == true
        }
    }

    func testControlHeaderLoaderRejectsMismatchedRecordTagWithTypedError() {
        let record = HwpRecord(
            tagId: HwpSectionTag.paraText.rawValue,
            level: 1,
            payload: controlHeaderLittleEndianData(HwpOtherCtrlId.bookmark.rawValue)
        )

        expect {
            _ = try HwpCtrlHeader.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("\(HwpSectionTag.ctrlHeader.rawValue)"))
            expect(reason).to(contain("\(HwpSectionTag.paraText.rawValue)"))
        })
    }

    func testTruncatedControlHeaderIsPreservedAsUnknownControl() throws {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let childPayload = Data([0x01, 0x02, 0x03])
        let ctrlRecord = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: payload
        )
        ctrlRecord.children.append(
            HwpRecord(tagId: 0x2FF, level: 2, payload: childPayload)
        )
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: controlHeaderParagraphHeaderPayload()
        )
        paraHeader.children = [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ctrlRecord,
        ]

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        guard case let .unknown(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated control header to be preserved as unknown")
        }
        expect(header.ctrlId) == 0
        expect(header.rawPayload) == payload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FF, level: 2, payload: childPayload),
        ]
        expect(paragraph.unknownChildren).to(beEmpty())
    }
}

private func controlHeaderParagraphHeaderPayload() -> Data {
    var data = Data()
    data.append(controlHeaderLittleEndianData(UInt32(0x8000_0000)))
    data.append(controlHeaderLittleEndianData(UInt32(0)))
    data.append(controlHeaderLittleEndianData(UInt16(0)))
    data.append(controlHeaderLittleEndianData(UInt8(0)))
    data.append(controlHeaderLittleEndianData(UInt8(0)))
    data.append(controlHeaderLittleEndianData(UInt16(0)))
    data.append(controlHeaderLittleEndianData(UInt16(0)))
    data.append(controlHeaderLittleEndianData(UInt16(0)))
    data.append(controlHeaderLittleEndianData(UInt32(1)))
    return data
}

private func controlHeaderLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
