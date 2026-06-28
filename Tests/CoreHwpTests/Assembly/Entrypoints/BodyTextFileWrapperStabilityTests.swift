#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    @testable import CoreHwp
    import Foundation
    import Nimble
    import XCTest

    final class BodyTextFileWrapperStabilityTests: XCTestCase {
        func testBodyTextSectionsAreReadInNumericNameOrder() throws {
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

            let hwp = try bodyTextHwpFromFileWrapper(at: url)

            expect(hwp.sectionArray.map(\.rawPayload)) == Array(originalPayloads.reversed())
        }

        func testBodyTextSectionGapsThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntry: "Section1",
                to: "Section2",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectInvalidBodyTextSectionTree(
                "BodyText sections must start at Section0 and be contiguous"
            ) {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }
        }

        func testUnexpectedBodyTextChildrenThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntryAllowingLengthChange: "Section1",
                to: "Preview",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectUnexpectedBodyTextDirectoryEntry("Preview") {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }
        }

        func testDuplicateBodyTextSectionNamesThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntry: "Section1",
                to: "Section0",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Duplicate BodyText directory entry names"))
                expect(reason).to(contain("Section0"))
            })
        }

        func testMalformedBodyTextSectionNamesThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntry: "Section1",
                to: "SectionA",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectInvalidBodyTextSectionTree(
                "BodyText section name SectionA is malformed"
            ) {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }
        }

        func testMalformedNonStreamBodyTextSectionNamesThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntryAllowingLengthChange: "Section1",
                to: "SectionA",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("BodyText section name SectionA is malformed"))
            })
        }

        func testLeadingZeroBodyTextSectionNamesThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "multi-section",
                renamingEntryAllowingLengthChange: "Section1",
                to: "Section01",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("BodyText section name Section01 is malformed"))
            })
        }

        func testBodyTextDirectoryEntryMustBeStorage() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: "BodyText",
                fromType: directoryEntryOleStorageType,
                toType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'BodyText'"))
                expect(reason).to(contain("expected storage"))
            })
        }

        func testNonStreamBodyTextSectionChildrenThrowTypedError() throws {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: "plain-text-minimal",
                changingEntry: "Section0",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expect {
                _ = try bodyTextHwpFromFileWrapper(at: url)
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Directory entry 'BodyText/Section0'"))
                expect(reason).to(contain("expected stream"))
            })
        }
    }

    private func bodyTextHwpFromFileWrapper(at url: URL) throws -> HwpFile {
        let wrapper = try FileWrapper(url: url, options: [])
        return try HwpFile(fromWrapper: wrapper)
    }

    private func expectInvalidBodyTextSectionTree(
        _ expectedReason: String,
        _ expression: @escaping () throws -> Void
    ) {
        expect {
            try expression()
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain(expectedReason))
        })
    }

    private func expectUnexpectedBodyTextDirectoryEntry(
        _ entryName: String,
        _ expression: @escaping () throws -> Void
    ) {
        expect {
            try expression()
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("BodyText directory entry \(entryName) is unexpected"))
        })
    }
#endif
