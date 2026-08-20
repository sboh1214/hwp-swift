@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class StreamDecompressionStabilityTests: XCTestCase {
    func testCompressedStreamInputLimitThrowsTypedError() {
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: 1,
            maxDecompressedStreamBytes: .max
        )

        expectStreamSizeLimitExceeded(.docInfo, limit: 1) {
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

    func testUncompressedStreamLimitThrowsTypedErrorBeforeReadingFileHeader() {
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: .max,
            maxDecompressedStreamBytes: 1
        )

        expectStreamSizeLimitExceeded(.fileHeader, limit: 1) {
            _ = try HwpFile(
                fromPath: hwpURL(#file, "plain-text-minimal").path,
                readLimits: limits
            )
        }
    }

    func testAggregateStreamLimitThrowsTypedError() {
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: .max,
            maxDecompressedStreamBytes: .max,
            maxAggregateStreamBytes: 16
        )

        expect {
            _ = try HwpFile(
                fromPath: hwpURL(#file, "plain-text-minimal").path,
                readLimits: limits
            )
        }.to(throwError { error in
            guard case let HwpError.aggregateStreamSizeLimitExceeded(name, limit, actual) = error
            else {
                return fail("Expected aggregateStreamSizeLimitExceeded, got \(error)")
            }
            expect(name) == HwpStreamName.fileHeader
            expect(limit) == 16
            expect(actual) > 16
        })
    }

    /// ViewText 자식 수가 구역 수와 일치하는 정상 문서는 표시 본문으로 채택된다
    /// — 초과/부족 자식을 압축 해제 전에 거부하는 검증(R69 #2)이 정상 파일을
    /// 빈 ViewText로 폴백시키지 않는다.
    func testValidViewTextStorageIsStillAdopted() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "track-changes").path)

        expect(hwp.viewSectionArray).toNot(beEmpty())
        expect(hwp.viewSectionArray.count) == hwp.sectionArray.count
        expect(hwp.displaySectionArray.count) == hwp.sectionArray.count
    }

    /// 거부 측 경계 (#67): 실제 OLE의 ViewText storage에 기대 자식 수가
    /// 어긋나면 **압축 해제 전에** typed invalidRecordTree로 거부된다 —
    /// 초과분을 잘라 내면 손상/stale ViewText가 유효한 BodyText를 대체하므로
    /// (`StreamReader.getOptionalNamedDataFromStorage`의 R69 #2 검증). 일치
    /// 기대치는 통과해 경계 검증이 공허하지 않음을 함께 고정한다.
    func testViewTextStorageChildCountMismatchIsRejectedBeforeDecompression() throws {
        let url = hwpURL(#file, "track-changes")
        let hwp = try HwpFile(fromPath: url.path)
        let sectionCount = hwp.sectionArray.count
        let isCompressed = hwp.fileHeader.fileProperty.isCompressed
        let ole = try OLEFile(url.path)
        let reader = StreamReader(
            ole,
            try StreamReader.rootStreams(from: ole.root.children)
        )

        for wrongCount in [sectionCount - 1, sectionCount + 1] {
            expect {
                _ = try reader.getOptionalNamedDataFromStorage(
                    .viewText, isCompressed, expectedChildCount: wrongCount
                )
            }.to(throwError { error in
                guard case let HwpError.invalidRecordTree(reason) = error else {
                    return fail("Expected invalidRecordTree, got \(error)")
                }
                expect(reason).to(contain("ViewText child count"))
                expect(reason).to(contain("!= \(wrongCount)"))
            })
        }

        let adopted = try reader.getOptionalNamedDataFromStorage(
            .viewText, isCompressed, expectedChildCount: sectionCount
        )
        expect(adopted.count) == sectionCount
    }

    func testReadLimitsRejectNonPositiveValuesWithTypedError() {
        let cases = [
            HwpReadLimits(maxCompressedStreamBytes: 0),
            HwpReadLimits(maxDecompressedStreamBytes: 0),
            HwpReadLimits(maxAggregateStreamBytes: 0),
            HwpReadLimits(maxCompressedStreamBytes: -1),
            HwpReadLimits(maxDecompressedStreamBytes: -1),
            HwpReadLimits(maxAggregateStreamBytes: -1),
            HwpReadLimits(maxNestingDepth: 0),
            HwpReadLimits(maxNestingDepth: -1),
        ]

        for limits in cases {
            expect {
                _ = try HwpFile(
                    fromPath: hwpURL(#file, "plain-text-minimal").path,
                    readLimits: limits
                )
            }.to(throwError { error in
                guard case let HwpError.invalidDataLength(length) = error else {
                    return fail("Expected invalidDataLength, got \(error)")
                }
                expect(length).to(contain("HwpReadLimits"))
                expect(length).to(contain("greater than 0"))
            })
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
