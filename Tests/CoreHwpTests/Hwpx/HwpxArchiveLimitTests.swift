@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 자원 한도(개별·집계)의 적용과 귀속 규약.
final class HwpxArchiveLimitTests: XCTestCase {
    private func makeBudget(_ limits: HwpReadLimits) -> HwpxByteBudget {
        HwpxByteBudget(limits: limits)
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
}
