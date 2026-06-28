@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class FileHeaderHwpMutationTests: XCTestCase {
    func testInvalidFileHeaderSignatureInHwpThrowsTypedError() throws {
        let mutation = try temporaryFileHeaderHwp(basedOnFixture: "plain-text-minimal") { data in
            guard !data.isEmpty else {
                throw HwpError.invalidDataLength(length: "FileHeader stream is empty")
            }

            var mutated = data
            mutated[mutated.startIndex] = 0x00
            return mutated
        }
        defer { removeTemporaryFileHeaderMutationFile(mutation.url) }

        expectInvalidFileHeaderSignature {
            _ = try HwpFile(fromPath: mutation.url.path)
        }
        expectInvalidFileHeaderSignature {
            _ = try HwpFileHeader.load(fromPath: mutation.url.path)
        }
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let data = try Data(contentsOf: mutation.url)
            expectInvalidFileHeaderSignature {
                _ = try HwpFile(fromData: data)
            }
            expectInvalidFileHeaderSignature {
                _ = try HwpFileHeader.load(fromData: data)
            }
            expectInvalidFileHeaderSignature {
                _ = try HwpFile(fromWrapper: fileHeaderWrapper(at: mutation.url))
            }
            expectInvalidFileHeaderSignature {
                _ = try HwpFileHeader.load(fromWrapper: fileHeaderWrapper(at: mutation.url))
            }
        #endif
        expect(mutation.mutatedStreamData.count) == mutation.originalStreamData.count
    }

    func testNonASCIIFileHeaderSignatureInHwpThrowsTypedStringError() throws {
        let mutation = try temporaryFileHeaderHwp(basedOnFixture: "plain-text-minimal") { data in
            guard !data.isEmpty else {
                throw HwpError.invalidDataLength(length: "FileHeader stream is empty")
            }

            var mutated = data
            mutated[mutated.startIndex] = 0xFF
            return mutated
        }
        defer { removeTemporaryFileHeaderMutationFile(mutation.url) }

        expectInvalidFileHeaderSignatureStringData {
            _ = try HwpFile(fromPath: mutation.url.path)
        }
        expectInvalidFileHeaderSignatureStringData {
            _ = try HwpFileHeader.load(fromPath: mutation.url.path)
        }
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let data = try Data(contentsOf: mutation.url)
            expectInvalidFileHeaderSignatureStringData {
                _ = try HwpFile(fromData: data)
            }
            expectInvalidFileHeaderSignatureStringData {
                _ = try HwpFileHeader.load(fromData: data)
            }
            expectInvalidFileHeaderSignatureStringData {
                _ = try HwpFile(fromWrapper: fileHeaderWrapper(at: mutation.url))
            }
            expectInvalidFileHeaderSignatureStringData {
                _ = try HwpFileHeader.load(fromWrapper: fileHeaderWrapper(at: mutation.url))
            }
        #endif
        expect(mutation.mutatedStreamData.count) == mutation.originalStreamData.count
    }

    func testUnsupportedFilePropertyBitsInHwpThrowUnsupportedFeature() throws {
        let cases: [(bitIndex: UInt8, expectedFeature: HwpUnsupportedFeature)] = [
            (1, .encryptedDocument),
            (2, .deploymentDocument),
            (4, .drmDocument),
            (8, .encryptedDocument),
            (10, .drmDocument),
        ]

        for testCase in cases {
            let mutation = try temporaryFileHeaderHwp(
                basedOnFixture: "plain-text-minimal",
                settingFilePropertyBit: testCase.bitIndex
            )
            defer { removeTemporaryFileHeaderMutationFile(mutation.url) }

            let header = try HwpFileHeader.load(fromPath: mutation.url.path)

            expect(header.fileProperty.unsupportedFeature) == testCase.expectedFeature
            #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
                let data = try Data(contentsOf: mutation.url)
                let dataHeader = try HwpFileHeader.load(fromData: data)
                expect(dataHeader.fileProperty.unsupportedFeature) ==
                    testCase.expectedFeature

                let wrapperHeader = try HwpFileHeader.load(
                    fromWrapper: fileHeaderWrapper(at: mutation.url)
                )
                expect(wrapperHeader.fileProperty.unsupportedFeature) ==
                    testCase.expectedFeature
            #endif
            expectUnsupportedFeature(testCase.expectedFeature) {
                _ = try HwpFile(fromPath: mutation.url.path)
            }
            #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
                expectUnsupportedFeature(testCase.expectedFeature) {
                    _ = try HwpFile(fromData: data)
                }
                expectUnsupportedFeature(testCase.expectedFeature) {
                    _ = try HwpFile(fromWrapper: fileHeaderWrapper(at: mutation.url))
                }
            #endif
        }
    }

    func testUnsupportedFilePropertyBitCombinationsUseStablePrecedence() throws {
        let cases: [(bitIndices: [UInt8], expectedFeature: HwpUnsupportedFeature)] = [
            ([2, 4], .deploymentDocument),
            ([1, 2, 4], .encryptedDocument),
            ([8, 2, 10], .encryptedDocument),
            ([4, 10], .drmDocument),
        ]

        for testCase in cases {
            let mutation = try temporaryFileHeaderHwp(
                basedOnFixture: "plain-text-minimal",
                settingFilePropertyBits: testCase.bitIndices
            )
            defer { removeTemporaryFileHeaderMutationFile(mutation.url) }

            let header = try HwpFileHeader.load(fromPath: mutation.url.path)

            expect(header.fileProperty.unsupportedFeature) == testCase.expectedFeature
            #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
                let data = try Data(contentsOf: mutation.url)
                let dataHeader = try HwpFileHeader.load(fromData: data)
                expect(dataHeader.fileProperty.unsupportedFeature) ==
                    testCase.expectedFeature

                let wrapperHeader = try HwpFileHeader.load(
                    fromWrapper: fileHeaderWrapper(at: mutation.url)
                )
                expect(wrapperHeader.fileProperty.unsupportedFeature) ==
                    testCase.expectedFeature
            #endif
            expectUnsupportedFeature(testCase.expectedFeature) {
                _ = try HwpFile(fromPath: mutation.url.path)
            }
            #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
                expectUnsupportedFeature(testCase.expectedFeature) {
                    _ = try HwpFile(fromData: data)
                }
                expectUnsupportedFeature(testCase.expectedFeature) {
                    _ = try HwpFile(fromWrapper: fileHeaderWrapper(at: mutation.url))
                }
            #endif
        }
    }

    func testClearedCompressedBitInCompressedHwpThrowsTypedParsingError() throws {
        let mutation = try temporaryFileHeaderHwp(
            basedOnFixture: "plain-text-minimal",
            clearingFilePropertyBit: 0
        )
        defer { removeTemporaryFileHeaderMutationFile(mutation.url) }

        let header = try HwpFileHeader.load(fromPath: mutation.url.path)

        expect(header.fileProperty.isCompressed) == false
        expect {
            _ = try HwpFile(fromPath: mutation.url.path)
        }.to(throwError { error in
            guard let hwpError = error as? HwpError else {
                return fail("Expected typed HwpError, got \(error)")
            }
            expect(isExpectedCompressionFlagMismatchError(hwpError)) == true
        })
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let data = try Data(contentsOf: mutation.url)
            let dataHeader = try HwpFileHeader.load(fromData: data)
            expect(dataHeader.fileProperty.isCompressed) == false

            expect {
                _ = try HwpFile(fromData: data)
            }.to(throwError { error in
                guard let hwpError = error as? HwpError else {
                    return fail("Expected typed HwpError, got \(error)")
                }
                expect(isExpectedCompressionFlagMismatchError(hwpError)) == true
            })
            expect {
                _ = try HwpFile(fromWrapper: fileHeaderWrapper(at: mutation.url))
            }.to(throwError { error in
                guard let hwpError = error as? HwpError else {
                    return fail("Expected typed HwpError, got \(error)")
                }
                expect(isExpectedCompressionFlagMismatchError(hwpError)) == true
            })
        #endif
    }
}

private struct FileHeaderHwpMutation {
    let url: URL
    let originalStreamData: Data
    let mutatedStreamData: Data
}

private func temporaryFileHeaderHwp(
    basedOnFixture fixture: String,
    mutation: (Data) throws -> Data
) throws -> FileHeaderHwpMutation {
    let sourceURL = hwpURL(#file, fixture)
    let originalStreamData = try fileHeaderStreamData(in: sourceURL)
    let mutatedStreamData = try mutation(originalStreamData)
    guard originalStreamData.count == mutatedStreamData.count else {
        throw HwpError.invalidDataLength(length: "FileHeader mutation changed stream length")
    }

    var fileData = try Data(contentsOf: sourceURL)
    let range = try uniqueFileHeaderRange(of: originalStreamData, in: fileData)
    fileData.replaceSubrange(range, with: mutatedStreamData)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreHwp-\(UUID().uuidString).hwp")
    try fileData.write(to: url, options: .atomic)
    return FileHeaderHwpMutation(
        url: url,
        originalStreamData: originalStreamData,
        mutatedStreamData: mutatedStreamData
    )
}

private func temporaryFileHeaderHwp(
    basedOnFixture fixture: String,
    settingFilePropertyBit bitIndex: UInt8
) throws -> FileHeaderHwpMutation {
    try temporaryFileHeaderHwp(basedOnFixture: fixture, settingFilePropertyBits: [bitIndex])
}

private func temporaryFileHeaderHwp(
    basedOnFixture fixture: String,
    settingFilePropertyBits bitIndices: [UInt8]
) throws -> FileHeaderHwpMutation {
    try temporaryFileHeaderHwp(basedOnFixture: fixture) { data in
        var mutated = data
        for bitIndex in bitIndices {
            let byteOffset = try filePropertyByteOffset(for: bitIndex, in: mutated)
            let bitMask = UInt8(1 << (bitIndex % 8))
            mutated[byteOffset] |= bitMask
        }
        return mutated
    }
}

private func temporaryFileHeaderHwp(
    basedOnFixture fixture: String,
    clearingFilePropertyBit bitIndex: UInt8
) throws -> FileHeaderHwpMutation {
    try temporaryFileHeaderHwp(basedOnFixture: fixture) { data in
        var mutated = data
        let byteOffset = try filePropertyByteOffset(for: bitIndex, in: mutated)
        let bitMask = UInt8(1 << (bitIndex % 8))
        mutated[byteOffset] &= ~bitMask
        return mutated
    }
}

private func filePropertyByteOffset(for bitIndex: UInt8, in data: Data) throws -> Int {
    let filePropertyOffset = 32 + 4
    guard data.count >= filePropertyOffset + MemoryLayout<UInt32>.size else {
        throw HwpError.truncatedData(
            expected: filePropertyOffset + MemoryLayout<UInt32>.size,
            actual: data.count
        )
    }
    return filePropertyOffset + Int(bitIndex / 8)
}

private func fileHeaderStreamData(in url: URL) throws -> Data {
    let ole: OLEFile
    do {
        ole = try OLEFile(url.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    guard let stream = ole.root.children.first(where: {
        $0.name == HwpStreamName.fileHeader.rawValue
    }) else {
        throw HwpError.streamDoesNotExist(name: .fileHeader)
    }

    do {
        return try ole.stream(stream).readDataToEnd()
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
}

private func uniqueFileHeaderRange(
    of streamData: Data,
    in data: Data
) throws -> Range<Data.Index> {
    guard let range = data.range(of: streamData) else {
        throw HwpError.invalidOLEFile(reason: "FileHeader stream bytes were not found")
    }

    let remainingRange = range.upperBound ..< data.endIndex
    guard data.range(of: streamData, options: [], in: remainingRange) == nil else {
        throw HwpError.invalidOLEFile(reason: "FileHeader stream bytes were found more than once")
    }

    return range
}

private func expectInvalidFileHeaderSignature(_ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidFileHeaderSignature(signature) = error else {
            return fail("Expected invalidFileHeaderSignature, got \(error)")
        }
        expect(signature.hasPrefix("\0WP Document File")) == true
    })
}

private func expectInvalidFileHeaderSignatureStringData(
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidDataForString(data, name) = error else {
            return fail("Expected invalidDataForString, got \(error)")
        }
        expect(data.count) == 32
        expect(data.first) == 0xFF
        expect(name) == "signature"
    })
}

private func expectUnsupportedFeature(
    _ expectedFeature: HwpUnsupportedFeature,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.unsupportedFeature(feature) = error else {
            return fail("Expected unsupportedFeature, got \(error)")
        }
        expect(feature) == expectedFeature
    })
}

private func isExpectedCompressionFlagMismatchError(_ error: HwpError) -> Bool {
    switch error {
    case .truncatedData,
         .invalidRecordTree,
         .recordDoesNotExist,
         .bytesAreNotEOF,
         .invalidRawValueForEnum,
         .unidentifiedTag,
         .invalidDataLength:
        true
    default:
        false
    }
}

private func removeTemporaryFileHeaderMutationFile(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("Failed to remove temporary file: \(error)")
    }
}

#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    private func fileHeaderWrapper(at url: URL) throws -> FileWrapper {
        try FileWrapper(url: url, options: [])
    }
#endif
