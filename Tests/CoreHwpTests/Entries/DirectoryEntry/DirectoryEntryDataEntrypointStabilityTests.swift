#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    @testable import CoreHwp
    import Foundation
    import Nimble
    import XCTest

    final class DirectoryEntryDataEntrypointTests: XCTestCase {
        func testDataEntrypointValidatesDirectoryEntryTypes() throws {
            for testCase in directoryEntryTypeDataCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    changingEntry: testCase.entryName,
                    fromType: testCase.fromType,
                    toType: testCase.toType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                try expectInvalidDirectoryEntryTypeFromData(
                    at: url,
                    entryName: testCase.expectedEntryName,
                    expectedType: testCase.expectedType
                )
            }
        }

        func testFileHeaderDataEntrypointValidatesDirectoryEntryType() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: "FileHeader",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let data = try Data(contentsOf: url)
            expect {
                _ = try HwpFileHeader.load(fromData: data)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'FileHeader'"))
                expect(reason).to(contain("expected stream"))
            })
        }

        func testDataEntrypointRejectsDuplicateRootDirectoryEntryNames() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvText",
                to: "DocInfo",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let data = try Data(contentsOf: url)
            expectDuplicateDirectoryEntryFromData(
                "Duplicate root directory entry names",
                "DocInfo"
            ) {
                _ = try HwpFile(fromData: data)
            }
            expectDuplicateDirectoryEntryFromData(
                "Duplicate root directory entry names",
                "DocInfo"
            ) {
                _ = try HwpFileHeader.load(fromData: data)
            }
        }

        func testDataEntrypointRejectsDuplicateStorageChildNames() throws {
            for testCase in directoryEntryDuplicateStorageCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    renamingEntry: testCase.entryName,
                    to: testCase.newName,
                    entryType: testCase.entryType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let data = try Data(contentsOf: url)
                expectDuplicateDirectoryEntryFromData(
                    testCase.expectedReasonPrefix,
                    testCase.duplicateName
                ) {
                    _ = try HwpFile(fromData: data)
                }
            }
        }

        func testDataEntrypointRejectsInvalidBodyTextSectionNames() throws {
            for testCase in bodyTextSectionNameDataCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: "multi-section",
                    renamingEntryAllowingLengthChange: "Section1",
                    to: testCase.newName,
                    fromType: directoryEntryOleStreamType,
                    toType: testCase.toType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                try expectInvalidRecordTreeFromData(at: url, reason: testCase.reason)
            }
        }

        func testDataEntrypointReadsBodyTextSectionsInNumericNameOrder() throws {
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

            let hwp = try HwpFile(fromData: Data(contentsOf: url))

            expect(hwp.sectionArray.map(\.rawPayload)) == Array(originalPayloads.reversed())
        }

        func testDataEntrypointPreservesUnrecognizedBinDataStreamNames() throws {
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

            let hwp = try HwpFile(fromData: Data(contentsOf: url))

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

        func testDataEntrypointUsesDefaultsForMissingOptionalStreams() throws {
            let previewTextURL = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvText",
                to: "XrvText",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(previewTextURL) }

            let previewTextHwp = try HwpFile(fromData: Data(contentsOf: previewTextURL))
            expect(previewTextHwp.previewText.text) == "\r\n"
            expect(previewTextHwp.previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])

            let previewImageURL = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvImage",
                to: "XrvImage",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(previewImageURL) }

            let previewImageHwp = try HwpFile(fromData: Data(contentsOf: previewImageURL))
            expect(previewImageHwp.previewImage.image).to(beEmpty())
            expect(previewImageHwp.previewImage.format) == HwpPreviewImageFormat.none

            let binDataURL = try temporaryDirectoryEntryHwp(
                basedOnFixture: "chart",
                renamingEntry: "BinData",
                to: "XinData",
                entryType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(binDataURL) }

            let binDataHwp = try HwpFile(fromData: Data(contentsOf: binDataURL))
            expect(binDataHwp.binaryDataArray).to(beEmpty())
        }
    }

    private struct DirectoryEntryTypeDataCase {
        let fixtureId: String
        let entryName: String
        let fromType: UInt8
        let toType: UInt8
        let expectedEntryName: String
        let expectedType: String
    }

    private struct DirectoryEntryDuplicateStorageCase {
        let fixtureId: String
        let entryName: String
        let newName: String
        let entryType: UInt8
        let expectedReasonPrefix: String
        let duplicateName: String
    }

    private struct BodyTextSectionNameDataCase {
        let newName: String
        let toType: UInt8
        let reason: String
    }

    private let directoryEntryTypeDataCases = [
        DirectoryEntryTypeDataCase(
            fixtureId: "plain-text-minimal",
            entryName: "DocInfo",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType,
            expectedEntryName: "DocInfo",
            expectedType: "stream"
        ),
        DirectoryEntryTypeDataCase(
            fixtureId: "plain-text-minimal",
            entryName: "BodyText",
            fromType: directoryEntryOleStorageType,
            toType: directoryEntryOleStreamType,
            expectedEntryName: "BodyText",
            expectedType: "storage"
        ),
        DirectoryEntryTypeDataCase(
            fixtureId: "plain-text-minimal",
            entryName: "PrvText",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType,
            expectedEntryName: "PrvText",
            expectedType: "stream"
        ),
        DirectoryEntryTypeDataCase(
            fixtureId: "plain-text-minimal",
            entryName: "PrvImage",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType,
            expectedEntryName: "PrvImage",
            expectedType: "stream"
        ),
        DirectoryEntryTypeDataCase(
            fixtureId: "chart",
            entryName: "BinData",
            fromType: directoryEntryOleStorageType,
            toType: directoryEntryOleStreamType,
            expectedEntryName: "BinData",
            expectedType: "storage"
        ),
        DirectoryEntryTypeDataCase(
            fixtureId: "BinData",
            entryName: "BIN0002.jpeg",
            fromType: directoryEntryOleStreamType,
            toType: directoryEntryOleStorageType,
            expectedEntryName: "BinData/BIN0002.jpeg",
            expectedType: "stream"
        ),
    ]

    private let directoryEntryDuplicateStorageCases = [
        DirectoryEntryDuplicateStorageCase(
            fixtureId: "multi-section",
            entryName: "Section1",
            newName: "Section0",
            entryType: directoryEntryOleStreamType,
            expectedReasonPrefix: "Duplicate BodyText directory entry names",
            duplicateName: "Section0"
        ),
        DirectoryEntryDuplicateStorageCase(
            fixtureId: "BinData",
            entryName: "BIN0003.gif",
            newName: "BIN0001.png",
            entryType: directoryEntryOleStreamType,
            expectedReasonPrefix: "Duplicate BinData directory entry names",
            duplicateName: "BIN0001.png"
        ),
    ]

    private let bodyTextSectionNameDataCases = [
        BodyTextSectionNameDataCase(
            newName: "Section2",
            toType: directoryEntryOleStreamType,
            reason: "BodyText sections must start at Section0 and be contiguous"
        ),
        BodyTextSectionNameDataCase(
            newName: "Preview",
            toType: directoryEntryOleStreamType,
            reason: "BodyText directory entry Preview is unexpected"
        ),
        BodyTextSectionNameDataCase(
            newName: "SectionA",
            toType: directoryEntryOleStreamType,
            reason: "BodyText section name SectionA is malformed"
        ),
        BodyTextSectionNameDataCase(
            newName: "Section01",
            toType: directoryEntryOleStreamType,
            reason: "BodyText section name Section01 is malformed"
        ),
        BodyTextSectionNameDataCase(
            newName: "SectionA",
            toType: directoryEntryOleStorageType,
            reason: "BodyText section name SectionA is malformed"
        ),
    ]

    private func expectInvalidDirectoryEntryTypeFromData(
        at url: URL,
        entryName: String,
        expectedType: String
    ) throws {
        let data = try Data(contentsOf: url)
        expect {
            _ = try HwpFile(fromData: data)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("Directory entry '\(entryName)'"))
            expect(reason).to(contain("expected \(expectedType)"))
        })
    }

    private func expectInvalidRecordTreeFromData(
        at url: URL,
        reason expectedReason: String
    ) throws {
        let data = try Data(contentsOf: url)
        expect {
            _ = try HwpFile(fromData: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain(expectedReason))
        })
    }

    private func expectDuplicateDirectoryEntryFromData(
        _ expectedReasonPrefix: String,
        _ duplicateName: String,
        _ expression: @escaping () throws -> Void
    ) {
        expect {
            try expression()
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain(expectedReasonPrefix))
            expect(reason).to(contain(duplicateName))
        })
    }
#endif
