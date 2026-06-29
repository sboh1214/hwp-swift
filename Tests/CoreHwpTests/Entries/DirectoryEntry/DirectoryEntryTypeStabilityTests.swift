@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class DirectoryEntryTypeStabilityTests: XCTestCase {
    func testFileHeaderDirectoryEntryMustBeStream() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "FileHeader",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "FileHeader", expectedType: "stream")
    }

    func testFileHeaderLoadFromPathValidatesDirectoryEntryType() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "FileHeader",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFileHeader.load(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("Directory entry 'FileHeader'"))
            expect(reason).to(contain("expected stream"))
        })
    }

    func testDocInfoDirectoryEntryMustBeStream() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "DocInfo",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "DocInfo", expectedType: "stream")
    }

    func testDuplicateRootDirectoryEntryNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "PrvText",
            to: "DocInfo",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectDuplicateRootDirectoryEntryName("DocInfo") {
            _ = try HwpFile(fromPath: url.path)
        }
        expectDuplicateRootDirectoryEntryName("DocInfo") {
            _ = try HwpFileHeader.load(fromPath: url.path)
        }
    }

    func testBodyTextDirectoryEntryMustBeStorage() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "BodyText",
            fromType: directoryEntryOleStorageType,
            toType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "BodyText", expectedType: "storage")
    }

    func testNonStreamBodyTextSectionChildrenAreRejectedAsDirectoryTypeErrors() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "Section0",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("Directory entry 'BodyText/Section0'"))
            expect(reason).to(contain("expected stream"))
        })
    }

    func testDuplicateBodyTextSectionNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntry: "Section1",
            to: "Section0",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectDuplicateStorageDirectoryEntryName(
            url,
            storageName: "BodyText",
            duplicateName: "Section0"
        )
    }

    func testBodyTextSectionGapsAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntry: "Section1",
            to: "Section2",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidBodyTextSectionTree(url)
    }

    func testUnexpectedBodyTextChildrenAreRejectedBeforeSectionCountMismatch() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntryAllowingLengthChange: "Section1",
            to: "Preview",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectUnexpectedBodyTextDirectoryEntry(url, entryName: "Preview")
    }

    func testBodyTextSectionsAreReadInNumericNameOrderFromActualHwp() throws {
        let original = try HwpFile(fromPath: hwpURL(#file, "multi-section").path)
        let originalPayloads = original.sectionArray.map(\.rawPayload)
        expect(originalPayloads.count) == 2

        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            swappingEntry: "Section0",
            with: "Section1",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.sectionArray.map(\.rawPayload)) == Array(originalPayloads.reversed())
    }

    func testMalformedBodyTextSectionNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntry: "Section1",
            to: "SectionA",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText section name SectionA is malformed"))
        })
    }

    func testMalformedNonStreamBodyTextSectionNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntryAllowingLengthChange: "Section1",
            to: "SectionA",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText section name SectionA is malformed"))
        })
    }

    func testLeadingZeroBodyTextSectionNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "multi-section",
            renamingEntryAllowingLengthChange: "Section1",
            to: "Section01",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expect {
            _ = try HwpFile(fromPath: url.path)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText section name Section01 is malformed"))
        })
    }

    func testBinDataDirectoryEntryMustBeStorageWhenPresent() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "chart",
            changingEntry: "BinData",
            fromType: directoryEntryOleStorageType,
            toType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "BinData", expectedType: "storage")
    }

    func testPreviewTextDirectoryEntryMustBeStreamWhenPresent() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "PrvText",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "PrvText", expectedType: "stream")
    }

    func testMissingOptionalPreviewTextUsesDefaultPreviewText() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "PrvText",
            to: "XrvText",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.previewText.text) == "\r\n"
        expect(hwp.previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
    }

    func testPreviewImageDirectoryEntryMustBeStreamWhenPresent() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            changingEntry: "PrvImage",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidDirectoryEntryType(url, entryName: "PrvImage", expectedType: "stream")
    }

    func testMissingOptionalPreviewImageUsesDefaultPreviewImage() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "PrvImage",
            to: "XrvImage",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.previewImage.image).to(beEmpty())
        expect(hwp.previewImage.format) == HwpPreviewImageFormat.none
    }

    func testMissingOptionalBinDataStorageUsesEmptyBinaryDataArray() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "chart",
            renamingEntry: "BinData",
            to: "XinData",
            entryType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.binaryDataArray).to(beEmpty())
    }

    func testDuplicateBinDataStreamNamesAreRejected() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "BinData",
            renamingEntry: "BIN0003.gif",
            to: "BIN0001.png",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectDuplicateStorageDirectoryEntryName(
            url,
            storageName: "BinData",
            duplicateName: "BIN0001.png"
        )
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let data = try Data(contentsOf: url)
            expectDuplicateStorageDirectoryEntryName(
                storageName: "BinData",
                duplicateName: "BIN0001.png"
            ) {
                _ = try HwpFile(fromData: data)
            }
            expectDuplicateStorageDirectoryEntryName(
                storageName: "BinData",
                duplicateName: "BIN0001.png"
            ) {
                _ = try HwpFile(fromWrapper: FileWrapper(url: url, options: []))
            }
        #endif
    }

    func testUnrecognizedBinDataStreamNamesArePreservedWithoutMetadata() throws {
        let originalHwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)
        guard let originalPayload = originalHwp.binaryDataArray
            .first(where: { $0.name == "BIN0002.jpeg" })?.data
        else {
            return fail("Expected BIN0002.jpeg in BinData fixture")
        }
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "BinData",
            renamingEntry: "BIN0002.jpeg",
            to: "bin0002.jpeg",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let hwp = try HwpFile(fromPath: url.path)

        expect(hwp.binaryDataArray.map(\.name)) == [
            "BIN0001.png",
            "BIN0003.gif",
            "bin0002.jpeg",
        ]
        guard let renamed = hwp.binaryDataArray.first(
            where: { $0.name == "bin0002.jpeg" }
        ) else {
            return fail("Expected renamed BinData stream to be preserved")
        }
        expect(renamed.streamId).to(beNil())
        expect(renamed.extensionName).to(beNil())
        expect(renamed.data) == originalPayload
    }

    func testNonStreamBinDataChildrenAreRejectedAsDirectoryTypeErrors() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "BinData",
            changingEntry: "BIN0002.jpeg",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectInvalidBinDataChildType("BIN0002.jpeg") {
            _ = try HwpFile(fromPath: url.path)
        }
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let data = try Data(contentsOf: url)
            expectInvalidBinDataChildType("BIN0002.jpeg") {
                _ = try HwpFile(fromData: data)
            }
            expectInvalidBinDataChildType("BIN0002.jpeg") {
                _ = try HwpFile(fromWrapper: FileWrapper(url: url, options: []))
            }
        #endif
    }
}

private func expectInvalidDirectoryEntryType(
    _ url: URL,
    entryName: String,
    expectedType: String
) {
    expect {
        _ = try HwpFile(fromPath: url.path)
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Directory entry '\(entryName)'"))
        expect(reason).to(contain("expected \(expectedType)"))
    })
}

private func expectDuplicateRootDirectoryEntryName(
    _ duplicateName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Duplicate root directory entry names"))
        expect(reason).to(contain(duplicateName))
    })
}

private func expectDuplicateStorageDirectoryEntryName(
    _ url: URL,
    storageName: String,
    duplicateName: String
) {
    expectDuplicateStorageDirectoryEntryName(
        storageName: storageName,
        duplicateName: duplicateName
    ) {
        _ = try HwpFile(fromPath: url.path)
    }
}

private func expectDuplicateStorageDirectoryEntryName(
    storageName: String,
    duplicateName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Duplicate \(storageName) directory entry names"))
        expect(reason).to(contain(duplicateName))
    })
}

private func expectInvalidBinDataChildType(
    _ entryName: String,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidOLEFile(reason) = error else {
            return fail("Expected invalidOLEFile, got \(error)")
        }
        expect(reason).to(contain("Directory entry 'BinData/\(entryName)'"))
        expect(reason).to(contain("expected stream"))
    })
}

private func expectInvalidBodyTextSectionTree(_ url: URL) {
    expect {
        _ = try HwpFile(fromPath: url.path)
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("BodyText sections"))
    })
}

private func expectUnexpectedBodyTextDirectoryEntry(_ url: URL, entryName: String) {
    expect {
        _ = try HwpFile(fromPath: url.path)
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("BodyText directory entry \(entryName) is unexpected"))
    })
}
