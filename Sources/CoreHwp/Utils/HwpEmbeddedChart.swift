import Foundation

/// BinData `.OLE` 스트림 (내장 개체 CFB)에서 차트 콘텐츠를 꺼내는 헬퍼.
///
/// 한/글의 차트 개체는 gso → OLE 개체 요소 (표 118)로 저장되고, 참조된
/// BinData payload는 4바이트 길이 프리픽스 + CFB (compound file)다.
/// CFB 안의 `OOXMLChartContents` 스트림이 DrawingML 차트 XML
/// (`c:chartSpace`)을 담는다 (한컴오피스 macOS 12.x 실측).
///
/// OLEKit은 miniFAT이 없는 CFB (내장 차트 실측)를 `invalidEmptyStream`으로
/// 거부하므로 여기서는 자체 최소 CFB 리더 (`EmbeddedCompoundFile`)를 쓴다.
public enum HwpEmbeddedChart {
    /// BinData `.OLE` payload에서 OOXML 차트 XML 문자열을 꺼낸다.
    /// 차트 개체가 아니거나 스트림이 없으면 nil.
    public static func chartXML(fromOLEPayload payload: Data) -> String? {
        guard payload.count > 4 else { return nil }
        let cfb = Data(payload.dropFirst(4))
        guard let file = EmbeddedCompoundFile(data: cfb),
              let data = file.stream(named: "OOXMLChartContents")
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// 내장 개체 payload 전용 최소 CFB (compound file binary) 리더.
///
/// 필요한 만큼만 지원한다: v3/v4 헤더, DIFAT 109개 이하 (내장 개체는 수십 KB),
/// FAT/miniFAT 체인, 디렉터리 평면 탐색 (이름으로 스트림 찾기).
struct EmbeddedCompoundFile {
    private static let signature = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let freeSector: UInt32 = 0xFFFF_FFFF

    private let data: Data
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniStreamCutoff: UInt64
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let entries: [DirectoryEntry]

    private struct DirectoryEntry {
        let name: String
        let objectType: UInt8
        let firstSector: UInt32
        let streamSize: UInt64
    }

    init?(data: Data) {
        guard data.count >= 512, data.prefix(8) == Self.signature else { return nil }
        self.data = data

        guard let sectorShift = data.readUInt16(at: 30),
              let miniSectorShift = data.readUInt16(at: 32),
              let fatSectorCount = data.readUInt32(at: 44),
              let firstDirectorySector = data.readUInt32(at: 48),
              let cutoff = data.readUInt32(at: 56),
              let firstMiniFATSector = data.readUInt32(at: 60),
              let miniFATSectorCount = data.readUInt32(at: 64),
              sectorShift >= 7, sectorShift <= 12, miniSectorShift <= sectorShift
        else { return nil }
        let sectorSize = 1 << Int(sectorShift)
        self.sectorSize = sectorSize
        miniSectorSize = 1 << Int(miniSectorShift)
        miniStreamCutoff = UInt64(cutoff)

        guard let fatTable = Self.fatTable(
            data, sectorSize: sectorSize, fatSectorCount: fatSectorCount
        ) else { return nil }
        fat = fatTable

        guard let directoryData = Self.chainData(
            data, fat: fatTable, sectorSize: sectorSize,
            firstSector: firstDirectorySector, size: nil
        ) else { return nil }
        entries = Self.directoryEntries(directoryData, sectorShift: sectorShift)

        // miniFAT (없으면 빈 체인)
        if miniFATSectorCount > 0, firstMiniFATSector != Self.endOfChain,
           firstMiniFATSector != Self.freeSector,
           let miniFATData = Self.chainData(
               data, fat: fatTable, sectorSize: sectorSize,
               firstSector: firstMiniFATSector, size: nil
           )
        {
            miniFAT = Self.uint32Array(miniFATData)
        } else {
            miniFAT = []
        }
    }

    /// DIFAT: 헤더 내 109개까지만 지원 (내장 개체 크기에 충분)
    private static func fatTable(
        _ data: Data,
        sectorSize: Int,
        fatSectorCount: UInt32
    ) -> [UInt32]? {
        guard fatSectorCount <= 109 else { return nil }
        var table: [UInt32] = []
        for index in 0 ..< Int(fatSectorCount) {
            guard let fatSector = data.readUInt32(at: 76 + index * 4),
                  let sector = sectorData(data, sectorSize: sectorSize, fatSector)
            else { return nil }
            table.append(contentsOf: uint32Array(sector))
        }
        return table
    }

    /// 디렉터리 스트림 → 128바이트 엔트리 배열 (손상 엔트리는 건너뜀)
    private static func directoryEntries(
        _ directoryData: Data,
        sectorShift: UInt16
    ) -> [DirectoryEntry] {
        var parsed: [DirectoryEntry] = []
        var offset = 0
        while offset + 128 <= directoryData.count {
            let entry = Data(directoryData[offset ..< offset + 128])
            offset += 128
            guard let nameLength = entry.readUInt16(at: 64),
                  nameLength >= 2, nameLength <= 64,
                  let firstSector = entry.readUInt32(at: 116),
                  let streamSize = entry.readUInt64(at: 120)
            else { continue }
            let nameData = entry.prefix(Int(nameLength) - 2)
            parsed.append(DirectoryEntry(
                name: String(data: nameData, encoding: .utf16LittleEndian) ?? "",
                objectType: entry[entry.startIndex + 66],
                firstSector: firstSector,
                // v3 CFB는 상위 4바이트가 쓰레기일 수 있다 (스펙 권고: 무시)
                streamSize: sectorShift == 9 ? streamSize & 0xFFFF_FFFF : streamSize
            ))
        }
        return parsed
    }

    /// 이름이 일치하는 첫 스트림 엔트리의 내용 (스토리지 계층 무시 — 평면 탐색)
    func stream(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.objectType == 2 && $0.name == name })
        else { return nil }
        guard entry.streamSize > 0 else { return Data() }
        // v4 CFB의 streamSize는 신뢰할 수 없는 UInt64 — Int.max 초과는 거부하고
        // 실제 CFB 크기로 상한해 이후 Int 변환/prefix가 트랩하지 않게 한다.
        guard let size = Self.boundedSize(entry.streamSize, availableBytes: data.count)
        else { return nil }

        if entry.streamSize < miniStreamCutoff {
            return miniStreamData(entry, streamSize: size)
        }
        return Self.chainData(
            data, fat: fat, sectorSize: sectorSize,
            firstSector: entry.firstSector, size: size
        )
    }

    /// mini 스트림: root 엔트리의 일반 체인이 컨테이너, miniFAT이 체인
    private func miniStreamData(_ entry: DirectoryEntry, streamSize: Int) -> Data? {
        guard let root = entries.first(where: { $0.objectType == 5 }),
              let rootSize = Self.boundedSize(root.streamSize, availableBytes: data.count),
              let container = Self.chainData(
                  data, fat: fat, sectorSize: sectorSize,
                  firstSector: root.firstSector, size: rootSize
              )
        else { return nil }

        var result = Data()
        var sector = entry.firstSector
        var visited = Set<UInt32>()
        while sector != Self.endOfChain, result.count < streamSize {
            // 순환 miniFAT 체인 방어 — 같은 mini 섹터 재방문 즉시 중단
            guard visited.insert(sector).inserted,
                  Int(sector) < miniFAT.count || sector != Self.freeSector
            else { return nil }
            let start = Int(sector) * miniSectorSize
            guard start + miniSectorSize <= container.count else { return nil }
            let base = container.startIndex + start
            result.append(container[base ..< base + miniSectorSize])
            guard Int(sector) < miniFAT.count else { return nil }
            sector = miniFAT[Int(sector)]
        }
        guard result.count >= streamSize else { return nil }
        return Data(result.prefix(streamSize))
    }

    /// FAT 체인을 따라 스트림 데이터를 모은다. size가 nil이면 체인 끝까지.
    private static func chainData(
        _ data: Data,
        fat: [UInt32],
        sectorSize: Int,
        firstSector: UInt32,
        size: Int?
    ) -> Data? {
        var result = Data()
        var sector = firstSector
        var visited = Set<UInt32>()
        while sector != endOfChain, sector != freeSector {
            // 순환 FAT 체인(자기참조 등) 방어 — 같은 섹터 재방문 즉시 중단해
            // 손상 파일이 같은 섹터를 무한 append하며 OOM되는 것을 막는다.
            guard visited.insert(sector).inserted,
                  let sectorData = sectorData(data, sectorSize: sectorSize, sector)
            else { return nil }
            result.append(sectorData)
            if let size, result.count >= size {
                break
            }
            guard Int(sector) < fat.count else { return nil }
            sector = fat[Int(sector)]
        }
        if let size {
            guard result.count >= size else { return nil }
            return Data(result.prefix(size))
        }
        return result
    }

    /// 섹터 번호 → 바이트 (섹터 0은 헤더 뒤부터). 마지막 섹터는 잘릴 수 있다.
    private static func sectorData(
        _ data: Data,
        sectorSize: Int,
        _ sector: UInt32
    ) -> Data? {
        // 섹터 n은 (n+1)*sectorSize에서 시작한다 — 헤더가 한 섹터로 패딩되기
        // 때문 (v3 512B: 512+n*512, v4 4096B: 4096+n*4096과 동일).
        let start = (Int(sector) + 1) * sectorSize
        guard start < data.count else { return nil }
        let end = min(start + sectorSize, data.count)
        let base = data.startIndex
        return Data(data[(base + start) ..< (base + end)])
    }

    /// 선언된 스트림 크기를 Int로 안전 변환하고 실제 CFB 크기로 상한한다.
    /// Int.max를 넘는 (신뢰할 수 없는 v4 UInt64) 값은 nil.
    private static func boundedSize(_ declared: UInt64, availableBytes: Int) -> Int? {
        guard let size = Int(exactly: declared) else { return nil }
        return min(size, availableBytes)
    }

    private static func uint32Array(_ data: Data) -> [UInt32] {
        stride(from: 0, to: data.count - 3, by: 4).compactMap {
            data.readUInt32(at: $0)
        }
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16? {
        do {
            return try readLittleEndianUInt16(at: offset)
        } catch {
            return nil
        }
    }

    func readUInt32(at offset: Int) -> UInt32? {
        do {
            return try readLittleEndianUInt32(at: offset)
        } catch {
            return nil
        }
    }

    func readUInt64(at offset: Int) -> UInt64? {
        guard let low = readUInt32(at: offset), let high = readUInt32(at: offset + 4)
        else { return nil }
        return UInt64(high) << 32 | UInt64(low)
    }
}
