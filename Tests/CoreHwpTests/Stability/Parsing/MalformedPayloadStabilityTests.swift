@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class MalformedPayloadStabilityTests: XCTestCase {
    func testInvalidPreviewTextEncodingThrowsTypedError() {
        let invalidUTF16LE = Data([0x00, 0xD8])

        expectInvalidPreviewTextData(invalidUTF16LE)
    }

    func testOddLengthPreviewTextEncodingThrowsTypedError() {
        let truncatedUTF16LECodeUnit = Data([0x41])

        expectInvalidPreviewTextData(truncatedUTF16LECodeUnit)
    }

    func testTruncatedControlHeaderIsPreservedAsUnknownControl() throws {
        let ctrlPayload = Data([0x01, 0x02, 0x03])
        let childPayload = Data([0xAA, 0xBB])
        let paraHeader = HwpRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: paragraphHeaderPayload()
        )
        let ctrlHeader = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        )
        ctrlHeader.children = [
            HwpRecord(tagId: 0x2FE, level: 2, payload: childPayload),
        ]
        paraHeader.children = [
            HwpRecord(tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()),
            HwpRecord(tagId: HwpSectionTag.paraLineSeg.rawValue, level: 1, payload: Data()),
            ctrlHeader,
        ]

        let paragraph = try HwpParagraph.load(paraHeader, HwpVersion(5, 0, 1, 1))

        guard case let .unknown(header) = paragraph.ctrlHeaderArray?.first else {
            return fail("Expected truncated control header to be preserved as unknown")
        }
        expect(header.ctrlId) == 0
        expect(header.rawPayload) == ctrlPayload
        expect(header.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: childPayload),
        ]
    }

    private func expectInvalidPreviewTextData(_ data: Data) {
        expect {
            _ = try HwpPreviewText.load(data)
        }.to(throwError { error in
            guard case let HwpError.invalidDataForString(actualData, name) = error else {
                return fail("Expected invalidDataForString, got \(error)")
            }
            expect(actualData) == data
            expect(name) == "PreviewText"
        })
    }
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

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
