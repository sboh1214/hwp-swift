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

    /// 중앙 디렉터리와 EOCD 사이에 임의 20바이트를 끼운다 — EOCD의
    /// offset/size 관계는 그대로라 아카이브는 여전히 유효하다.
    private func endOfCentralDirectoryOffset(of archive: Data) throws -> Int {
        // 한 식에 몰면 Swift 5.9 타입 체커가 시간 안에 못 푼다 (Linux CI 실측:
        // "unable to type-check this expression in reasonable time").
        let bytes = [UInt8](archive)
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let candidates = stride(from: bytes.count - signature.count, through: 0, by: -1)
        let offset = candidates.first { start in
            Array(bytes[start ..< start + signature.count]) == signature
        }
        return try XCTUnwrap(offset)
    }

    private func splicingBeforeEndOfCentralDirectory(
        _ archive: Data, _ filler: [UInt8]
    ) throws -> Data {
        let eocd = try endOfCentralDirectoryOffset(of: archive)
        return archive[..<eocd] + Data(filler) + archive[eocd...]
    }

    func testLocatorSignatureWithoutValidStructureIsNotZip64() throws {
        // 유효한 non-Zip64인데 EOCD 앞 20바이트가 우연히 locator 시그니처로
        // 시작하는 경우 — 시그니처만 보면 이 아카이브를 잃는다.
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        let decoy: [UInt8] = [0x50, 0x4B, 0x06, 0x07] + [UInt8](repeating: 0xAA, count: 16)

        let archive = try splicingBeforeEndOfCentralDirectory(builder.build(), decoy)
        let parsed = try HwpxArchive(data: archive)

        expect(parsed.entriesByName.keys.sorted()) == ["a"]
    }

    func testCoherentZip64LocatorStillThrowsInvalidArchive() throws {
        // 대조군 — 가리키는 자리에 실제 Zip64 EOCD가 있으면 종전대로 거부한다.
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        let base = builder.build()
        // 끼워 넣은 record가 놓일 자리 = 원래 EOCD 위치.
        let recordOffset = UInt32(try endOfCentralDirectoryOffset(of: base))
        var locator: [UInt8] = [0x50, 0x4B, 0x06, 0x07, 0, 0, 0, 0]
        locator += withUnsafeBytes(of: recordOffset.littleEndian, Array.init)
        locator += [0, 0, 0, 0] + [1, 0, 0, 0]
        let record: [UInt8] = [0x50, 0x4B, 0x06, 0x06]

        let archive = try splicingBeforeEndOfCentralDirectory(base, record + locator)

        expect {
            _ = try HwpxArchive(data: archive)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "Zip64")
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

    func testEntryOnAnotherDiskThrowsInvalidArchive() throws {
        // EOCD 검사는 아카이브 수준 선언만 본다 — 엔트리 자신의 disk
        // 선언(+34)이 다른 디스크를 가리키면 localHeaderOffset을 현재
        // 바이트로 읽으면 안 되므로 같은 문구로 거부한다.
        let data = try archivePatchingDirectoryEntryDisk(to: 1)

        expect {
            _ = try HwpxArchive(data: data)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "multi-disk")
        })
    }

    func testEntryDiskZip64SentinelThrowsInvalidArchive() throws {
        // 0xFFFF는 멀티 디스크 주장이 아니라 Zip64 extra field 위임 표식이다
        // — EOCD sentinel과 같은 분류로 던진다.
        let data = try archivePatchingDirectoryEntryDisk(to: 0xFFFF)

        expect {
            _ = try HwpxArchive(data: data)
        }.to(throwError { error in
            assertInvalidArchive(error, containing: "Zip64")
        })
    }

    /// central directory 엔트리(PK\x01\x02)의 disk-number-start(+34)를
    /// 조작한 단일 엔트리 아카이브.
    private func archivePatchingDirectoryEntryDisk(to value: UInt16) throws -> Data {
        var builder = ZipBuilder()
        builder.entries = [.init(name: "a", content: Data("x".utf8), method: 0)]
        var data = builder.build()
        let signature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        let start = try XCTUnwrap(data.indices.first { index in
            index + 4 <= data.endIndex && data[index ..< index + 4].elementsEqual(signature)
        })
        data[start + 34] = UInt8(value & 0xFF)
        data[start + 35] = UInt8(value >> 8)
        return data
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
