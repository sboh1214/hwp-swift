@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class StreamDecompressionStabilityTests: XCTestCase {
    func testCompressedStreamInputLimitThrowsTypedError() {
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: 0,
            maxDecompressedStreamBytes: .max
        )

        expectStreamSizeLimitExceeded(.docInfo, limit: 0) {
            _ = try HwpFile(
                fromPath: hwpURL(#file, "plain-text-minimal").path,
                readLimits: limits
            )
        }
    }

    func testCompressedStreamOutputLimitThrowsTypedError() {
        let limit = 256
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: .max,
            maxDecompressedStreamBytes: limit
        )

        expectStreamSizeLimitExceeded(.docInfo, limit: limit) {
            _ = try HwpFile(
                fromPath: hwpURL(#file, "plain-text-minimal").path,
                readLimits: limits
            )
        }
    }

    func testCorruptedCompressedDocInfoStreamThrowsTypedDecompressError() throws {
        let url = try temporaryHwp(
            basedOnFixture: "plain-text-minimal",
            corruptingCompressedRootStream: .docInfo
        )
        defer { removeTemporaryFile(url) }

        expectStreamDecompressFailed(.docInfo) {
            _ = try HwpFile(fromPath: url.path)
        }
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testCorruptedCompressedStreamsFromDataThrowTypedErrors() throws {
            let cases = [
                StreamDecompressionDataCase(
                    mutation: {
                        try temporaryHwp(
                            basedOnFixture: "plain-text-minimal",
                            corruptingCompressedRootStream: .docInfo
                        )
                    },
                    streamName: .docInfo
                ),
                StreamDecompressionDataCase(
                    mutation: {
                        try temporaryHwp(
                            basedOnFixture: "plain-text-minimal",
                            corruptingCompressedStorageStream: "Section0",
                            in: .bodyText
                        )
                    },
                    streamName: .bodyText
                ),
                StreamDecompressionDataCase(
                    mutation: {
                        try temporaryHwp(
                            basedOnFixture: "multi-section",
                            corruptingCompressedStorageStream: "Section1",
                            in: .bodyText
                        )
                    },
                    streamName: .bodyText
                ),
            ]

            for testCase in cases {
                let url = try testCase.mutation()
                defer { removeTemporaryFile(url) }

                let data = try Data(contentsOf: url)
                expectStreamDecompressFailed(testCase.streamName) {
                    _ = try HwpFile(fromData: data)
                }
            }
        }

        func testCorruptedCompressedDocInfoStreamFromFileWrapperThrowsTypedError() throws {
            let url = try temporaryHwp(
                basedOnFixture: "plain-text-minimal",
                corruptingCompressedRootStream: .docInfo
            )
            defer { removeTemporaryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])
            expectStreamDecompressFailed(.docInfo) {
                _ = try HwpFile(fromWrapper: wrapper)
            }
        }
    #endif

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testCorruptedCompressedBodyTextSectionFromFileWrapperThrowsTypedError() throws {
            let url = try temporaryHwp(
                basedOnFixture: "plain-text-minimal",
                corruptingCompressedStorageStream: "Section0",
                in: .bodyText
            )
            defer { removeTemporaryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])
            expectStreamDecompressFailed(.bodyText) {
                _ = try HwpFile(fromWrapper: wrapper)
            }
        }
    #endif

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testCorruptedCompressedLaterBodyTextSectionFromFileWrapperThrowsTypedError() throws {
            let url = try temporaryHwp(
                basedOnFixture: "multi-section",
                corruptingCompressedStorageStream: "Section1",
                in: .bodyText
            )
            defer { removeTemporaryFile(url) }

            let wrapper = try FileWrapper(url: url, options: [])
            expectStreamDecompressFailed(.bodyText) {
                _ = try HwpFile(fromWrapper: wrapper)
            }
        }
    #endif

    func testCorruptedCompressedBodyTextSectionThrowsTypedDecompressError() throws {
        let url = try temporaryHwp(
            basedOnFixture: "plain-text-minimal",
            corruptingCompressedStorageStream: "Section0",
            in: .bodyText
        )
        defer { removeTemporaryFile(url) }

        expectStreamDecompressFailed(.bodyText) {
            _ = try HwpFile(fromPath: url.path)
        }
    }

    func testCorruptedCompressedLaterBodyTextSectionThrowsTypedDecompressError() throws {
        let url = try temporaryHwp(
            basedOnFixture: "multi-section",
            corruptingCompressedStorageStream: "Section1",
            in: .bodyText
        )
        defer { removeTemporaryFile(url) }

        expectStreamDecompressFailed(.bodyText) {
            _ = try HwpFile(fromPath: url.path)
        }
    }
}

#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    private struct StreamDecompressionDataCase {
        let mutation: () throws -> URL
        let streamName: HwpStreamName
    }
#endif

private func expectStreamDecompressFailed(
    _ expectedName: HwpStreamName,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.streamDecompressFailed(name) = error else {
            return fail("Expected streamDecompressFailed, got \(error)")
        }
        expect(name) == expectedName
    })
}

private func expectStreamSizeLimitExceeded(
    _ expectedName: HwpStreamName,
    limit: Int,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.streamSizeLimitExceeded(name, actualLimit, actual) = error else {
            return fail("Expected streamSizeLimitExceeded, got \(error)")
        }
        expect(name) == expectedName
        expect(actualLimit) == limit
        expect(actual) > limit
    })
}

private func temporaryHwp(
    basedOnFixture fixture: String,
    corruptingCompressedRootStream streamName: HwpStreamName
) throws -> URL {
    let sourceURL = hwpURL(#file, fixture)
    let streamData = try compressedRootStreamData(named: streamName, in: sourceURL)
    return try temporaryHwp(
        basedOn: sourceURL,
        corruptingCompressedStreamData: streamData,
        streamDescription: streamName.rawValue
    )
}

private func temporaryHwp(
    basedOnFixture fixture: String,
    corruptingCompressedStorageStream streamName: String,
    in storageName: HwpStreamName
) throws -> URL {
    let sourceURL = hwpURL(#file, fixture)
    let streamData = try compressedStorageStreamData(
        named: streamName,
        inStorage: storageName,
        in: sourceURL
    )
    return try temporaryHwp(
        basedOn: sourceURL,
        corruptingCompressedStreamData: streamData,
        streamDescription: "\(storageName.rawValue)/\(streamName)"
    )
}

private func temporaryHwp(
    basedOn sourceURL: URL,
    corruptingCompressedStreamData streamData: Data,
    streamDescription: String
) throws -> URL {
    var data = try Data(contentsOf: sourceURL)
    let range = try uniqueContiguousRange(
        of: streamData,
        in: data,
        streamDescription: streamDescription
    )
    guard !range.isEmpty else {
        throw HwpError.invalidDataLength(length: "empty \(streamDescription) stream")
    }

    data[range.lowerBound] = streamData[streamData.startIndex] == 0x06 ? 0x07 : 0x06

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreHwp-\(UUID().uuidString).hwp")
    try data.write(to: url, options: .atomic)
    return url
}

private func uniqueContiguousRange(
    of streamData: Data,
    in data: Data,
    streamDescription: String
) throws -> Range<Data.Index> {
    guard let range = data.range(of: streamData) else {
        throw HwpError.invalidOLEFile(
            reason: "\(streamDescription) stream bytes were not found as a contiguous range"
        )
    }

    let remainingRange = range.upperBound ..< data.endIndex
    guard data.range(of: streamData, options: [], in: remainingRange) == nil else {
        throw HwpError.invalidOLEFile(
            reason: "\(streamDescription) stream bytes were found more than once"
        )
    }

    return range
}

private func compressedRootStreamData(named streamName: HwpStreamName, in url: URL) throws -> Data {
    let ole: OLEFile
    do {
        ole = try OLEFile(url.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    guard let stream = ole.root.children.first(where: { $0.name == streamName.rawValue }) else {
        throw HwpError.streamDoesNotExist(name: streamName)
    }

    do {
        return try ole.stream(stream).readDataToEnd()
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
}

private func compressedStorageStreamData(
    named streamName: String,
    inStorage storageName: HwpStreamName,
    in url: URL
) throws -> Data {
    let ole: OLEFile
    do {
        ole = try OLEFile(url.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    guard let storage = ole.root.children.first(where: { $0.name == storageName.rawValue }) else {
        throw HwpError.streamDoesNotExist(name: storageName)
    }
    guard let stream = storage.children.first(where: { $0.name == streamName }) else {
        throw HwpError.streamDoesNotExist(name: storageName)
    }

    do {
        return try ole.stream(stream).readDataToEnd()
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
}

private func removeTemporaryFile(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("Failed to remove temporary file: \(error)")
    }
}
