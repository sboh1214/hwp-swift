@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class RequiredStreamPresenceStabilityTests: XCTestCase {
    func testMissingFileHeaderStreamThrowsTypedError() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "FileHeader",
            to: "XileHeader",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectMissingRequiredStream(.fileHeader) {
            _ = try HwpFile(fromPath: url.path)
        }
        expectMissingRequiredStream(.fileHeader) {
            _ = try HwpFileHeader.load(fromPath: url.path)
        }
    }

    func testMissingDocInfoStreamThrowsTypedError() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "DocInfo",
            to: "XocInfo",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectMissingRequiredStream(.docInfo) {
            _ = try HwpFile(fromPath: url.path)
        }
    }

    func testMissingBodyTextStorageThrowsTypedError() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "BodyText",
            to: "XodyText",
            entryType: directoryEntryOleStorageType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        expectMissingRequiredStream(.bodyText) {
            _ = try HwpFile(fromPath: url.path)
        }
    }

    func testMissingRequiredStreamsFromRepresentativeReadableFixturesThrowTypedError() throws {
        for fixtureId in [
            "plain-text-minimal",
            "multi-section",
            "BinData",
            "header-footer",
        ] {
            for testCase in missingRequiredStreamCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: fixtureId,
                    renamingEntry: testCase.entryName,
                    to: testCase.newName,
                    entryType: testCase.type
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                expectMissingRequiredStream(testCase.stream) {
                    _ = try HwpFile(fromPath: url.path)
                }
            }
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testMissingRequiredStreamsFromDataThrowTypedError() throws {
            for testCase in missingRequiredStreamCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: "plain-text-minimal",
                    renamingEntry: testCase.entryName,
                    to: testCase.newName,
                    entryType: testCase.type
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let data = try Data(contentsOf: url)
                expectMissingRequiredStream(testCase.stream) {
                    _ = try HwpFile(fromData: data)
                }
                if testCase.stream == .fileHeader {
                    expectMissingRequiredStream(.fileHeader) {
                        _ = try HwpFileHeader.load(fromData: data)
                    }
                }
            }
        }

        func testMissingRequiredStreamsFromFileWrapperThrowTypedError() throws {
            for testCase in missingRequiredStreamCases {
                let url = try temporaryDirectoryEntryHwp(
                    basedOnFixture: "plain-text-minimal",
                    renamingEntry: testCase.entryName,
                    to: testCase.newName,
                    entryType: testCase.type
                )
                defer { removeTemporaryDirectoryEntryFile(url) }

                let wrapper = try FileWrapper(url: url, options: [])
                expectMissingRequiredStream(testCase.stream) {
                    _ = try HwpFile(fromWrapper: wrapper)
                }
                if testCase.stream == .fileHeader {
                    expectMissingRequiredStream(.fileHeader) {
                        _ = try HwpFileHeader.load(fromWrapper: wrapper)
                    }
                }
            }
        }
    #endif
}

private struct MissingRequiredStreamCase {
    let entryName: String
    let newName: String
    let type: UInt8
    let stream: HwpStreamName
}

private let missingRequiredStreamCases = [
    MissingRequiredStreamCase(
        entryName: "FileHeader",
        newName: "XileHeader",
        type: directoryEntryOleStreamType,
        stream: .fileHeader
    ),
    MissingRequiredStreamCase(
        entryName: "DocInfo",
        newName: "XocInfo",
        type: directoryEntryOleStreamType,
        stream: .docInfo
    ),
    MissingRequiredStreamCase(
        entryName: "BodyText",
        newName: "XodyText",
        type: directoryEntryOleStorageType,
        stream: .bodyText
    ),
]

private func expectMissingRequiredStream(
    _ expectedName: HwpStreamName,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.streamDoesNotExist(name) = error else {
            return fail("Expected streamDoesNotExist, got \(error)")
        }
        expect(name) == expectedName
    })
}
