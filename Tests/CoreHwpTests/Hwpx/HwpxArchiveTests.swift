@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpxArchiveTests: XCTestCase {
    private let limits = HwpReadLimits.default

    private func makeBudget(_ limits: HwpReadLimits) -> HwpxByteBudget {
        HwpxByteBudget(limits: limits)
    }

    // MARK: - 정상 경로

    func testReadsStoredAndDeflatedEntries() throws {
        let mimetype = Data("application/hwp+zip".utf8)
        let header = Data(String(repeating: "<hh:head/>", count: 100).utf8)
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: mimetype, method: 0),
            .init(name: "Contents/header.xml", content: header, method: 8),
        ]

        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect(try archive.entryData(
            named: "mimetype", limits: self.limits, budget: &budget
        )) == mimetype
        expect(try archive.entryData(
            named: "Contents/header.xml", limits: self.limits, budget: &budget
        )) == header
        expect(budget.totalBytes) == mimetype.count + header.count
    }

    func testReadsArchiveWithTrailingComment() throws {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("payload".utf8), method: 0)]
        builder.comment = Data("trailing archive comment".utf8)

        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect(try archive.entryData(named: "a", limits: self.limits, budget: &budget))
            == Data("payload".utf8)
    }

    func testReadsDataDescriptorEntryUsingCentralDirectorySizes() throws {
        // 비트 3이 세워지면 local header의 크기가 0이다 — central directory의
        // 선언값을 신뢰하는 리더만 이 엔트리를 읽을 수 있다.
        let content = Data("data descriptor entry".utf8)
        var builder = ZipBuilder()
        builder.entries = [.init(name: "d", content: content, method: 8, flags: 0b1000)]

        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect(try archive.entryData(named: "d", limits: self.limits, budget: &budget))
            == content
    }

    func testDuplicateEntryNamesKeepFirstOccurrence() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
            .init(name: "mimetype", content: Data("application/evil".utf8), method: 0),
        ]

        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect(try archive.entryData(
            named: "mimetype", limits: self.limits, budget: &budget
        )) == Data("application/hwp+zip".utf8)
    }

    func testOptionalEntryDataReturnsNilForMissingEntry() throws {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]

        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect(try archive.optionalEntryData(
            named: "missing", limits: self.limits, budget: &budget
        )).to(beNil())
        expect(budget.totalBytes) == 0
    }

    // MARK: - 구조 오류

    func testMissingEntryThrowsTypedError() throws {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "b", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            guard case let HwpError.archiveEntryDoesNotExist(name) = error else {
                return fail("Expected archiveEntryDoesNotExist, got \(error)")
            }
            expect(name) == "b"
        })
    }

    func testTooSmallDataThrowsInvalidArchive() {
        expect {
            _ = try HwpxArchive(data: Data("PK".utf8))
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "too small")
        })
    }

    func testMissingEndOfCentralDirectoryThrowsInvalidArchive() {
        expect {
            _ = try HwpxArchive(data: Data(repeating: 0x41, count: 128))
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "end-of-central-directory")
        })
    }

    func testTruncatedCentralDirectoryThrowsInvalidArchive() {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        builder.declaredEntryCount = 2

        expect {
            _ = try HwpxArchive(data: builder.build())
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "truncated central directory")
        })
    }

    func testCentralDirectoryBeyondEndOfCentralDirectoryThrowsInvalidArchive() {
        // EOCD만 있고 central directory 오프셋이 EOCD 뒤를 가리키는 아카이브.
        var data = Data()
        data.appendLittleEndian(UInt32(0x0605_4B50))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(64)) // directorySize
        data.appendLittleEndian(UInt32(0)) // directoryOffset
        data.appendLittleEndian(UInt16(0))

        expect {
            _ = try HwpxArchive(data: data)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "does not precede")
        })
    }

    func testZip64SentinelThrowsInvalidArchive() {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        builder.declaredEntryCount = 0xFFFF

        expect {
            _ = try HwpxArchive(data: builder.build())
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "Zip64")
        })
    }

    func testMultiDiskArchiveThrowsInvalidArchive() {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        var data = builder.build()
        // EOCD의 disk number 필드(뒤에서 18바이트 앞)를 1로 조작한다.
        data[data.count - 18] = 1

        expect {
            _ = try HwpxArchive(data: data)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "multi-disk")
        })
    }

    func testUnsupportedCompressionMethodThrowsInvalidArchive() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "a", content: Data("x".utf8), method: 12, storedPayload: Data("x".utf8)),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "unsupported compression method 12")
        })
    }

    func testEncryptedEntryThrowsUnsupportedFeature() throws {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0, flags: 0b1)]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            guard case HwpError.unsupportedFeature(.encryptedDocument) = error else {
                return fail("Expected unsupportedFeature(.encryptedDocument), got \(error)")
            }
        })
    }

    func testStoredEntrySizeMismatchThrowsInvalidArchive() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data("abcd".utf8),
                method: 0,
                declaredUncompressedSize: 9
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "mismatched sizes")
        })
    }

    func testDeflatedEntrySizeMismatchThrowsInvalidArchive() throws {
        // stored 경로와 같은 규약 — central directory 선언값이 정본이므로
        // 인플레이트 결과가 선언 크기와 다르면 구조 손상으로 거부한다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data("abcd".utf8),
                method: 8,
                declaredUncompressedSize: 9
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "mismatched sizes")
        })
    }

    func testCorruptedDeflateStreamThrowsInvalidArchive() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data("whatever".utf8),
                method: 8,
                storedPayload: Data([0xDE, 0xAD, 0xBE, 0xEF])
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "corrupted deflate stream")
        })
    }

    func testTruncatedEntryPayloadThrowsInvalidArchive() throws {
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "a",
                content: Data("abcd".utf8),
                method: 0,
                declaredCompressedSize: 1 << 20,
                declaredUncompressedSize: 1 << 20
            ),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "a", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "truncated entry")
        })
    }
}

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

private func assertInvalidArchive(_ error: Error, containing fragment: String) {
    guard case let HwpError.invalidArchive(reason) = error else {
        return fail("Expected invalidArchive, got \(error)")
    }
    expect(reason).to(contain(fragment))
}
