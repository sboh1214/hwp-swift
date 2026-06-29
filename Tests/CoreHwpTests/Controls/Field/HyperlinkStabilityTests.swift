@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HyperlinkStabilityTests: XCTestCase {
    func testHyperlinkInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let url = "docs"
        let rawTrailing = Data([0xAA, 0xBB])
        let payload = hyperlinkPayload(url: url, rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xEF]), payload).dropFirst()
        let childPayload = Data([0xCC])
        let child = HwpRecord(tagId: 0x2FA, level: 2, payload: childPayload)
        var reader = DataReader(slicedPayload)

        let hyperlink = try HwpHyperlink(&reader, [child])

        expect(hyperlink.ctrlId) == HwpFieldCtrlId.hyperLink.rawValue
        expect(hyperlink.url) == url
        expect(hyperlink.urlLengthRawPayload) == Data([0x04, 0x00])
        expect(hyperlink.urlRawPayload) == hyperlinkUTF16Payload(url)
        expect(hyperlink.rawTrailing) == rawTrailing
        expect(hyperlink.rawPayload) == slicedPayload
        expect(hyperlink.unknownChildren) == [
            expectedTestUnknownRecord(tagId: 0x2FA, level: 2, payload: childPayload),
        ]
        expect(reader.isEOF) == true
    }

    func testHyperlinkPreservesSurrogatePairURLRawPayload() throws {
        let url = "https://example.test/😀"
        let urlRawPayload = hyperlinkUTF16Payload(url)
        let rawTrailing = Data([0xAA, 0xBB])
        let rawPayload = hyperlinkPayload(url: url, rawTrailing: rawTrailing)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        let hyperlink = try HwpHyperlink.load(record)

        expect(hyperlink.ctrlId) == HwpFieldCtrlId.hyperLink.rawValue
        expect(hyperlink.urlLength) == WORD(url.utf16.count)
        expect(hyperlink.urlLengthRawPayload) ==
            hyperlinkLittleEndianData(WORD(url.utf16.count))
        expect(hyperlink.url) == url
        expect(hyperlink.urlRawPayload) == urlRawPayload
        expect(hyperlink.rawTrailing) == rawTrailing
        expect(hyperlink.rawPayload) == rawPayload
    }

    func testHyperlinkURLRawPayloadHandlesNonZeroDataStartIndex() throws {
        let url = "docs"
        let rawTrailing = Data([0xCC, 0xDD])
        let expectedPayload = hyperlinkPayload(url: url, rawTrailing: rawTrailing)
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), expectedPayload).dropFirst(2)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: slicedPayload
        )

        let hyperlink = try HwpHyperlink.load(record)

        expect(hyperlink.url) == url
        expect(hyperlink.urlLengthRawPayload) == Data([0x04, 0x00])
        expect(hyperlink.urlRawPayload) == hyperlinkUTF16Payload(url)
        expect(hyperlink.rawPayload) == expectedPayload
        expect(hyperlink.rawTrailing) == rawTrailing
    }

    func testHyperlinkTruncatedFixedHeaderThrowsTypedError() {
        let rawPayload = concatenatedData(
            hyperlinkLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue),
            Data([0xAA, 0xBB])
        )

        expectTruncatedHyperlink(rawPayload, expected: 4, actual: 2)
    }

    func testHyperlinkTruncatedURLPayloadThrowsTypedError() {
        var rawPayload = Data()
        rawPayload.append(hyperlinkLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
        rawPayload.append(hyperlinkLittleEndianData(UInt32(0)))
        rawPayload.append(hyperlinkLittleEndianData(BYTE(0)))
        rawPayload.append(hyperlinkLittleEndianData(WORD(3)))
        rawPayload.append(hyperlinkLittleEndianData(WCHAR(0x0041)))

        expectTruncatedHyperlink(rawPayload, expected: 6, actual: 2)
    }

    func testHyperlinkRejectsUnpairedSurrogateWithTypedError() {
        let urlRawPayload = hyperlinkLittleEndianData(WCHAR(0xD83D))
        var rawPayload = Data()
        rawPayload.append(hyperlinkLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
        rawPayload.append(hyperlinkLittleEndianData(UInt32(0)))
        rawPayload.append(hyperlinkLittleEndianData(BYTE(0)))
        rawPayload.append(hyperlinkLittleEndianData(WORD(1)))
        rawPayload.append(urlRawPayload)
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: rawPayload
        )

        expect {
            _ = try HwpHyperlink.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD83D
        })
    }

    func testCCLFixtureHyperlinksSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "CCL")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let expectedHyperlinks = try cclHyperlinkExpectations(fixture)
        let originalHyperlinks = FixtureDerivedValues.hyperlinks(from: hwp)
        let decodedHyperlinks = FixtureDerivedValues.hyperlinks(from: decoded)

        FixtureAssertions.assertHyperlinks(expectedHyperlinks, decoded)
        assertHyperlinkPayloadsMatch(decodedHyperlinks, originalHyperlinks)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private struct HyperlinkUnknownFingerprint: Equatable {
    let tagId: UInt32
    let level: UInt32
    let payload: Data
    let children: [HyperlinkUnknownFingerprint]
}

private func cclHyperlinkExpectations(
    _ fixture: LoadedFixture
) throws -> [FixtureHyperlinkExpectations] {
    guard let hyperlinks = fixture.manifest.expectations.hyperlinks else {
        fail("Expected CCL fixture manifest to declare hyperlinks")
        return []
    }

    return hyperlinks
}

private func assertHyperlinkPayloadsMatch(
    _ decoded: [HwpHyperlink],
    _ original: [HwpHyperlink]
) {
    expect(decoded.map(\.ctrlId)) == original.map(\.ctrlId)
    expect(decoded.map(\.url)) == original.map(\.url)
    expect(decoded.map(\.urlLengthRawPayload)) == original.map(\.urlLengthRawPayload)
    expect(decoded.map(\.urlRawPayload)) == original.map(\.urlRawPayload)
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map { hyperlinkUnknownFingerprints($0.unknownChildren) }) ==
        original.map { hyperlinkUnknownFingerprints($0.unknownChildren) }
}

private func hyperlinkUnknownFingerprints(
    _ records: [HwpUnknownRecord]
) -> [HyperlinkUnknownFingerprint] {
    records.map { record in
        HyperlinkUnknownFingerprint(
            tagId: record.tagId,
            level: record.level,
            payload: record.payload,
            children: hyperlinkUnknownFingerprints(record.children)
        )
    }
}

private func hyperlinkPayload(url: String, rawTrailing: Data) -> Data {
    var data = Data()
    data.append(hyperlinkLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
    data.append(hyperlinkLittleEndianData(UInt32(0)))
    data.append(hyperlinkLittleEndianData(BYTE(0)))
    data.append(hyperlinkLittleEndianData(WORD(url.utf16.count)))
    data.append(hyperlinkUTF16Payload(url))
    data.append(rawTrailing)
    return data
}

private func hyperlinkUTF16Payload(_ value: String) -> Data {
    var data = Data()
    for character in value.utf16 {
        data.append(hyperlinkLittleEndianData(WCHAR(character)))
    }
    return data
}

private func expectTruncatedHyperlink(_ payload: Data, expected: Int, actual: Int) {
    let record = HwpRecord(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: payload
    )

    expect {
        _ = try HwpHyperlink.load(record)
    }.to(throwError { error in
        guard case let HwpError.truncatedData(expectedBytes, actualBytes) = error else {
            return fail("Expected truncatedData, got \(error)")
        }
        expect(expectedBytes) == expected
        expect(actualBytes) == actual
    })
}

private func hyperlinkLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
