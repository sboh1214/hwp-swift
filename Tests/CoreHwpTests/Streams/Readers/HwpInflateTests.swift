@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import SWCompression
import XCTest

/// `HwpInflate`의 Apple `Compression` 경로가 `SWCompression` 폴백과 같은 결과를
/// 내는지 고정한다.
///
/// Apple 경로가 컴파일되지 않는 플랫폼에서는 두 경로가 같은 구현이 되어 비교가
/// 항등식이 되므로 동등성 스위트 전체를 `canImport(Compression)`으로 막는다.
/// 즉 이 파일의 실효 검증은 macOS·iOS 잡에서만 일어난다.
final class HwpInflateTests: XCTestCase {
    #if canImport(Compression)

        /// **수용 기준.** 코퍼스의 모든 실제 deflate stream에서 두 경로의 출력이
        /// 바이트 단위로 같아야 한다.
        func testInflateMatchesFallbackOnEveryDeflateStream() throws {
            var compared = 0

            for stream in try allDeflateStreams() {
                let actual = try HwpInflate.decompress(stream.input, limit: .max)
                expect(actual).to(equal(stream.output), description: stream.label)
                compared += 1
            }

            // 코퍼스가 비거나 경로가 어긋나 아무것도 비교하지 않은 채 초록이
            // 되는 것을 막는다. 현재 코퍼스는 정확히 100개이고, 픽스처가
            // 늘어나는 방향으로만 움직인다.
            expect(compared).to(beGreaterThanOrEqualTo(100))
        }

        /// 절단된 stream은 부분 출력으로 성공해서는 안 된다.
        ///
        /// 스트리밍 루프가 "진전 없음 + `COMPRESSION_STATUS_END` 미도달"을 손상으로
        /// 판정하지 않으면 잘린 본문이 조용히 파싱되는 무성 데이터 손상이 된다.
        /// 성능 회귀가 아니라 정확성 회귀이므로 별도로 고정한다.
        func testTruncatedDeflateStreamIsRejectedInsteadOfReturningPartialOutput() throws {
            var truncatedCases = 0

            for stream in try allDeflateStreams() {
                let half = Data(stream.input.prefix(stream.input.count / 2))
                guard !half.isEmpty else {
                    continue
                }

                expect { try HwpInflate.decompress(half, limit: .max) }
                    .to(throwError(HwpInflate.Failure.corrupted), description: stream.label)
                truncatedCases += 1
            }

            expect(truncatedCases).to(beGreaterThanOrEqualTo(100))
        }

        /// deflate stream의 첫 byte를 예약 `BTYPE`으로 바꾸면 거부해야 한다 —
        /// 기존 손상 픽스처 합성(`temporaryHwp(corrupting…)`)이 쓰는 바로 그
        /// 변조이며, 문서 레벨 판정은 `StreamDecompressionStabilityTests`가
        /// 이미 양 경로에서 고정하고 있다.
        func testFirstByteCorruptionIsRejected() throws {
            var corruptedCases = 0

            for stream in try allDeflateStreams() {
                var corrupted = stream.input
                corrupted[corrupted.startIndex] = corrupted[corrupted.startIndex] == 0x06
                    ? 0x07
                    : 0x06

                expect { try HwpInflate.decompress(corrupted, limit: .max) }
                    .to(throwError(HwpInflate.Failure.corrupted), description: stream.label)
                corruptedCases += 1
            }

            expect(corruptedCases).to(beGreaterThanOrEqualTo(100))
        }

        /// **알려진 차이 고정.** Apple 디코더는 stored block의 `NLEN`이 `LEN`의
        /// 1의 보수인지 검증하지 않는다. zlib·SWCompression은 검증해 거부한다.
        ///
        /// 그래서 "deflate가 아닌 바이트열"에 대한 두 경로의 판정은 갈릴 수 있다.
        /// 프로덕션에서 이 차이에 닿는 입력은 **압축으로 표시됐지만 실제로는
        /// deflate가 아닌 손상 stream**뿐이고, 그 경우 출력은 레코드 트리
        /// 파서가 다시 검증해 typed error로 거른다. 유효한 HWP stream의 출력
        /// 바이트에는 영향이 없다.
        ///
        /// 이 테스트가 깨지면 Apple 디코더 동작이 바뀐 것이므로, 통과시킬 게
        /// 아니라 위 서술과 `HwpInflate` 주석을 다시 판단할 사건이다.
        func testAppleDecoderAcceptsStoredBlockWithInvalidComplement() {
            // PNG 매직 `89 50 4E 47`을 raw DEFLATE로 읽으면
            // BFINAL=1 · BTYPE=00(stored) · LEN=0x4E50 · NLEN=0x0D47 이고,
            // NLEN은 LEN의 보수(0xB1AF)가 아니다.
            var input = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            input.append(Data(repeating: 0x00, count: 0x4E50))

            expect(try Deflate.decompress(data: input)).to(throwError())
            expect(try HwpInflate.decompress(input, limit: .max)).to(haveCount(0x4E50))
        }

        /// 상한은 압축 해제가 끝난 뒤가 아니라 도중에 걸려야 한다.
        func testLimitStopsInflateBeforeProducingFullOutput() throws {
            let stream = try largestDeflateStream()
            let limit = stream.output.count / 2

            expect { try HwpInflate.decompress(stream.input, limit: limit) }
                .to(throwError { error in
                    guard case let HwpInflate.Failure.limitExceeded(produced) = error else {
                        return fail("Expected limitExceeded, got \(error)")
                    }
                    // 하한이므로 limit은 넘되, 전체를 다 푼 뒤 재는 것이
                    // 아님을 전체 크기에 못 미친다는 것으로 확인한다.
                    expect(produced) > limit
                    expect(produced) < stream.output.count
                })
            // 상한 초과가 손상으로 뭉개지지 않는지 — 즉 `throwError(_:)`가
            // 두 케이스를 실제로 구별하는지 확인한다. 구별하지 못하면 위
            // 절단·손상 테스트가 아무것도 증명하지 못한다.
            expect { try HwpInflate.decompress(stream.input, limit: limit) }
                .toNot(throwError(HwpInflate.Failure.corrupted))
        }

        /// 정확히 결과 크기만큼의 상한은 성공해야 한다 (off-by-one 방지).
        func testLimitEqualToDecompressedSizeSucceeds() throws {
            let stream = try largestDeflateStream()

            expect(try HwpInflate.decompress(stream.input, limit: stream.output.count))
                == stream.output
            expect { try HwpInflate.decompress(stream.input, limit: stream.output.count - 1) }
                .to(throwError { error in
                    guard case HwpInflate.Failure.limitExceeded = error else {
                        return fail("Expected limitExceeded, got \(error)")
                    }
                })
        }

        /// 빈 입력은 유효한 raw DEFLATE stream이 아니다 — 폴백과 판정을 맞춘다.
        func testEmptyInputIsRejectedLikeFallback() {
            expect(try Deflate.decompress(data: Data())).to(throwError())
            expect { try HwpInflate.decompress(Data(), limit: .max) }
                .to(throwError(HwpInflate.Failure.corrupted))
        }

    #endif

    /// 도중 상한이 개별 stream 한도에 걸리면 `streamSizeLimitExceeded`를 던지고,
    /// `limit` payload로는 **파생된 min이 아니라 원래 개별 stream 한도**를
    /// 보고해야 한다.
    func testPerStreamLimitReportsOriginalStreamLimit() throws {
        let url = hwpURL(#file, "plain-text-minimal")
        let limit = try decompressedSize(ofRootStream: .docInfo, in: url) - 1

        expect {
            _ = try HwpFile(
                fromPath: url.path,
                readLimits: HwpReadLimits(
                    maxCompressedStreamBytes: .max,
                    maxDecompressedStreamBytes: limit,
                    maxAggregateStreamBytes: .max
                )
            )
        }.to(throwError { error in
            guard case let HwpError.streamSizeLimitExceeded(name, actualLimit, actual) = error
            else {
                return fail("Expected streamSizeLimitExceeded, got \(error)")
            }
            expect(name) == HwpStreamName.docInfo
            expect(actualLimit) == limit
            expect(actual) > limit
        })
    }

    /// 남은 집계 예산이 개별 stream 한도보다 작아 도중 상한을 결정하더라도,
    /// 보고되는 error는 `aggregateStreamSizeLimitExceeded`이고 `limit`은 원래
    /// 집계 한도여야 한다 — 도중 상한 도입으로 error 분류가 바뀌면 안 된다.
    func testAggregateBudgetBindingReportsAggregateError() throws {
        let url = hwpURL(#file, "plain-text-minimal")
        let fileHeaderSize = try rootStreamData(.fileHeader, in: url).count
        let docInfoSize = try decompressedSize(ofRootStream: .docInfo, in: url)
        // FileHeader는 통과시키고 DocInfo 압축 해제 도중 정확히 1 byte 모자라게.
        let aggregate = fileHeaderSize + docInfoSize - 1

        expect {
            _ = try HwpFile(
                fromPath: url.path,
                readLimits: HwpReadLimits(
                    maxCompressedStreamBytes: .max,
                    maxDecompressedStreamBytes: .max,
                    maxAggregateStreamBytes: aggregate
                )
            )
        }.to(throwError { error in
            guard case let HwpError.aggregateStreamSizeLimitExceeded(name, limit, actual) = error
            else {
                return fail("Expected aggregateStreamSizeLimitExceeded, got \(error)")
            }
            expect(name) == HwpStreamName.docInfo
            expect(limit) == aggregate
            expect(actual) > aggregate
        })
    }
}

private struct DeflateStreamSample {
    let label: String
    let input: Data
    let output: Data
}

/// 프로덕션이 실제로 압축 해제하는 stream만 모은다 — `DocInfo`와
/// `BodyText`/`ViewText` storage의 자식들.
///
/// 문서 로드 루프(`HwpFile`)를 쓰지 않는 이유: 암호·DRM·배포용 픽스처는 압축
/// 해제 전에 `unsupportedFeature`로 거부되어 압축 경로에 닿지 못한다. 그래서
/// OLE를 직접 순회하되, 같은 이유로 그 4종은 `expectedError` 매니페스트로
/// 걸러 낸다 — 그 문서들의 stream은 deflate가 아니다.
///
/// **`SWCompression`에 임의 바이트를 먹이지 않는다.** `Deflate.decompress`는
/// deflate가 아닌 입력에서 throw가 아니라 프로세스를 중단시킨다(실측:
/// `bookmark`의 `PrvText` 64 byte). 그래서 코퍼스를 "SWCompression이 푸는가"로
/// 정의할 수 없고, 손상 입력 테스트도 Apple 경로만 단언한다. 문서 레벨의
/// 양 경로 손상 판정은 `StreamDecompressionStabilityTests`가 담당한다.
private func allDeflateStreams() throws -> [DeflateStreamSample] {
    var samples: [DeflateStreamSample] = []
    for fixture in try FixtureLoader.loadAll() where fixture.manifest.expectedError == nil {
        let fixtureID = fixture.fixtureURL.lastPathComponent
        for stream in try compressedStreams(in: fixture.documentURL) {
            samples.append(
                DeflateStreamSample(
                    label: "\(fixtureID)/\(stream.path)",
                    input: stream.data,
                    output: try Deflate.decompress(data: stream.data)
                )
            )
        }
    }
    return samples
}

/// 도중 상한 검사에 쓸, 코퍼스에서 압축 해제 결과가 가장 큰 stream.
/// 출력 버퍼 한 덩어리(64 KiB)보다 충분히 커야 "도중에 멈췄다"가 의미를 가진다.
private func largestDeflateStream() throws -> DeflateStreamSample {
    let largest = try allDeflateStreams().max { $0.output.count < $1.output.count }
    guard let largest, largest.output.count > 256 * 1024 else {
        throw HwpError.invalidDataLength(length: "no sufficiently large deflate stream")
    }
    return largest
}

private struct OLEStreamSample {
    let path: String
    let data: Data
}

private let compressedStorageNames: Set<String> = [
    HwpStreamName.bodyText.rawValue,
    HwpStreamName.viewText.rawValue,
]

private func compressedStreams(in url: URL) throws -> [OLEStreamSample] {
    let ole = try openOLE(at: url)

    var samples: [OLEStreamSample] = []
    for child in ole.root.children {
        if child.type == .stream, child.name == HwpStreamName.docInfo.rawValue {
            try samples.append(
                OLEStreamSample(path: child.name, data: readStream(child, from: ole))
            )
        } else if child.type == .storage, compressedStorageNames.contains(child.name) {
            for grandchild in child.children where grandchild.type == .stream {
                try samples.append(
                    OLEStreamSample(
                        path: "\(child.name)/\(grandchild.name)",
                        data: readStream(grandchild, from: ole)
                    )
                )
            }
        }
    }
    return samples
}

private func openOLE(at url: URL) throws -> OLEFile {
    do {
        return try OLEFile(url.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
}

private func readStream(_ entry: DirectoryEntry, from ole: OLEFile) throws -> Data {
    do {
        return try ole.stream(entry).readDataToEnd()
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }
}

private func rootStreamData(_ streamName: HwpStreamName, in url: URL) throws -> Data {
    let ole = try openOLE(at: url)
    guard let stream = ole.root.children.first(where: { $0.name == streamName.rawValue }) else {
        throw HwpError.streamDoesNotExist(name: streamName)
    }
    return try readStream(stream, from: ole)
}

private func decompressedSize(
    ofRootStream streamName: HwpStreamName,
    in url: URL
) throws -> Int {
    try Deflate.decompress(data: rootStreamData(streamName, in: url)).count
}
