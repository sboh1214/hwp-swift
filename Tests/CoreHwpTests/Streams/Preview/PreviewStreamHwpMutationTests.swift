@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class PreviewStreamHwpMutationTests: XCTestCase {
    func testMalformedPreviewTextStreamInHwpThrowsTypedStringError() throws {
        let mutation = try temporaryHwp(
            basedOnFixture: "plain-text-minimal",
            mutatingRootStream: .previewText
        ) { streamData in
            guard streamData.count >= 2 else {
                throw HwpError.invalidDataLength(length: "PrvText stream is shorter than 2 bytes")
            }

            var mutated = streamData
            mutated.replaceSubrange(
                mutated.startIndex ..< mutated.startIndex + 2,
                with: [0x00, 0xD8]
            )
            return mutated
        }
        defer { removeTemporaryPreviewStreamFile(mutation.url) }

        expect {
            _ = try HwpFile(fromPath: mutation.url.path)
        }.to(throwError { error in
            assertInvalidPreviewTextError(error, mutation.mutatedStreamData)
        })
        expect {
            _ = try HwpFile(fromData: Data(contentsOf: mutation.url))
        }.to(throwError { error in
            assertInvalidPreviewTextError(error, mutation.mutatedStreamData)
        })
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            expect {
                _ = try HwpFile(fromWrapper: previewStreamWrapper(at: mutation.url))
            }.to(throwError { error in
                assertInvalidPreviewTextError(error, mutation.mutatedStreamData)
            })
        #endif
    }

    func testUnknownPreviewImageFormatInHwpPreservesRawPayload() throws {
        let mutation = try temporaryHwp(
            basedOnFixture: "plain-text-minimal",
            mutatingRootStream: .previewImage
        ) { streamData in
            guard !streamData.isEmpty else {
                throw HwpError.invalidDataLength(length: "PrvImage stream is empty")
            }

            var mutated = streamData
            mutated[mutated.startIndex] = 0x00
            return mutated
        }
        defer { removeTemporaryPreviewStreamFile(mutation.url) }

        let hwp = try HwpFile(fromPath: mutation.url.path)

        expect(hwp.previewImage.format) == HwpPreviewImageFormat.unknown
        expect(hwp.previewImage.rawPayload) == mutation.mutatedStreamData
        expect(hwp.previewImage.image) == mutation.mutatedStreamData
        expect(hwp.previewImage.rawPayload.count) == mutation.originalStreamData.count
        expect(Array(hwp.previewImage.rawPayload.prefix(4))) == Array(
            mutation.mutatedStreamData.prefix(4)
        )
        let dataHwp = try HwpFile(fromData: Data(contentsOf: mutation.url))

        expect(dataHwp.previewImage.format) == HwpPreviewImageFormat.unknown
        expect(dataHwp.previewImage.rawPayload) == mutation.mutatedStreamData
        expect(dataHwp.previewImage.image) == mutation.mutatedStreamData
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let wrapperHwp = try HwpFile(fromWrapper: previewStreamWrapper(at: mutation.url))

            expect(wrapperHwp.previewImage.format) == HwpPreviewImageFormat.unknown
            expect(wrapperHwp.previewImage.rawPayload) == mutation.mutatedStreamData
            expect(wrapperHwp.previewImage.image) == mutation.mutatedStreamData
        #endif
    }

    func testUnknownPreviewImageFormatInHwpSurvivesCodableRoundTrip() throws {
        let mutation = try temporaryHwp(
            basedOnFixture: "plain-text-minimal",
            mutatingRootStream: .previewImage
        ) { streamData in
            guard !streamData.isEmpty else {
                throw HwpError.invalidDataLength(length: "PrvImage stream is empty")
            }

            var mutated = streamData
            mutated[mutated.startIndex] = 0x00
            return mutated
        }
        defer { removeTemporaryPreviewStreamFile(mutation.url) }
        let hwp = try HwpFile(fromPath: mutation.url.path)

        let encoded = try JSONEncoder().encode(hwp)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

        expect(decoded.previewImage.format) == HwpPreviewImageFormat.unknown
        expect(decoded.previewImage.rawPayload) == mutation.mutatedStreamData
        expect(decoded.previewImage.image) == mutation.mutatedStreamData
        expect(decoded.previewImage.rawPayload.count) == mutation.originalStreamData.count
    }
}

private func assertInvalidPreviewTextError(_ error: Error, _ expectedData: Data) {
    guard case let HwpError.invalidDataForString(data, name) = error else {
        return fail("Expected invalidDataForString, got \(error)")
    }
    expect(name) == "PreviewText"
    expect(data) == expectedData
    expect(Array(data.prefix(2))) == [0x00, 0xD8]
}

private struct PreviewStreamMutation {
    let url: URL
    let originalStreamData: Data
    let mutatedStreamData: Data
}

private func temporaryHwp(
    basedOnFixture fixture: String,
    mutatingRootStream streamName: HwpStreamName,
    mutation: (Data) throws -> Data
) throws -> PreviewStreamMutation {
    let sourceURL = hwpURL(#file, fixture)
    let originalStreamData = try rootStreamData(named: streamName, in: sourceURL)
    let mutatedStreamData = try mutation(originalStreamData)
    guard originalStreamData.count == mutatedStreamData.count else {
        throw HwpError.invalidDataLength(
            length: "\(streamName.rawValue) mutation changed stream length"
        )
    }

    var fileData = try Data(contentsOf: sourceURL)
    let range = try uniqueContiguousRange(
        of: originalStreamData,
        in: fileData,
        streamDescription: streamName.rawValue
    )
    fileData.replaceSubrange(range, with: mutatedStreamData)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreHwp-\(UUID().uuidString).hwp")
    try fileData.write(to: url, options: .atomic)
    return PreviewStreamMutation(
        url: url,
        originalStreamData: originalStreamData,
        mutatedStreamData: mutatedStreamData
    )
}

private func rootStreamData(named streamName: HwpStreamName, in url: URL) throws -> Data {
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

private func removeTemporaryPreviewStreamFile(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("Failed to remove temporary file: \(error)")
    }
}

#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    private func previewStreamWrapper(at url: URL) throws -> FileWrapper {
        try FileWrapper(url: url, options: [])
    }
#endif
