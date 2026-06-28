@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class PreviewStreamPrimitiveTests: XCTestCase {
    func testPreviewTextLoadPreservesRawPayload() throws {
        let data = Data([0x41, 0x00, 0x0D, 0x00, 0x0A, 0x00])
        let preview = try HwpPreviewText.load(data)

        expect(preview.text) == "A\r\n"
        expect(preview.rawPayload) == data
    }

    func testPreviewTextPublicInitializerPreservesRawPayload() throws {
        let data = utf16LittleEndianData("Public\r\n")

        let preview = try HwpPreviewText(rawPayload: data)

        expect(preview.text) == "Public\r\n"
        expect(preview.rawPayload) == data
    }

    func testPreviewTextDecodesUtf16SurrogatePairs() throws {
        let text = "A😀\r\n"
        let data = utf16LittleEndianData(text)

        let preview = try HwpPreviewText.load(data)

        expect(preview.text) == text
        expect(preview.rawPayload) == data
    }

    func testPreviewTextLoadHandlesNonZeroStartIndexPayload() throws {
        let text = "Slice\r\n"
        let payload = utf16LittleEndianData(text)
        let data = (Data([0xFF]) + payload).dropFirst(1)

        let preview = try HwpPreviewText.load(data)

        expect(preview.text) == text
        expect(preview.rawPayload) == payload
    }

    func testPreviewTextOddBytePayloadThrowsTypedError() {
        let data = Data([0x41])

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

    func testPreviewTextPublicInitializerRejectsInvalidPayloadWithTypedError() {
        let data = Data([0x41])

        expect {
            _ = try HwpPreviewText(rawPayload: data)
        }.to(throwError { error in
            guard case let HwpError.invalidDataForString(actualData, name) = error else {
                return fail("Expected invalidDataForString, got \(error)")
            }
            expect(actualData) == data
            expect(name) == "PreviewText"
        })
    }

    func testPreviewImageLoadPreservesBytes() throws {
        let data = Data([0x42, 0x4D, 0x00])
        let preview = try HwpPreviewImage.load(data)

        expect(preview.rawPayload) == data
        expect(preview.image) == data
        expect(preview.format) == .bmp
    }

    func testPreviewImagePublicInitializerPreservesBytes() {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE1])

        let preview = HwpPreviewImage(rawPayload: data)

        expect(preview.rawPayload) == data
        expect(preview.image) == data
        expect(preview.format) == .jpeg
    }

    func testPreviewImageLoadTreatsEmptyPayloadAsNoPreviewImage() throws {
        let preview = try HwpPreviewImage.load(Data())

        expect(preview.rawPayload).to(beEmpty())
        expect(preview.image).to(beEmpty())
        expect(preview.format) == HwpPreviewImageFormat.none
    }

    func testPreviewImageLoadDetectsKnownFormatsAndPreservesUnknownBytes() throws {
        let cases: [(Data, HwpPreviewImageFormat)] = [
            (Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]), .gif),
            (Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), .png),
            (Data([0xFF, 0xD8, 0xFF, 0xE0]), .jpeg),
            (Data([0x00, 0x01, 0x02]), .unknown),
        ]

        for (data, format) in cases {
            let preview = try HwpPreviewImage.load(data)
            expect(preview.rawPayload) == data
            expect(preview.image) == data
            expect(preview.format) == format
        }
    }

    func testPreviewImageLoadDetectsFormatFromNonZeroStartIndexPayload() throws {
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let data = (Data([0xFF, 0xFE]) + payload).dropFirst(2)

        let preview = try HwpPreviewImage.load(data)

        expect(preview.rawPayload) == payload
        expect(preview.image) == payload
        expect(preview.format) == .png
    }

    func testPreviewImageShortSignaturesRemainUnknownAndPreserveBytes() throws {
        let shortSignatures = [
            Data([0x42]),
            Data([0x47, 0x49, 0x46]),
            Data([0x89, 0x50, 0x4E, 0x47]),
            Data([0xFF, 0xD8]),
        ]

        for data in shortSignatures {
            let preview = try HwpPreviewImage.load(data)
            expect(preview.rawPayload) == data
            expect(preview.image) == data
            expect(preview.format) == .unknown
        }
    }

    func testSummaryLoadPreservesRawPayload() throws {
        let data = Data([0xFE, 0xFF, 0x00, 0x00])
        let summary = try HwpSummary.load(data)

        expect(summary.rawPayload) == data
    }

    func testSummaryPublicInitializerPreservesRawPayload() {
        let data = Data([0x05, 0x48, 0x57, 0x50])

        let summary = HwpSummary(rawPayload: data)

        expect(summary.rawPayload) == data
    }

    func testSummaryLoadHandlesNonZeroStartIndexPayload() throws {
        let payload = Data([0x05, 0x48, 0x57, 0x50])
        let data = (Data([0xAA, 0xBB]) + payload).dropFirst(2)

        let summary = try HwpSummary.load(data)
        let decoded = try JSONDecoder().decode(
            HwpSummary.self,
            from: JSONEncoder().encode(summary)
        )

        expect(summary.rawPayload) == payload
        expect(decoded.rawPayload) == payload
    }
}

private func utf16LittleEndianData(_ string: String) -> Data {
    string.utf16.reduce(into: Data()) { data, codeUnit in
        var littleEndian = codeUnit.littleEndian
        data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
    }
}
