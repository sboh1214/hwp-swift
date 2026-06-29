@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class UnsupportedFeaturePrecedenceTests: XCTestCase {
    func testUnsupportedFilesRejectBeforeValidatingDocInfoEntryType() throws {
        let cases = try unsupportedFixtureCases()

        for testCase in cases {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: testCase.fixtureId,
                changingEntry: "DocInfo",
                fromType: directoryEntryOleStreamType,
                toType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectUnsupportedFeature(url, expectedFeature: testCase.expectedFeature)
        }
    }

    func testUnsupportedFilesRejectBeforeValidatingBodyTextEntryType() throws {
        let cases = try unsupportedFixtureCases()

        for testCase in cases {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: testCase.fixtureId,
                changingEntry: "BodyText",
                fromType: directoryEntryOleStorageType,
                toType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectUnsupportedFeature(url, expectedFeature: testCase.expectedFeature)
        }
    }

    func testUnsupportedFilesRejectBeforeCheckingMissingDocInfoStream() throws {
        let cases = try unsupportedFixtureCases()

        for testCase in cases {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: testCase.fixtureId,
                renamingEntry: "DocInfo",
                to: "XocInfo",
                entryType: directoryEntryOleStreamType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectUnsupportedFeature(url, expectedFeature: testCase.expectedFeature)
        }
    }

    func testUnsupportedFilesRejectBeforeCheckingMissingBodyTextStorage() throws {
        let cases = try unsupportedFixtureCases()

        for testCase in cases {
            let url = try temporaryDirectoryEntryHwp(
                basedOnFixture: testCase.fixtureId,
                renamingEntry: "BodyText",
                to: "XodyText",
                entryType: directoryEntryOleStorageType
            )
            defer { removeTemporaryDirectoryEntryFile(url) }

            expectUnsupportedFeature(url, expectedFeature: testCase.expectedFeature)
        }
    }

    func testUnsupportedDocInfoRawRecordHelperRejectsDuplicateRootEntries() throws {
        let fixture = try FixtureLoader.load(id: "배포용문서")
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: fixture.manifest.id,
            renamingEntryAllowingLengthChange: "PrvText",
            to: "DocInfo",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let fileHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)
        expect {
            try FixtureAssertions.assertUnsupportedDocInfoRawRecords(
                fixture.manifest.expectations,
                url,
                fileHeader
            )
        }.to(throwError { error in
            guard case let HwpError.invalidOLEFile(reason) = error else {
                return fail("Expected invalidOLEFile, got \(error)")
            }
            expect(reason).to(contain("Duplicate root directory entry names"))
            expect(reason).to(contain("DocInfo"))
        })
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testUnsupportedFileWrappersRejectBeforeValidatingDocInfoEntryType() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    changingEntry: "DocInfo",
                    fromType: directoryEntryOleStreamType,
                    toType: directoryEntryOleStorageType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let wrapper = try FileWrapper(url: url, options: [])
                expectUnsupportedFeature(wrapper, expectedFeature: testCase.expectedFeature)
            }
        }

        func testUnsupportedFileWrappersRejectBeforeValidatingBodyTextEntryType() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    changingEntry: "BodyText",
                    fromType: directoryEntryOleStorageType,
                    toType: directoryEntryOleStreamType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let wrapper = try FileWrapper(url: url, options: [])
                expectUnsupportedFeature(wrapper, expectedFeature: testCase.expectedFeature)
            }
        }

        func testUnsupportedFileWrappersRejectBeforeCheckingMissingDocInfoStream() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    renamingEntry: "DocInfo",
                    to: "XocInfo",
                    entryType: directoryEntryOleStreamType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let wrapper = try FileWrapper(url: url, options: [])
                expectUnsupportedFeature(wrapper, expectedFeature: testCase.expectedFeature)
            }
        }

        func testUnsupportedFileWrappersRejectBeforeCheckingMissingBodyTextStorage() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: testCase.fixtureId,
                    renamingEntry: "BodyText",
                    to: "XodyText",
                    entryType: directoryEntryOleStorageType
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let wrapper = try FileWrapper(url: url, options: [])
                expectUnsupportedFeature(wrapper, expectedFeature: testCase.expectedFeature)
            }
        }

        func testUnsupportedDataRejectBeforeValidatingRequiredEntryTypes() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                for mutation in unsupportedRequiredEntryTypeMutations {
                    let url = try temporaryDirectoryEntryHwp(
                        basedOnFixture: testCase.fixtureId,
                        changingEntry: mutation.entryName,
                        fromType: mutation.fromType,
                        toType: mutation.toType
                    )
                    defer { removeTemporaryDirectoryEntryFile(url) }

                    let data = try Data(contentsOf: url)
                    expectUnsupportedFeature(data, expectedFeature: testCase.expectedFeature)
                }
            }
        }

        func testUnsupportedDataRejectBeforeCheckingMissingRequiredEntries() throws {
            let cases = try unsupportedFixtureCases()

            for testCase in cases {
                for mutation in unsupportedMissingRequiredEntryMutations {
                    let url = try temporaryDirectoryEntryHwp(
                        basedOnFixture: testCase.fixtureId,
                        renamingEntry: mutation.entryName,
                        to: mutation.newName,
                        entryType: mutation.entryType
                    )
                    defer { removeTemporaryDirectoryEntryFile(url) }

                    let data = try Data(contentsOf: url)
                    expectUnsupportedFeature(data, expectedFeature: testCase.expectedFeature)
                }
            }
        }
    #endif
}

private struct UnsupportedFixtureCase {
    let fixtureId: String
    let expectedFeature: HwpUnsupportedFeature
}

private struct UnsupportedEntryTypeMutation {
    let entryName: String
    let fromType: UInt8
    let toType: UInt8
}

private struct UnsupportedMissingEntryMutation {
    let entryName: String
    let newName: String
    let entryType: UInt8
}

private let unsupportedRequiredEntryTypeMutations = [
    UnsupportedEntryTypeMutation(
        entryName: "DocInfo",
        fromType: directoryEntryOleStreamType,
        toType: directoryEntryOleStorageType
    ),
    UnsupportedEntryTypeMutation(
        entryName: "BodyText",
        fromType: directoryEntryOleStorageType,
        toType: directoryEntryOleStreamType
    ),
]

private let unsupportedMissingRequiredEntryMutations = [
    UnsupportedMissingEntryMutation(
        entryName: "DocInfo",
        newName: "XocInfo",
        entryType: directoryEntryOleStreamType
    ),
    UnsupportedMissingEntryMutation(
        entryName: "BodyText",
        newName: "XodyText",
        entryType: directoryEntryOleStorageType
    ),
]

private func unsupportedFixtureCases() throws -> [UnsupportedFixtureCase] {
    let cases = try FixtureLoader.loadAll().compactMap { fixture -> UnsupportedFixtureCase? in
        guard let expectedError = fixture.manifest.expectedError else {
            return nil
        }
        return UnsupportedFixtureCase(
            fixtureId: fixture.manifest.id,
            expectedFeature: try expectedFeature(from: expectedError)
        )
    }

    expect(cases).notTo(beEmpty())
    return cases
}

private func expectedFeature(from expectedError: FixtureExpectedError) throws
    -> HwpUnsupportedFeature
{
    switch expectedError.code {
    case "unsupportedFeature.encryptedDocument":
        return .encryptedDocument
    case "unsupportedFeature.deploymentDocument":
        return .deploymentDocument
    case "unsupportedFeature.drmDocument":
        return .drmDocument
    default:
        throw HwpError.invalidDataForString(
            data: Data(expectedError.code.utf8),
            name: "expectedError.code"
        )
    }
}

private func expectUnsupportedFeature(
    _ url: URL,
    expectedFeature: HwpUnsupportedFeature
) {
    expect {
        _ = try HwpFile(fromPath: url.path)
    }.to(throwError { error in
        guard case let HwpError.unsupportedFeature(feature) = error else {
            return fail("Expected unsupportedFeature, got \(error)")
        }
        expect(feature) == expectedFeature
    })
}

#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    private func expectUnsupportedFeature(
        _ data: Data,
        expectedFeature: HwpUnsupportedFeature
    ) {
        expect {
            _ = try HwpFile(fromData: data)
        }.to(throwError { error in
            guard case let HwpError.unsupportedFeature(feature) = error else {
                return fail("Expected unsupportedFeature, got \(error)")
            }
            expect(feature) == expectedFeature
        })
    }

    private func expectUnsupportedFeature(
        _ wrapper: FileWrapper,
        expectedFeature: HwpUnsupportedFeature
    ) {
        expect {
            _ = try HwpFile(fromWrapper: wrapper)
        }.to(throwError { error in
            guard case let HwpError.unsupportedFeature(feature) = error else {
                return fail("Expected unsupportedFeature, got \(error)")
            }
            expect(feature) == expectedFeature
        })
    }
#endif
