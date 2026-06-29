@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OptionalStreamCodableStabilityTests: XCTestCase {
    func testMissingOptionalPreviewTextSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.previewText.rawValue,
            to: "XrvText",
            entryType: directoryEntryOleStreamType
        )
        let decoded = try codableRoundTrip(hwp)

        assertDefaultPreviewText(hwp.previewText)
        assertDefaultPreviewText(decoded.previewText)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testMissingOptionalPreviewImageSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.previewImage.rawValue,
            to: "XrvImage",
            entryType: directoryEntryOleStreamType
        )
        let decoded = try codableRoundTrip(hwp)

        assertDefaultPreviewImage(hwp.previewImage)
        assertDefaultPreviewImage(decoded.previewImage)
        expect(decoded.previewImage.rawPayload) == hwp.previewImage.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testMissingOptionalPreviewTextAndImageSurviveHwpFileCodableRoundTrip()
        throws
    {
        let hwp = try hwpWithRenamedRootEntries([
            DirectoryEntryRename(
                entryName: HwpStreamName.previewText.rawValue,
                newName: "XrvText",
                entryType: directoryEntryOleStreamType
            ),
            DirectoryEntryRename(
                entryName: HwpStreamName.previewImage.rawValue,
                newName: "XrvImage",
                entryType: directoryEntryOleStreamType
            ),
        ])
        let decoded = try codableRoundTrip(hwp)

        assertDefaultPreviewText(hwp.previewText)
        assertDefaultPreviewText(decoded.previewText)
        assertDefaultPreviewImage(hwp.previewImage)
        assertDefaultPreviewImage(decoded.previewImage)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testMissingOptionalSummarySurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.summary.rawValue,
            to: "\u{5}XwpSummaryInformation",
            entryType: directoryEntryOleStreamType
        )
        let decoded = try codableRoundTrip(hwp)

        expect(hwp.summary.rawPayload).to(beEmpty())
        expect(decoded.summary.rawPayload).to(beEmpty())
        expect(decoded.previewText.rawPayload) == hwp.previewText.rawPayload
        expect(decoded.previewImage.rawPayload) == hwp.previewImage.rawPayload
    }

    func testMissingOptionalBinDataSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.binData.rawValue,
            to: "XinData",
            entryType: directoryEntryOleStorageType,
            fixture: "chart"
        )
        let decoded = try codableRoundTrip(hwp)

        expect(hwp.binaryDataArray).to(beEmpty())
        expect(decoded.binaryDataArray).to(beEmpty())
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func hwpWithRenamedRootEntry(
    _ entryName: String,
    to newName: String,
    entryType: UInt8,
    fixture: String = "plain-text-minimal"
) throws -> HwpFile {
    let url = try temporaryDirectoryEntryHwp(
        basedOnFixture: fixture,
        renamingEntry: entryName,
        to: newName,
        entryType: entryType
    )
    defer { removeTemporaryDirectoryEntryFile(url) }

    return try HwpFile(fromPath: url.path)
}

private func hwpWithRenamedRootEntries(
    _ entries: [DirectoryEntryRename],
    fixture: String = "plain-text-minimal"
) throws -> HwpFile {
    let url = try temporaryDirectoryEntryHwp(
        basedOnFixture: fixture,
        renamingEntries: entries
    )
    defer { removeTemporaryDirectoryEntryFile(url) }

    return try HwpFile(fromPath: url.path)
}

private func codableRoundTrip(_ hwp: HwpFile) throws -> HwpFile {
    try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
}

private func assertDefaultPreviewText(_ previewText: HwpPreviewText) {
    expect(previewText.text) == "\r\n"
    expect(previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
}

private func assertDefaultPreviewImage(_ previewImage: HwpPreviewImage) {
    expect(previewImage.image).to(beEmpty())
    expect(previewImage.rawPayload).to(beEmpty())
    expect(previewImage.format) == HwpPreviewImageFormat.none
}
