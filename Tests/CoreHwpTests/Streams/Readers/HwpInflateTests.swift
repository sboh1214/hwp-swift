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
    /// 집계 한도여야 한다. 개별 한도가 `.max`인 이 조합은 집계만 위반이라 종전
    /// 분류와 같다 — 둘 다 위반이면 갈리며, 그 칸은
    /// `testDualLimitViolationReportsAggregateWhenAggregateBindsFirst`가 잠근다.
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

    /// 두 한도를 **동시에** 넘고 남은 집계 예산이 개별 stream 한도보다 작으면
    /// 집계 error로 보고한다. 후처리 거부 시절에는 개별 stream 검사가 집계
    /// 소비보다 먼저라 같은 입력이 `streamSizeLimitExceeded`였다 — 도중 상한이
    /// 종전 분류를 바꾸는 **유일한** 칸이다 (역방향은 없다).
    ///
    /// 복원할 수 없다. min에서 멈추므로 개별 한도 초과는 **증명되지 않았고**,
    /// 확인하려면 남은 집계 예산을 넘겨 풀어야 하는데 그것이 이 상한이 막으려는
    /// 할당이다. 증명 없이 개별 error를 고르면 실제로는 개별 한도 안이었던
    /// 입력(`남은 예산 < 크기 ≤ 개별 한도`)에 거짓 분류를 주므로, 분기를 없애는
    /// 것이 아니라 옮기는 셈이 된다.
    func testDualLimitViolationReportsAggregateWhenAggregateBindsFirst() throws {
        let url = hwpURL(#file, "plain-text-minimal")
        let fileHeaderSize = try rootStreamData(.fileHeader, in: url).count
        let docInfoSize = try decompressedSize(ofRootStream: .docInfo, in: url)
        // 개별 stream 한도를 넘기되(-1), 남은 집계 예산이 그보다 1 byte 더 작게(-2)
        // 잡아 min이 집계 쪽으로 결정되게 한다. 즉 둘 다 위반이고 집계가 먼저 건다.
        let streamLimit = docInfoSize - 1
        let aggregate = fileHeaderSize + docInfoSize - 2

        expect {
            _ = try HwpFile(
                fromPath: url.path,
                readLimits: HwpReadLimits(
                    maxCompressedStreamBytes: .max,
                    maxDecompressedStreamBytes: streamLimit,
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

    /// stored block의 `NLEN`이 `LEN`의 1의 보수가 아니면 거부한다.
    ///
    /// Apple 디코더는 이 검사를 생략하므로 `HwpInflate`가 앞단에서 직접 본다.
    /// 이런 입력이 닿는 곳이 레코드 트리로 다시 걸러지는 경로뿐이라면 굳이
    /// 볼 필요가 없지만, BinData 는 압축 해제 결과를 검증 없이 그대로 보관한다
    /// (`HwpFile.init(fromOLE:)`).
    func testStoredBlockWithInvalidComplementIsRejected() {
        // PNG 매직 `89 50 4E 47`을 raw DEFLATE로 읽으면
        // BFINAL=1 · BTYPE=00(stored) · LEN=0x4E50 · NLEN=0x0D47 이고,
        // NLEN은 LEN의 보수(0xB1AF)가 아니다.
        var input = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        input.append(Data(repeating: 0x00, count: 0x4E50))

        expect(try Deflate.decompress(data: input)).to(throwError())
        expect { try HwpInflate.decompress(input, limit: .max) }
            .to(throwError(HwpInflate.Failure.corrupted))
    }

    /// 유효한 stored block 연쇄는 통과시키고 폴백과 같은 바이트를 낸다 —
    /// 검사가 정상 입력을 막지 않는지 확인한다.
    func testValidStoredBlockChainMatchesFallback() {
        let input = storedBlock(Data("가나".utf8), isFinal: false)
            + storedBlock(Data("다라".utf8), isFinal: true)
        let expected = Data("가나다라".utf8)

        expect(try Deflate.decompress(data: input)) == expected
        expect(try HwpInflate.decompress(input, limit: .max)) == expected
    }

    /// 첫 블록만 보는 것이 아니라 stored 연쇄를 따라간다 — 두 번째 블록의
    /// `NLEN`만 틀려도 거부해야 검사가 공허하지 않다.
    ///
    /// **폴백은 이 입력을 받아들인다** (실측). 즉 이 거부는 어느 디코더와도
    /// 같지 않은 우리 쪽 엄격성이다. 가드가 Apple 분기 안이 아니라 공유
    /// 진입점에 있는 이유가 이것이다 — 그래야 두 플랫폼이 같은 판정을 낸다.
    func testInvalidComplementInLaterStoredBlockIsRejected() {
        let input = storedBlock(Data("가나".utf8), isFinal: false)
            + storedBlock(Data("다라".utf8), isFinal: true, complement: 0)

        expect(try Deflate.decompress(data: input)) == Data("가나다라".utf8)
        expect { try HwpInflate.decompress(input, limit: .max) }
            .to(throwError(HwpInflate.Failure.corrupted))
    }

    /// stored block 헤더가 `LEN`·`NLEN` 4 byte를 채우기 전에 끝나면 거부한다.
    func testStoredBlockHeaderTruncatedBeforeLengthIsRejected() {
        // BFINAL=1 · BTYPE=00 뒤에 LEN 2 byte 중 1 byte 만 남아 있다.
        let input = Data([0x01, 0x0A, 0x00])

        expect { try HwpInflate.decompress(input, limit: .max) }
            .to(throwError(HwpInflate.Failure.corrupted))
    }

    /// stored block 이 선언한 `LEN` 이 남은 입력을 넘으면 거부한다.
    func testStoredBlockLengthBeyondInputIsRejected() {
        // LEN=10 이라고 선언하고 payload 는 3 byte 만 준다 (NLEN 은 정상).
        var input = Data([0x01, 0x0A, 0x00, 0xF5, 0xFF])
        input.append(Data([0x41, 0x42, 0x43]))

        expect { try HwpInflate.decompress(input, limit: .max) }
            .to(throwError(HwpInflate.Failure.corrupted))
    }

    #if canImport(Compression)

        /// 마지막 블록이 `BFINAL` 없이 입력 끝에 닿으면 stream 이 끊긴 것이다.
        ///
        /// 검사기는 연쇄를 다 따라가고도 최종 블록을 못 만나 그냥 반환하고,
        /// 거부는 디코더의 "진전 없음 + `END` 미도달" 판정이 맡는다. 두 층이
        /// 이어져야 절단이 부분 출력으로 새지 않는다.
        func testNonFinalStoredBlockEndingAtInputEndIsRejected() {
            let input = storedBlock(Data("가나".utf8), isFinal: false)

            expect { try HwpInflate.decompress(input, limit: .max) }
                .to(throwError(HwpInflate.Failure.corrupted))
        }

    #endif
}

/// raw DEFLATE stored block 한 개. `complement`를 주면 `NLEN`을 그 값으로 심어
/// 규격 위반 입력을 만든다.
private func storedBlock(
    _ payload: Data,
    isFinal: Bool,
    complement: UInt16? = nil
) -> Data {
    let length = UInt16(payload.count)
    let storedLengthComplement = complement ?? ~length
    var block = Data([isFinal ? 0x01 : 0x00])
    block.append(UInt8(length & 0xFF))
    block.append(UInt8(length >> 8))
    block.append(UInt8(storedLengthComplement & 0xFF))
    block.append(UInt8(storedLengthComplement >> 8))
    block.append(payload)
    return block
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
