import Foundation

/// HWPX(OCF) 컨테이너의 ZIP 계층을 읽는 최소 리더.
///
/// OLE는 OLEKit에 맡기지만 ZIP은 외부 의존 없이 직접 읽는다 — 순수 Swift
/// 압축 라이브러리를 프로덕션에서 걷어낸 결정(#101)과 정합하도록, 필요한
/// 만큼만 지원한다: central directory 기반 엔트리 탐색, method 0(stored)/
/// 8(deflate), Zip64·멀티 디스크 거부. 압축 해제는 기존 `HwpInflate`
/// (raw DEFLATE = ZIP method 8)에 위임해 스트리밍 도중 한도 적용을 그대로
/// 얻는다. 자체 컨테이너 리더의 선례는 `EmbeddedCompoundFile`
/// (`Utils/HwpEmbeddedChart.swift`)이다.
///
/// 엔트리 크기는 항상 central directory의 선언값을 쓴다 — general purpose
/// bit 3(data descriptor)이 세워진 파일의 local header는 크기가 0이므로
/// 보지 않는다. CRC는 검증하지 않는다 — HWP5 경로도 stream 무결성 검사를
/// 하지 않으며, 손상은 상위 XML/모델 검증이 typed error로 받는다.
///
/// 같은 이름의 중복 엔트리는 **첫 등장이 이긴다** (결정적) — 뒤에 붙인
/// 두 번째 `mimetype` 등으로 판정을 뒤집을 수 없다.
struct HwpxArchive {
    /// central directory 한 항목의 해석 결과.
    struct Entry {
        let name: String
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    let entriesByName: [String: Entry]
    /// central directory가 상주로 옮긴 바이트 — 엔트리 이름 문자열의 상한이다.
    /// 컨테이너가 이것을 집계 예산에서 **차감**해야 이름과 엔트리 데이터가
    /// 한 상한을 나눠 쓴다 (고립 검사만 두면 각각 한도만큼 써 2배가 된다).
    let centralDirectoryBytes: Int

    /// 아카이브 전체 바이트에서 central directory를 해석한다.
    ///
    /// 여기서는 구조만 읽고 엔트리 내용은 읽지 않는다 — 내용 읽기와 자원
    /// 한도 적용은 `entryData(named:limits:budget:)`가 맡는다.
    init(data: Data, limits: HwpReadLimits = .default) throws {
        // 슬라이스 인덱스 함정을 피해 분리 복사 없이 0 기준으로 다룬다.
        let data = data.startIndex == 0 ? data : Data(data)
        self.data = data

        let eocdOffset = try Self.locateEndOfCentralDirectory(data)
        try Self.rejectZip64AndMultiDisk(data, eocdOffset: eocdOffset)

        // 단일 디스크 아카이브만 지원하므로 이 디스크의 개수(+8)와 총
        // 개수(+10)가 같아야 한다 — 어긋나면 어느 쪽을 믿어도 디렉터리를
        // 부분만 읽게 된다.
        let diskEntryCount = try data.readLittleEndianUInt16(at: eocdOffset + 8)
        let entryCount = Int(try data.readLittleEndianUInt16(at: eocdOffset + 10))
        guard Int(diskEntryCount) == entryCount else {
            throw HwpError.invalidArchive(
                reason: "end-of-central-directory entry counts disagree: " +
                    "\(diskEntryCount) on disk vs \(entryCount) total"
            )
        }
        // 32비트 Int(watchOS arm64_32)에서 트랩하지 않게 구조 가드 전에 failable
        // 변환한다 — sentinel 아닌 0x80000000...0xFFFFFFFE가 여기 도달한다 (P1,
        // `parseDirectoryEntry`와 같은 이유).
        guard let directorySize = Int(
            exactly: try data.readLittleEndianUInt32(at: eocdOffset + 12)
        ),
            let directoryOffset = Int(
                exactly: try data.readLittleEndianUInt32(at: eocdOffset + 16)
            )
        else {
            throw HwpError.invalidArchive(
                reason: "central directory size or offset beyond Int range"
            )
        }
        guard directoryOffset <= eocdOffset,
              directorySize <= eocdOffset - directoryOffset
        else {
            throw HwpError.invalidArchive(
                reason: "central directory [\(directoryOffset), +\(directorySize)] " +
                    "does not precede end-of-central-directory at \(eocdOffset)"
            )
        }
        // 이름 디코딩은 매핑된 바이트를 **상주** String으로 옮기는 유일한
        // 지점인데, 여기는 엔트리 예산(HwpxByteBudget)이 서기 전이라 설정한
        // 한도가 통째로 우회된다. 이름 바이트 합은 디렉터리 크기 이하이므로
        // 그것으로 사전에 막는다 (항목 수는 EOCD가 UInt16이라 이미 유계다).
        guard directorySize <= limits.maxAggregateStreamBytes else {
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: "central directory",
                limit: limits.maxAggregateStreamBytes,
                actual: directorySize
            )
        }

        centralDirectoryBytes = directorySize
        entriesByName = try Self.readCentralDirectory(
            data,
            directoryOffset: directoryOffset,
            directoryEnd: directoryOffset + directorySize,
            entryCount: entryCount
        )
    }
}

extension HwpxArchive {
    /// 이름이 일치하는 엔트리의 압축 해제된 내용을 돌려준다.
    ///
    /// 한도 규약은 `StreamReader`와 같다: 압축 입력은
    /// `maxCompressedStreamBytes`, 출력은 `maxDecompressedStreamBytes`와
    /// 남은 집계 예산의 min을 **도중에** 적용하고, 실제로 걸린 쪽의 원래
    /// 한도를 보고하되 같으면 개별 한도를 우선한다. 보유하게 된 출력
    /// 바이트는 `budget`에 누적된다.
    func entryData(
        named name: String,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws -> Data {
        guard let entry = entriesByName[name] else {
            throw HwpError.archiveEntryDoesNotExist(name: name)
        }
        // general purpose bit 0 = 엔트리 암호화. 별도 케이스를 만들지 않고
        // 기존 미지원 분류를 재사용한다 — 뷰어가 그릴 수 없는 최소 전제라는
        // 의미가 같다 (recovery-exempt 분류도 함께 따라온다).
        guard entry.flags & 0b1 == 0 else {
            throw HwpError.unsupportedFeature(.encryptedDocument)
        }

        let payload = try compressedPayload(of: entry)
        switch entry.method {
        case 0:
            return try storedEntryData(entry, payload: payload, limits: limits, budget: &budget)
        case 8:
            return try deflatedEntryData(entry, payload: payload, limits: limits, budget: &budget)
        default:
            throw HwpError.invalidArchive(
                reason: "unsupported compression method \(entry.method) in '\(entry.name)'"
            )
        }
    }

    /// 엔트리가 없으면 nil, 있으면 `entryData`와 같다.
    func optionalEntryData(
        named name: String,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws -> Data? {
        guard entriesByName[name] != nil else {
            return nil
        }
        return try entryData(named: name, limits: limits, budget: &budget)
    }
}

private extension HwpxArchive {
    /// ZIP 시그니처 (little-endian UInt32로 읽은 값).
    enum Signature {
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
        static let centralDirectoryEntry: UInt32 = 0x0201_4B50
        static let localFileHeader: UInt32 = 0x0403_4B50
        static let zip64Locator: UInt32 = 0x0706_4B50
        static let zip64EndOfCentralDirectory: UInt32 = 0x0606_4B50
    }

    static let endOfCentralDirectoryLength = 22
    static let maximumCommentLength = 0xFFFF

    /// EOCD 레코드를 끝에서 역방향으로 찾는다 (주석 최대 64 KiB 허용).
    ///
    /// 실제 EOCD의 주석은 파일 끝까지 정확히 이어지므로 선언 주석 길이가 남은
    /// 바이트와 **정확히** 일치해야 한다 (`==`). 합법 주석 안에 박힌 가짜 EOCD
    /// 시그니처는 실제 EOCD보다 **뒤**(높은 오프셋)에 있어 역방향 스캔이 먼저
    /// 만나는데, 그 뒤에는 자기 주석 몫보다 많은 바이트가 남으므로 이 정확
    /// 대조에서 탈락한다 — `<=`로 두면 가짜가 임의 주석 길이로 통과해 빈·엉뚱한
    /// 디렉터리를 파싱한다 (P2). 탈락하면 스캔을 계속해 앞의 진짜 EOCD를 찾는다.
    static func locateEndOfCentralDirectory(_ data: Data) throws -> Int {
        guard data.count >= endOfCentralDirectoryLength else {
            throw HwpError.invalidArchive(
                reason: "\(data.count) bytes is too small for a ZIP archive"
            )
        }
        let lowerBound = max(
            0, data.count - endOfCentralDirectoryLength - maximumCommentLength
        )
        var offset = data.count - endOfCentralDirectoryLength
        while offset >= lowerBound {
            if try data.readLittleEndianUInt32(at: offset) == Signature.endOfCentralDirectory {
                let commentLength = Int(try data.readLittleEndianUInt16(at: offset + 20))
                if commentLength == data.count - endOfCentralDirectoryLength - offset {
                    return offset
                }
            }
            offset -= 1
        }
        throw HwpError.invalidArchive(reason: "end-of-central-directory record not found")
    }

    /// Zip64와 멀티 디스크 아카이브를 typed error로 거부한다.
    ///
    /// HWPX 문서는 4 GiB 근처에도 가지 않고, 그 크기라면 자원 한도가 어차피
    /// 거부한다 — Zip64 필드 해석을 늘리는 대신 명시적으로 지원하지 않는다.
    static func rejectZip64AndMultiDisk(_ data: Data, eocdOffset: Int) throws {
        let diskNumber = try data.readLittleEndianUInt16(at: eocdOffset + 4)
        let directoryDisk = try data.readLittleEndianUInt16(at: eocdOffset + 6)
        guard diskNumber == 0, directoryDisk == 0 else {
            throw HwpError.invalidArchive(reason: "multi-disk archives are not supported")
        }

        let entryCount = try data.readLittleEndianUInt16(at: eocdOffset + 10)
        let directorySize = try data.readLittleEndianUInt32(at: eocdOffset + 12)
        let directoryOffset = try data.readLittleEndianUInt32(at: eocdOffset + 16)
        let zip64Sentinel = entryCount == 0xFFFF
            || directorySize == 0xFFFF_FFFF
            || directoryOffset == 0xFFFF_FFFF
        guard !zip64Sentinel, try !hasZip64Locator(data, eocdOffset: eocdOffset) else {
            throw HwpError.invalidArchive(reason: "Zip64 archives are not supported")
        }
    }

    /// EOCD 앞 20바이트가 **온전한** Zip64 EOCD locator인지.
    ///
    /// 시그니처만 보면 중앙 디렉터리의 마지막 바이트들이 우연히 그 4바이트로
    /// 시작하는 유효한 non-Zip64 아카이브(엔트리 주석 등)를 거부한다. 단일
    /// 디스크 형태이고 가리키는 자리에 실제 Zip64 EOCD가 있을 때만 Zip64로
    /// 판정한다 — 진짜 Zip64는 EOCD sentinel(0xFFFF·0xFFFF_FFFF)이 별도로
    /// 잡으므로 이 판정을 좁혀도 통과하지 않는다.
    static func hasZip64Locator(_ data: Data, eocdOffset: Int) throws -> Bool {
        guard eocdOffset >= 20 else {
            return false
        }
        let offset = eocdOffset - 20
        guard try data.readLittleEndianUInt32(at: offset) == Signature.zip64Locator,
              try data.readLittleEndianUInt32(at: offset + 4) == 0,
              try data.readLittleEndianUInt32(at: offset + 16) == 1
        else {
            return false
        }
        // 레코드 오프셋은 64비트다 — 상위 워드가 있으면 4 GiB 밖이라 이 Data로
        // 확인할 수 없다 (그런 아카이브는 EOCD sentinel이 잡는다).
        guard try data.readLittleEndianUInt32(at: offset + 12) == 0,
              let recordOffset = Int(exactly: try data.readLittleEndianUInt32(at: offset + 8)),
              // 뺄셈형이어야 한다 — `recordOffset + 4` 꼴은 32비트 Int
              // (watchOS arm64_32)에서 가드가 판정하기 전에 트랩한다
              // (`parseDirectoryEntry`의 경계 판정과 같은 계약).
              recordOffset <= offset - 4
        else {
            return false
        }
        return try data.readLittleEndianUInt32(at: recordOffset)
            == Signature.zip64EndOfCentralDirectory
    }

    static func readCentralDirectory(
        _ data: Data,
        directoryOffset: Int,
        directoryEnd: Int,
        entryCount: Int
    ) throws -> [String: Entry] {
        var entries: [String: Entry] = [:]
        entries.reserveCapacity(entryCount)
        var offset = directoryOffset
        for _ in 0 ..< entryCount {
            let (entry, nextOffset) = try parseDirectoryEntry(
                data, at: offset, directoryEnd: directoryEnd
            )
            if entries[entry.name] == nil {
                entries[entry.name] = entry
            }
            offset = nextOffset
        }
        // 선언 개수만큼 돌고 끝났는데 디렉터리가 남아 있으면 선언이 실제를
        // 덮지 못한 것이다 — 남은 레코드(예: 마지막 META-INF/encryption.xml)가
        // entriesByName에서 빠져 존재 기반 게이트가 통째로 우회된다.
        guard offset == directoryEnd else {
            throw HwpError.invalidArchive(
                reason: "central directory has \(directoryEnd - offset) trailing bytes " +
                    "beyond the declared \(entryCount) entries"
            )
        }
        return entries
    }

    static func parseDirectoryEntry(
        _ data: Data,
        at offset: Int,
        directoryEnd: Int
    ) throws -> (entry: Entry, nextOffset: Int) {
        // 경계 판정은 뺄셈형이다 — `offset + 46 + 길이` 꼴은 data.count가
        // Int.max 부근인 32비트(watchOS arm64_32) 입력에서 가드가 던지기 전에
        // 트랩한다 (P1, 아래 Int(exactly:) 변환과 같은 계약).
        guard directoryEnd - offset >= 46 else {
            throw HwpError.invalidArchive(reason: "truncated central directory")
        }
        guard try data.readLittleEndianUInt32(at: offset)
            == Signature.centralDirectoryEntry
        else {
            throw HwpError.invalidArchive(
                reason: "central directory entry signature mismatch at \(offset)"
            )
        }

        let flags = try data.readLittleEndianUInt16(at: offset + 8)
        let method = try data.readLittleEndianUInt16(at: offset + 10)
        let compressedSize = try data.readLittleEndianUInt32(at: offset + 20)
        let uncompressedSize = try data.readLittleEndianUInt32(at: offset + 24)
        let nameLength = Int(try data.readLittleEndianUInt16(at: offset + 28))
        let extraLength = Int(try data.readLittleEndianUInt16(at: offset + 30))
        let commentLength = Int(try data.readLittleEndianUInt16(at: offset + 32))
        let localHeaderOffset = try data.readLittleEndianUInt32(at: offset + 42)
        guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF,
              localHeaderOffset != 0xFFFF_FFFF
        else {
            throw HwpError.invalidArchive(reason: "Zip64 archives are not supported")
        }

        // 우변은 WORD 필드 3개 합(≤ 196,605)이라 오버플로할 수 없고, 좌변은
        // 위 가드로 46 이상이다 — 이 판정을 지나면 아래 덧셈들은 전부
        // directoryEnd 이하로 유계라 트랩하지 않는다.
        guard directoryEnd - offset - 46 >= nameLength + extraLength + commentLength else {
            throw HwpError.invalidArchive(reason: "truncated central directory")
        }
        let nameEnd = offset + 46 + nameLength
        // HWPX 엔트리 이름은 전부 ASCII다 — UTF-8이 아닌 이름은 어떤 조회에도
        // 걸리지 않으므로 빈 이름으로 접어 구조만 유지한다 (첫 등장 우선 규칙과
        // 함께 결정적).
        let name = String(bytes: data[(offset + 46) ..< nameEnd], encoding: .utf8) ?? ""
        guard !name.contains("\u{0}") else {
            throw HwpError.invalidArchive(reason: "entry name contains NUL byte")
        }
        // 32비트 Int(watchOS arm64_32)에서 Int.max 초과 UInt32가 트랩하지
        // 않게 failable 변환을 쓴다 (`EmbeddedCompoundFile`과 같은 이유, P1).
        guard let compressed = Int(exactly: compressedSize),
              let uncompressed = Int(exactly: uncompressedSize),
              let headerOffset = Int(exactly: localHeaderOffset)
        else {
            throw HwpError.invalidArchive(
                reason: "entry '\(name)' declares sizes beyond Int range"
            )
        }
        let entry = Entry(
            name: name,
            method: method,
            flags: flags,
            compressedSize: compressed,
            uncompressedSize: uncompressed,
            localHeaderOffset: headerOffset
        )
        return (entry, nameEnd + extraLength + commentLength)
    }

    /// local header를 건너뛰어 엔트리의 압축된 payload 슬라이스를 얻는다.
    /// 길이는 central directory의 선언값이다. 오프셋 합은 전부 오버플로
    /// 검사를 거친다 — 32비트 Int 플랫폼에서 조작 헤더가 트랩하지 않게.
    func compressedPayload(of entry: Entry) throws -> Data {
        let headerOffset = entry.localHeaderOffset
        let headerEnd = headerOffset.addingReportingOverflow(30)
        guard !headerEnd.overflow, headerEnd.partialValue <= data.count,
              try data.readLittleEndianUInt32(at: headerOffset) == Signature.localFileHeader
        else {
            throw HwpError.invalidArchive(
                reason: "local file header signature mismatch for '\(entry.name)'"
            )
        }
        let nameLength = Int(try data.readLittleEndianUInt16(at: headerOffset + 26))
        let extraLength = Int(try data.readLittleEndianUInt16(at: headerOffset + 28))
        let payloadStart = headerEnd.partialValue.addingReportingOverflow(
            nameLength + extraLength
        )
        guard !payloadStart.overflow else {
            throw HwpError.invalidArchive(reason: "truncated entry '\(entry.name)'")
        }
        let payloadEnd = payloadStart.partialValue.addingReportingOverflow(
            entry.compressedSize
        )
        guard !payloadEnd.overflow, payloadEnd.partialValue <= data.count else {
            throw HwpError.invalidArchive(reason: "truncated entry '\(entry.name)'")
        }
        return data[payloadStart.partialValue ..< payloadEnd.partialValue]
    }

    func storedEntryData(
        _ entry: Entry,
        payload: Data,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws -> Data {
        guard entry.compressedSize == entry.uncompressedSize else {
            throw HwpError.invalidArchive(
                reason: "stored entry '\(entry.name)' declares mismatched sizes: " +
                    "\(entry.compressedSize) compressed vs \(entry.uncompressedSize) uncompressed"
            )
        }
        // 두 한도를 따로 두는 계약은 method 0에도 적용된다 — 압축 입력 상한만
        // 작게 잡은 호출자가 stored로 저장된 파트에서 그것을 우회하면 안
        // 된다 (deflate 경로와 같은 검사·같은 순서).
        guard entry.compressedSize <= limits.maxCompressedStreamBytes else {
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: entry.name,
                limit: limits.maxCompressedStreamBytes,
                actual: entry.compressedSize
            )
        }
        guard entry.uncompressedSize <= limits.maxDecompressedStreamBytes else {
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: entry.name,
                limit: limits.maxDecompressedStreamBytes,
                actual: entry.uncompressedSize
            )
        }
        try budget.consume(entry.uncompressedSize, entryName: entry.name)
        // 아카이브 전체 버퍼를 붙잡지 않도록 분리 복사한다.
        return Data(payload)
    }

    func deflatedEntryData(
        _ entry: Entry,
        payload: Data,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws -> Data {
        guard entry.compressedSize <= limits.maxCompressedStreamBytes else {
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: entry.name,
                limit: limits.maxCompressedStreamBytes,
                actual: entry.compressedSize
            )
        }

        let entryLimit = limits.maxDecompressedStreamBytes
        // 선언값(central directory)이 정본이다 — 선언만으로 확정 초과인
        // 엔트리는 풀기 전에 거부한다 (stored 경로와 같은 순서). 아래
        // 스트리밍 한도는 선언을 속이는 payload의 방어로 남는다.
        guard entry.uncompressedSize <= entryLimit else {
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: entry.name,
                limit: entryLimit,
                actual: entry.uncompressedSize
            )
        }
        try budget.validate(entry.uncompressedSize, entryName: entry.name)
        // 위 사전 검사로 선언값이 항상 최소 한도다 — 선언을 스트리밍 한도로
        // 쓰면 작은 압축 입력이 전역 한도까지 증폭 할당을 강제하지 못하고,
        // 한도 초과는 정의상 선언 위반(구조 손상)이다.
        let output: Data
        do {
            output = try HwpInflate.decompress(payload, limit: entry.uncompressedSize)
        } catch HwpInflate.Failure.corrupted {
            throw HwpError.invalidArchive(
                reason: "corrupted deflate stream in '\(entry.name)'"
            )
        } catch HwpInflate.Failure.limitExceeded {
            throw HwpError.invalidArchive(
                reason: "deflated entry '\(entry.name)' inflates beyond its declared size " +
                    "\(entry.uncompressedSize)"
            )
        }
        guard output.count == entry.uncompressedSize else {
            throw HwpError.invalidArchive(
                reason: "deflated entry '\(entry.name)' declares mismatched sizes: " +
                    "\(entry.uncompressedSize) uncompressed vs \(output.count) inflated"
            )
        }
        try budget.consume(output.count, entryName: entry.name)
        return output
    }
}

/// 한 HWPX 파일이 읽어 보유하는 엔트리 바이트 합계 예산.
///
/// `StreamReader`의 집계 예산(`maxAggregateStreamBytes`)과 같은 역할이다 —
/// 개별 엔트리 한도만으로는 유효한 엔트리 다수(구역 XML·BinData)로 집계
/// 메모리 사용량이 무제한이 될 수 있다.
struct HwpxByteBudget {
    let maxAggregateStreamBytes: Int
    private(set) var totalBytes = 0

    init(limits: HwpReadLimits) {
        maxAggregateStreamBytes = limits.maxAggregateStreamBytes
    }

    var remaining: Int {
        max(0, maxAggregateStreamBytes - totalBytes)
    }

    /// 한도−사용량 차와 비교해 Int 오버플로 없이 판정한다
    /// (`StreamReader.consumeAggregateBudget`과 동일 규약). 소비하지 않는
    /// 판정만 — 선언 크기의 사전 거부가 쓴다.
    func validate(_ byteCount: Int, entryName: String) throws {
        guard byteCount <= maxAggregateStreamBytes - totalBytes else {
            let (sum, overflow) = totalBytes.addingReportingOverflow(byteCount)
            throw HwpError.archiveEntrySizeLimitExceeded(
                name: entryName,
                limit: maxAggregateStreamBytes,
                actual: overflow ? Int.max : sum
            )
        }
    }

    mutating func consume(_ byteCount: Int, entryName: String) throws {
        try validate(byteCount, entryName: entryName)
        totalBytes += byteCount
    }
}
