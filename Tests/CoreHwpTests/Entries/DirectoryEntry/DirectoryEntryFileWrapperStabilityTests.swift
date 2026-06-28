#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    @testable import CoreHwp
    import Foundation
    import Nimble
    import XCTest

    final class DirectoryEntryFileWrapperStabilityTests: XCTestCase {
        func testEntrypointValidatesDirectoryEntryType() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: "DocInfo",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try hwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'DocInfo'"))
                expect(reason).to(contain("expected stream"))
            })
        }

        func testFileHeaderLoadFromWrapperValidatesDirectoryEntryType() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: "FileHeader",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])

            expect {
                _ = try HwpFileHeader.load(fromWrapper: wrapper)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'FileHeader'"))
                expect(reason).to(contain("expected stream"))
            })
        }

        func testOptionalPreviewStreamDirectoryEntryTypesAreValidated() throws {
            let cases = [
                (entryName: "PrvText", expectedType: "stream"),
                (entryName: "PrvImage", expectedType: "stream"),
            ]

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: "plain-text-minimal",
                    changingEntry: testCase.entryName,
                    fromType: directoryEntryOleStreamType,
                    toType: directoryEntryOleStorageType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                expectInvalidDirectoryEntryType(
                    at: url,
                    entryName: testCase.entryName,
                    expectedType: testCase.expectedType
                )
            }
        }

        func testOptionalBinDataDirectoryEntryTypeIsValidated() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "chart",
                changingEntry: "BinData",
                fromType: directoryEntryOleStorageType,
                toType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectInvalidDirectoryEntryType(
                at: url,
                entryName: "BinData",
                expectedType: "storage"
            )
        }

        func testDuplicateRootDirectoryEntryNamesAreRejected() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvText",
                to: "DocInfo",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try hwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Duplicate root directory entry names"))
                expect(reason).to(contain("DocInfo"))
            })

            let wrapper = try FileWrapper(url: url, options: [])
            expect {
                _ = try HwpFileHeader.load(fromWrapper: wrapper)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Duplicate root directory entry names"))
                expect(reason).to(contain("DocInfo"))
            })
        }

        func testBodyTextSectionNamesAreValidatedThroughFileWrapper() throws {
            let cases = [
                (
                    newName: "Section2",
                    toType: directoryEntryOleStreamType,
                    reason: "BodyText sections must start at Section0 and be contiguous"
                ),
                (
                    newName: "Preview",
                    toType: directoryEntryOleStreamType,
                    reason: "BodyText directory entry Preview is unexpected"
                ),
                (
                    newName: "SectionA",
                    toType: directoryEntryOleStreamType,
                    reason: "BodyText section name SectionA is malformed"
                ),
                (
                    newName: "Section01",
                    toType: directoryEntryOleStreamType,
                    reason: "BodyText section name Section01 is malformed"
                ),
                (
                    newName: "SectionA",
                    toType: directoryEntryOleStorageType,
                    reason: "BodyText section name SectionA is malformed"
                ),
            ]

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: "multi-section",
                    renamingEntryAllowingLengthChange: "Section1",
                    to: testCase.newName,
                    fromType: directoryEntryOleStreamType,
                    toType: testCase.toType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                expect {
                    _ = try hwpFromFileWrapper(at: url)
                }.to(throwError { error in
                    guard case let HwpError.invalidRecordTree(reason) = error else {
                        return fail("Expected invalidRecordTree, got \(error)")
                    }
                    expect(reason) == testCase.reason
                })
            }
        }

        func testMissingOptionalPreviewTextUsesDefaultPreviewText() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvText",
                to: "XrvText",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let hwp = try hwpFromFileWrapper(at: url)

            expect(hwp.previewText.text) == "\r\n"
            expect(hwp.previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
        }

        func testMissingOptionalPreviewImageUsesDefaultPreviewImage() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                renamingEntry: "PrvImage",
                to: "XrvImage",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            let hwp = try hwpFromFileWrapper(at: url)

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

            let hwp = try hwpFromFileWrapper(at: url)

            expect(hwp.binaryDataArray).to(beEmpty())
        }

        func testBinDataStreamsPreserveNamesMetadataAndPayloads() throws {
            let url = hwpURL(#file, "BinData")
            let pathHwp = try HwpFile(fromPath: url.path)
            let wrapperHwp = try hwpFromFileWrapper(at: url)

            expect(wrapperHwp.binaryDataArray.map(\.name)) ==
                pathHwp.binaryDataArray.map(\.name)
            expect(wrapperHwp.binaryDataArray.map(\.streamId)) ==
                pathHwp.binaryDataArray.map(\.streamId)
            expect(wrapperHwp.binaryDataArray.map(\.extensionName)) ==
                pathHwp.binaryDataArray.map(\.extensionName)
            expect(wrapperHwp.binaryDataArray.map(\.data)) ==
                pathHwp.binaryDataArray.map(\.data)
            expect(wrapperHwp.binaryDataArray.map(\.data.count)) == [62875, 51551, 20462]
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

            let hwp = try hwpFromFileWrapper(at: url)

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

        func testDuplicateBinDataStreamNamesAreRejected() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "BinData",
                renamingEntry: "BIN0003.gif",
                to: "BIN0001.png",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try hwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Duplicate BinData directory entry names"))
                expect(reason).to(contain("BIN0001.png"))
            })
        }

        func testNonStreamBinDataChildrenAreRejectedAsDirectoryTypeErrors() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "BinData",
                changingEntry: "BIN0002.jpeg",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try hwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'BinData/BIN0002.jpeg'"))
                expect(reason).to(contain("expected stream"))
            })
        }
    }

    private func hwpFromFileWrapper(at url: URL) throws -> HwpFile {
        let wrapper = try FileWrapper(url: url, options: [])
        return try HwpFile(fromWrapper: wrapper)
    }

    private func expectInvalidDirectoryEntryType(
        at url: URL,
        entryName: String,
        expectedType: String
    ) {
        expect {
            _ = try hwpFromFileWrapper(at: url)
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("Directory entry '\(entryName)'"))
            expect(reason).to(contain("expected \(expectedType)"))
        })
    }
#endif
