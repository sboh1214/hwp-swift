@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class OptionalStreamStabilityTests: XCTestCase {
    func testMissingOptionalPreviewTextFallsBackToDefault() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.previewText.rawValue,
            to: "XrvText",
            entryType: directoryEntryOleStreamType
        )

        assertDefaultPreviewText(hwp.previewText)
    }

    func testMissingOptionalPreviewImageFallsBackToDefault() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.previewImage.rawValue,
            to: "XrvImage",
            entryType: directoryEntryOleStreamType
        )

        assertDefaultPreviewImage(hwp.previewImage)
    }

    func testMissingOptionalPreviewTextAndImageFallBackToDefaults() throws {
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

        assertDefaultPreviewText(hwp.previewText)
        assertDefaultPreviewImage(hwp.previewImage)
    }

    func testMissingOptionalSummaryFallsBackToEmptyPayload() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.summary.rawValue,
            to: "\u{5}XwpSummaryInformation",
            entryType: directoryEntryOleStreamType
        )

        expect(hwp.summary.rawPayload).to(beEmpty())
    }

    func testMissingOptionalBinDataFallsBackToEmptyArray() throws {
        let hwp = try hwpWithRenamedRootEntry(
            HwpStreamName.binData.rawValue,
            to: "XinData",
            entryType: directoryEntryOleStorageType,
            fixture: "chart"
        )

        expect(hwp.binaryDataArray).to(beEmpty())
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

private func assertDefaultPreviewText(_ previewText: HwpPreviewText) {
    expect(previewText.text) == "\r\n"
    expect(previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
}

private func assertDefaultPreviewImage(_ previewImage: HwpPreviewImage) {
    expect(previewImage.image).to(beEmpty())
    expect(previewImage.rawPayload).to(beEmpty())
    expect(previewImage.format) == HwpPreviewImageFormat.none
}
