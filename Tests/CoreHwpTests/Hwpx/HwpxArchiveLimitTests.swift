@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 자원 한도(개별·집계)의 적용과 귀속 규약.
final class HwpxArchiveLimitTests: XCTestCase {
    private func makeBudget(_ limits: HwpReadLimits) -> HwpxByteBudget {
        HwpxByteBudget(limits: limits)
    }

    func testOversizedCentralDirectoryIsRejectedBeforeDecodingNames() throws {
        // 이름 디코딩은 엔트리 예산이 서기 전이라 설정 한도를 우회한다 —
        // 디렉터리 크기로 사전에 막는다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(name: "Contents/header.xml", content: Data("<x/>".utf8), method: 0),
        ]
        let archive = builder.build()

        expect {
            _ = try HwpxArchive(
                data: archive, limits: HwpReadLimits(maxAggregateStreamBytes: 16)
            )
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, _) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "central directory"
            expect(limit) == 16
        })

        // 대조군: 넉넉한 한도에서는 그대로 열린다.
        let opened = try HwpxArchive(data: archive)
        expect(opened.entriesByName.keys.sorted()) == ["Contents/header.xml", "mimetype"]
    }

    func testDeclaredOversizedDeflatedEntryIsRejectedBeforeInflating() throws {
        // payload가 corrupt인데 invalidArchive가 아니라 크기 오류가 나면
        // 인플레이트 전에 선언값으로 거부된 것이다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data(count: 4),
                method: 8,
                storedPayload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                declaredUncompressedSize: 1 << 20
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        let limits = HwpReadLimits(maxDecompressedStreamBytes: 1 << 10)
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: limits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(_, limit, actual) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(limit) == 1 << 10
            expect(actual) == 1 << 20
        })
    }

    func testDeclaredSizeOverAggregateBudgetIsRejectedBeforeInflating() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data(count: 4),
                method: 8,
                storedPayload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                declaredUncompressedSize: 2048
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        let limits = HwpReadLimits(maxAggregateStreamBytes: 1 << 10)
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: limits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(_, limit, actual) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(limit) == 1 << 10
            expect(actual) == 2048
        })
    }

    func testCompressedEntryOverPerEntryLimitThrowsTypedError() throws {
        let content = Data(repeating: 0x41, count: 4096)
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: content, method: 8)]
        let archive = try HwpxArchive(data: builder.build())
        let tightLimits = HwpReadLimits(maxCompressedStreamBytes: 4)
        var budget = makeBudget(tightLimits)

        expect {
            _ = try archive.entryData(named: "a", limits: tightLimits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, _) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "a"
            expect(limit) == 4
        })
    }

    func testDecompressionBombIsStoppedAtPerEntryLimit() throws {
        // 강압축 입력: 1 MiB 반복 바이트는 deflate로 수 KiB가 된다. 출력
        // 한도를 그보다 작게 걸면 해제 도중 중단되어야 한다.
        let content = Data(repeating: 0x42, count: 1 << 20)
        var builder = ZipBuilder()
        builder.entries = [.init(name: "bomb", content: content, method: 8)]
        let archive = try HwpxArchive(data: builder.build())
        let tightLimits = HwpReadLimits(maxDecompressedStreamBytes: 64 * 1024)
        var budget = makeBudget(tightLimits)

        expect {
            _ = try archive.entryData(named: "bomb", limits: tightLimits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, actual) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "bomb"
            expect(limit) == 64 * 1024
            expect(actual) >= limit
        })
        expect(budget.totalBytes) == 0
    }

    func testAggregateBudgetIsChargedAcrossEntriesAndReportsAggregateLimit() throws {
        let content = Data(repeating: 0x43, count: 60 * 1024)
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "first", content: content, method: 8),
            .init(name: "second", content: content, method: 8),
        ]
        let archive = try HwpxArchive(data: builder.build())
        // 개별 한도는 넉넉하고 집계만 한 엔트리 분량 남짓 — 둘째 읽기가 집계
        // 한도로 중단되고 error의 limit이 집계 한도여야 한다.
        let tightLimits = HwpReadLimits(maxAggregateStreamBytes: 64 * 1024)
        var budget = makeBudget(tightLimits)

        expect(try archive.entryData(
            named: "first", limits: tightLimits, budget: &budget
        )) == content

        expect {
            _ = try archive.entryData(named: "second", limits: tightLimits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, _) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "second"
            expect(limit) == 64 * 1024
        })
    }

    func testStoredEntryOverCompressedLimitIsRejected() throws {
        // 압축 입력 상한은 method 0에도 적용된다 — 출력 상한만 보면 stored로
        // 저장한 파트가 그 한도를 우회한다. 출력 상한은 넉넉히 둬서 이
        // 거부가 압축 상한에서 나온 것임을 분명히 한다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "a", content: Data(repeating: 0x55, count: 4 * 1024), method: 0),
        ]
        let archive = try HwpxArchive(data: builder.build())
        let limits = HwpReadLimits(
            maxCompressedStreamBytes: 1024,
            maxDecompressedStreamBytes: 1 << 20
        )
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: limits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, actual) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "a"
            expect(limit) == 1024
            expect(actual) == 4 * 1024
        })
    }

    func testStoredEntryOverAggregateBudgetThrowsAggregateLimit() throws {
        let content = Data(repeating: 0x44, count: 8 * 1024)
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "first", content: content, method: 0),
            .init(name: "second", content: content, method: 0),
        ]
        let archive = try HwpxArchive(data: builder.build())
        let tightLimits = HwpReadLimits(maxAggregateStreamBytes: 12 * 1024)
        var budget = makeBudget(tightLimits)

        _ = try archive.entryData(named: "first", limits: tightLimits, budget: &budget)

        expect {
            _ = try archive.entryData(named: "second", limits: tightLimits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntrySizeLimitExceeded(name, limit, actual) = error
            else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
            expect(name) == "second"
            expect(limit) == 12 * 1024
            expect(actual) == 16 * 1024
        })
    }

    func testCentralDirectoryIsDebitedFromTheAggregateBudget() throws {
        // 고립 검사만 두면 상주 이름과 엔트리 데이터가 각각 한도만큼 써
        // 파일 단위 상한의 2배까지 간다 — 디렉터리 비용을 예산에서 뺀다.
        let header = Data(repeating: 0x41, count: 400)
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(name: "Contents/header.xml", content: header, method: 0),
        ]
        let archive = builder.build()
        let directoryBytes = try HwpxArchive(data: archive).centralDirectoryBytes
        let mimetypeBytes = "application/hwp+zip".utf8.count

        // 디렉터리와 mimetype을 뺀 잔여가 399 — header 400에 한 바이트 모자란다.
        var tight = try HwpxContainer(
            data: archive,
            limits: HwpReadLimits(
                maxAggregateStreamBytes: directoryBytes + mimetypeBytes + 399
            )
        )
        expect {
            _ = try tight.requiredEntry("Contents/header.xml")
        }.to(throwError { error in
            guard case HwpError.archiveEntrySizeLimitExceeded = error else {
                return fail("Expected archiveEntrySizeLimitExceeded, got \(error)")
            }
        })

        // 대조군: 딱 한 바이트를 더 주면 열린다 (차감이 없으면 위도 통과한다).
        var ample = try HwpxContainer(
            data: archive,
            limits: HwpReadLimits(
                maxAggregateStreamBytes: directoryBytes + mimetypeBytes + 400
            )
        )
        expect(try ample.requiredEntry("Contents/header.xml").count) == 400
    }

    func testFailedEntryIsCachedInsteadOfReinflating() throws {
        // spine은 같은 손상 구역을 65,535번까지 참조할 수 있는데 실패 출력은
        // 예산에 잡히지 않아 (consume은 성공 경로에만 있다) 압축 해제가 상한
        // 없이 반복된다 — 실패를 캐시해 끊는다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(
                name: "Contents/section0.xml",
                content: Data(count: 4),
                method: 8,
                storedPayload: Data([0xDE, 0xAD, 0xBE, 0xEF])
            ),
        ]
        var container = try HwpxContainer(data: builder.build(), limits: .default)

        for _ in 0 ..< 2 {
            expect {
                _ = try container.requiredEntry("Contents/section0.xml")
            }.to(throwError { error in
                guard case HwpError.invalidArchive = error else {
                    return fail("Expected invalidArchive, got \(error)")
                }
            })
        }
        // 두 번 불렀지만 아카이브는 한 번만 읽혔다 — 조기 반환이 없으면
        // 같은 손상 스트림을 매번 다시 푼다.
        expect(container.archiveReadCount) == 1
        expect(container.failedEntries.keys.sorted()) == ["Contents/section0.xml"]
    }
}
