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

    func testUnderreportedEntryCountIsRejected() {
        // 개수를 적게 선언하면 뒤 레코드가 entriesByName에서 빠져 존재 기반
        // 게이트(META-INF/encryption.xml)가 통째로 우회된다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(
                name: "mimetype",
                content: Data("application/hwp+zip".utf8),
                method: 0
            ),
            .init(
                name: "META-INF/encryption.xml",
                content: Data("<encryption/>".utf8),
                method: 0
            ),
        ]
        builder.declaredEntryCount = 1

        expect {
            _ = try HwpxArchive(data: builder.build())
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "trailing bytes")
        })
    }

    func testOversizedDirectoryLengthFieldsAreRejectedAsTruncated() {
        // 이름 길이 필드를 0xFFFF로 조작 — 길이 합이 디렉터리 끝을 넘는
        // 입력은 (32비트에서 트랩할 수 있는 덧셈 없이) invalidArchive다.
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
        ]
        var archive = builder.build()
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        guard let entryRange = archive.firstRange(of: signature) else {
            return fail("central directory entry not found")
        }
        archive[entryRange.lowerBound + 28] = 0xFF
        archive[entryRange.lowerBound + 29] = 0xFF

        expect {
            _ = try HwpxArchive(data: archive)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "truncated central directory")
        })
    }

    func testDisagreeingEntryCountsAreRejected() {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        var archive = builder.build()
        // EOCD의 이 디스크 개수(+8)만 어긋나게 바꾼다.
        let eocdOffset = archive.count - 22
        archive[eocdOffset + 8] = 9

        expect {
            _ = try HwpxArchive(data: archive)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "entry counts disagree")
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

    func testInflationIsBoundedByDeclaredSize() throws {
        // 유효한 deflate가 선언보다 크게 풀리는 엔트리 — 전역 한도까지 증폭
        // 할당하지 않고 선언 한도에서 구조 손상으로 중단해야 한다.
        let content = Data(repeating: 0x42, count: 1 << 20)
        var builder = ZipBuilder()
        builder.entries = [
            .init(name: "bomb", content: content, method: 8, declaredUncompressedSize: 64),
        ]
        let archive = try HwpxArchive(data: builder.build())
        var budget = makeBudget(limits)

        expect {
            _ = try archive.entryData(named: "bomb", limits: self.limits, budget: &budget)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "declared size")
        })
        expect(budget.totalBytes) == 0
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

func assertInvalidArchive(_ error: Error, containing fragment: String) {
    guard case let HwpError.invalidArchive(reason) = error else {
        return fail("Expected invalidArchive, got \(error)")
    }
    expect(reason).to(contain(fragment))
}
