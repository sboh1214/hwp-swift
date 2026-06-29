@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixtureCodableRoundTripTests: XCTestCase {
    func testReadableFixturesPreserveManifestExpectationsThroughCodableRoundTrip() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let hwp = try HwpFile(fromPath: fixture.documentURL.path)
            let encoded = try encodedHwp(from: hwp)
            let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

            try FixtureAssertions.assertReadableFixture(fixture, decoded)
            expect(try encodedHwp(from: decoded)) == encoded
            expect(decoded.fileHeader.rawPayload) == hwp.fileHeader.rawPayload
            expect(decoded.fileHeader.reserved) == hwp.fileHeader.reserved
            expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
            expect(try encodedDocInfo(from: decoded)) == (try encodedDocInfo(from: hwp))
            expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
            expect(decoded.summary.rawPayload) == hwp.summary.rawPayload
            expect(decoded.previewText.rawPayload) == hwp.previewText.rawPayload
            expect(decoded.previewImage.rawPayload) == hwp.previewImage.rawPayload
            expect(decoded.binaryDataArray.map(\.data)) == hwp.binaryDataArray.map(\.data)
            assertParagraphPayloadsPreserved(original: hwp, decoded: decoded)
            assertUnknownRecordsPreserved(original: hwp, decoded: decoded)
            expect(try encodedControls(from: decoded)) == (try encodedControls(from: hwp))
            expect(try encodedInlineControls(from: decoded)) ==
                (try encodedInlineControls(from: hwp))
        }
    }
}

private struct UnknownRecordFingerprint: Equatable {
    let tagId: UInt32
    let level: UInt32
    let payload: Data
    let children: [UnknownRecordFingerprint]
}

private func assertParagraphPayloadsPreserved(
    original: HwpFile,
    decoded: HwpFile
) {
    expect(FixtureDerivedValues.paraTextRawPayloads(from: decoded)) ==
        FixtureDerivedValues.paraTextRawPayloads(from: original)
    expect(FixtureDerivedValues.paraTextPayloads(from: decoded)) ==
        FixtureDerivedValues.paraTextPayloads(from: original)
    expect(FixtureDerivedValues.paraHeaderPayloads(from: decoded)) ==
        FixtureDerivedValues.paraHeaderPayloads(from: original)
    expect(FixtureDerivedValues.paraCharShapePayloads(from: decoded)) ==
        FixtureDerivedValues.paraCharShapePayloads(from: original)
    expect(FixtureDerivedValues.paraLineSegPayloads(from: decoded)) ==
        FixtureDerivedValues.paraLineSegPayloads(from: original)
    expect(FixtureDerivedValues.paraRangeTagPayloads(from: decoded)) ==
        FixtureDerivedValues.paraRangeTagPayloads(from: original)
}

private func assertUnknownRecordsPreserved(
    original: HwpFile,
    decoded: HwpFile
) {
    expect(unknownRecordFingerprints(decoded.docInfo.unknownRecords)) ==
        unknownRecordFingerprints(original.docInfo.unknownRecords)
    expect(unknownRecordFingerprints(decoded.docInfo.idMappings.unknownChildren)) ==
        unknownRecordFingerprints(original.docInfo.idMappings.unknownChildren)
    expect(decoded.sectionArray.map { unknownRecordFingerprints($0.unknownRecords) }) ==
        original.sectionArray.map { unknownRecordFingerprints($0.unknownRecords) }

    let decodedParagraphs = FixtureDerivedValues.allParagraphs(from: decoded)
    let originalParagraphs = FixtureDerivedValues.allParagraphs(from: original)
    expect(decodedParagraphs.map { unknownRecordFingerprints($0.unknownChildren) }) ==
        originalParagraphs.map { unknownRecordFingerprints($0.unknownChildren) }
}

private func unknownRecordFingerprints(
    _ records: [HwpUnknownRecord]
) -> [UnknownRecordFingerprint] {
    records.map { record in
        UnknownRecordFingerprint(
            tagId: record.tagId,
            level: record.level,
            payload: record.payload,
            children: unknownRecordFingerprints(record.children)
        )
    }
}

private func encodedControls(from hwp: HwpFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(FixtureDerivedValues.allControls(from: hwp))
}

private func encodedHwp(from hwp: HwpFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(hwp)
}

private func encodedDocInfo(from hwp: HwpFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(hwp.docInfo)
}

private func encodedInlineControls(from hwp: HwpFile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(FixtureDerivedValues.paraTextInlineControls(from: hwp))
}
