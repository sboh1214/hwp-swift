import Foundation
import OLEKit

struct StreamReader {
    private let ole: OLEFile
    private let streams: [String: DirectoryEntry]
    private let readLimits: HwpReadLimits
    /// 참조 타입: 비변이 read 호출들이 파일 한 건의 읽기 총량을 공유 누적한다.
    private let aggregateUsage = AggregateUsage()

    private final class AggregateUsage {
        var totalBytes = 0
    }

    init(
        _ ole: OLEFile,
        _ streams: [String: DirectoryEntry],
        readLimits: HwpReadLimits = .default
    ) {
        self.ole = ole
        self.streams = streams
        self.readLimits = readLimits
    }

    func getDataFromStream(_ streamName: HwpStreamName, _ isCompressed: Bool) throws -> Data {
        guard let stream = streams[streamName.rawValue] else {
            throw HwpError.streamDoesNotExist(name: streamName)
        }
        try Self.validateEntryType(stream, expectedType: .stream, for: streamName)
        return try readData(stream, isCompressed, streamName)
    }

    func getOptionalDataFromStream(
        _ streamName: HwpStreamName,
        _ isCompressed: Bool
    ) throws -> Data? {
        guard let stream = streams[streamName.rawValue] else {
            return nil
        }
        try Self.validateEntryType(stream, expectedType: .stream, for: streamName)
        return try readData(stream, isCompressed, streamName)
    }

    func getDataFromStorage(
        _ streamName: HwpStreamName,
        _ isCompressed: Bool,
        expectedCount: Int? = nil
    ) throws -> [Data] {
        guard let storage = streams[streamName.rawValue] else {
            throw HwpError.streamDoesNotExist(name: streamName)
        }
        try Self.validateEntryType(storage, expectedType: .storage, for: streamName)
        return try requiredSortedStorageChildren(
            storage,
            for: streamName,
            expectedCount: expectedCount
        )
        .map { try readData($0, isCompressed, streamName) }
    }

    func getOptionalNamedDataFromStorage(
        _ streamName: HwpStreamName,
        _ isCompressed: Bool,
        expectedChildCount: Int? = nil
    ) throws -> [(name: String, data: Data)] {
        try getOptionalNamedDataFromStorage(
            streamName, expectedChildCount: expectedChildCount
        ) { _ in isCompressed }
    }

    private func readData(
        _ stream: DirectoryEntry,
        _ isCompressed: Bool,
        _ streamName: HwpStreamName
    ) throws -> Data {
        let inputLimit = streamByteLimit(isCompressed: isCompressed)
        try Self.validateStreamByteCount(stream.streamSize, limit: inputLimit, for: streamName)

        let data: Data
        do {
            let reader = try ole.stream(stream)
            data = reader.readDataToEnd()
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }

        try Self.validateStreamByteCount(data.count, limit: inputLimit, for: streamName)
        let result = isCompressed ? try decompress(data, for: streamName) : data
        try consumeAggregateBudget(result.count, for: streamName)
        return result
    }

    private static func validateEntryType(
        _ entry: DirectoryEntry,
        expectedType: StorageType,
        for streamName: HwpStreamName
    ) throws {
        guard entry.type == expectedType else {
            throw HwpError.invalidOLEFile(
                reason: "Directory entry '\(streamName.rawValue)' is \(entry.type), " +
                    "expected \(expectedType)"
            )
        }
    }

    static func sortedStorageChildNames(
        _ names: [String],
        for streamName: HwpStreamName
    ) -> [String] {
        sortedStorageChildNamesWithoutRequiredValidation(names, for: streamName)
    }

    static func requiredSortedStorageChildNames(
        _ names: [String],
        for streamName: HwpStreamName,
        expectedCount: Int? = nil
    ) throws -> [String] {
        let children = names.map { (name: $0, type: StorageType.stream) }
        return try requiredSortedStorageChildNames(
            children,
            for: streamName,
            expectedCount: expectedCount
        )
    }

    static func requiredSortedStorageChildNames(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName,
        expectedCount: Int? = nil
    ) throws -> [String] {
        try validateUniqueStorageChildNames(children.map(\.name), for: streamName)
        try validateRequiredStorageChildNames(children, for: streamName)
        let sortedNames = sortedStorageChildrenWithoutRequiredValidation(children, for: streamName)
            .map(\.name)
        try validateRequiredStorageChildren(
            sortedNames,
            for: streamName,
            expectedCount: expectedCount
        )
        return sortedNames
    }

    private static func sortedStorageChildNamesWithoutRequiredValidation(
        _ names: [String],
        for streamName: HwpStreamName
    ) -> [String] {
        let children = names.map { (name: $0, type: StorageType.stream) }
        return sortedStorageChildrenWithoutRequiredValidation(children, for: streamName)
            .map(\.name)
    }

    static func sortedStorageChildNames(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName
    ) -> [String] {
        sortedStorageChildrenWithoutRequiredValidation(children, for: streamName)
            .map(\.name)
    }

    private static func shouldIncludeStorageChild(
        _ name: String,
        _ type: StorageType,
        for streamName: HwpStreamName
    ) -> Bool {
        guard type == .stream else {
            return false
        }
        if streamName == .bodyText {
            return sectionIndex(name) != nil
        }
        return true
    }

    private static func sectionIndex(_ name: String) -> Int? {
        guard name.hasPrefix("Section") else {
            return nil
        }
        let suffix = name.dropFirst("Section".count)
        guard isASCIIIntegerSuffix(suffix),
              let index = Int(suffix),
              index >= 0,
              String(index) == String(suffix)
        else {
            return nil
        }
        return index
    }

    private static func isASCIIIntegerSuffix(_ suffix: Substring) -> Bool {
        !suffix.isEmpty && suffix.unicodeScalars.allSatisfy {
            $0.value >= 48 && $0.value <= 57
        }
    }

    private static func isMalformedSectionName(_ name: String) -> Bool {
        guard name.hasPrefix("Section") else {
            return false
        }
        let suffix = name.dropFirst("Section".count)
        guard isASCIIIntegerSuffix(suffix),
              let index = Int(suffix)
        else {
            return true
        }
        return String(index) != String(suffix)
    }

    private static func storageChildNamePrecedes(
        _ lhs: String,
        _ rhs: String,
        for streamName: HwpStreamName
    ) -> Bool {
        if streamName == .bodyText,
           let lhsIndex = sectionIndex(lhs),
           let rhsIndex = sectionIndex(rhs),
           lhsIndex != rhsIndex
        {
            return lhsIndex < rhsIndex
        }
        return lhs < rhs
    }

    private static func validateRequiredStorageChildren(
        _ names: [String],
        for streamName: HwpStreamName,
        expectedCount: Int? = nil
    ) throws {
        guard streamName == .bodyText else {
            return
        }

        if let expectedCount, expectedCount <= 0 {
            throw HwpError.invalidRecordTree(
                reason: "BodyText sectionSize \(expectedCount) is invalid"
            )
        }

        guard !names.isEmpty else {
            throw HwpError.streamDoesNotExist(name: streamName)
        }

        let sectionIndexes = names.compactMap(sectionIndex)
        for (expectedIndex, sectionIndex) in sectionIndexes.enumerated()
            where sectionIndex != expectedIndex
        {
            throw HwpError.invalidRecordTree(
                reason: "BodyText sections must start at Section0 and be contiguous"
            )
        }

        if let expectedCount, names.count != expectedCount {
            throw HwpError.invalidRecordTree(
                reason: "BodyText section count \(names.count) != sectionSize \(expectedCount)"
            )
        }
    }

    private static func validateRequiredStorageChildNames(
        _ names: [String],
        for streamName: HwpStreamName
    ) throws {
        guard streamName == .bodyText else {
            return
        }

        if let malformedName = names.first(where: isMalformedSectionName) {
            throw HwpError.invalidRecordTree(
                reason: "BodyText section name \(malformedName) is malformed"
            )
        }

        if let unexpectedName = names.first(where: { sectionIndex($0) == nil }) {
            throw HwpError.invalidRecordTree(
                reason: "BodyText directory entry \(unexpectedName) is unexpected"
            )
        }
    }

    private static func validateRequiredStorageChildNames(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName
    ) throws {
        try validateRequiredStorageChildTypes(children, for: streamName)
        try validateRequiredStorageChildNames(
            children.map(\.name),
            for: streamName
        )
    }

    private func requiredSortedStorageChildren(
        _ storage: DirectoryEntry,
        for streamName: HwpStreamName,
        expectedCount: Int? = nil
    ) throws -> [DirectoryEntry] {
        try Self.validateUniqueStorageChildNames(storage.children.map(\.name), for: streamName)
        try Self.validateRequiredStorageChildNames(
            storage.children.map { (name: $0.name, type: $0.type) },
            for: streamName
        )
        let children = sortedStorageChildrenWithoutRequiredValidation(storage, for: streamName)
        try Self.validateRequiredStorageChildren(
            children.map(\.name),
            for: streamName,
            expectedCount: expectedCount
        )
        return children
    }

    private func sortedStorageChildrenWithoutRequiredValidation(
        _ storage: DirectoryEntry,
        for streamName: HwpStreamName
    ) -> [DirectoryEntry] {
        storage.children
            .filter { Self.shouldIncludeStorageChild($0.name, $0.type, for: streamName) }
            .sorted { lhs, rhs in
                Self.storageChildNamePrecedes(lhs.name, rhs.name, for: streamName)
            }
    }

    private static func sortedStorageChildrenWithoutRequiredValidation(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName
    ) -> [(name: String, type: StorageType)] {
        children
            .filter { shouldIncludeStorageChild($0.name, $0.type, for: streamName) }
            .sorted { lhs, rhs in
                storageChildNamePrecedes(lhs.name, rhs.name, for: streamName)
            }
    }
}

extension StreamReader {
    func getOptionalNamedDataFromStorage(
        _ streamName: HwpStreamName,
        expectedChildCount: Int? = nil,
        compressionByChildName: (String) -> Bool
    ) throws -> [(name: String, data: Data)] {
        guard let storage = streams[streamName.rawValue] else {
            return []
        }
        try Self.validateEntryType(storage, expectedType: .storage, for: streamName)
        try Self.validateUniqueStorageChildNames(storage.children.map(\.name), for: streamName)
        try Self.validateOptionalStorageChildTypes(
            storage.children.map { (name: $0.name, type: $0.type) },
            for: streamName
        )
        let children = sortedStorageChildrenWithoutRequiredValidation(storage, for: streamName)
        // 아는 구역 수와 다른 자식 구성은 압축 해제 전에 거부한다 — 초과분을
        // 잘라 내면 뒤에 정렬된 자식이 조용히 사라져 남은 N개가 구역 검증을
        // 통과하고, 손상/stale ViewText가 유효한 BodyText를 대체한다 (R69 #2).
        // 거부는 호출부의 빈 ViewText 폴백으로 이어지고, 초과분을 읽지 않으므로
        // 집계 압축 해제량 방어도 유지된다 (R43 #1).
        if let expectedChildCount, children.count != expectedChildCount {
            throw HwpError.invalidRecordTree(
                reason: "\(streamName.rawValue) child count \(children.count) " +
                    "!= \(expectedChildCount)"
            )
        }
        return try children.map { entry in
            try (entry.name, readData(entry, compressionByChildName(entry.name), streamName))
        }
    }
}

private extension StreamReader {
    func streamByteLimit(isCompressed: Bool) -> Int {
        if isCompressed {
            return readLimits.maxCompressedStreamBytes
        }
        return readLimits.maxDecompressedStreamBytes
    }

    func consumeAggregateBudget(_ byteCount: Int, for streamName: HwpStreamName) throws {
        // 한도−사용량 차와 비교해 Int 오버플로 없이 판정한다 (보안 한도, R55 P1).
        guard byteCount <= readLimits.maxAggregateStreamBytes - aggregateUsage.totalBytes else {
            let (sum, overflow) = aggregateUsage.totalBytes.addingReportingOverflow(byteCount)
            throw HwpError.aggregateStreamSizeLimitExceeded(
                name: streamName,
                limit: readLimits.maxAggregateStreamBytes,
                actual: overflow ? Int.max : sum
            )
        }
        aggregateUsage.totalBytes += byteCount
    }

    /// 압축 해제 **도중** 상한을 걸어 bomb이 상한을 넘는 순간 중단시킨다.
    /// 상한은 두 한도의 min이지만 보고하는 error와 `limit`은 실제로 걸린 쪽의
    /// 원래 한도를 유지하고, 같으면 개별 stream 한도를 우선한다 (후처리 거부
    /// 시절의 검사 순서와 동일). 규칙 전문은 `Sources/CoreHwp/AGENTS.md` 참조.
    func decompress(_ data: Data, for streamName: HwpStreamName) throws -> Data {
        let streamLimit = readLimits.maxDecompressedStreamBytes
        let remainingAggregate = max(
            0, readLimits.maxAggregateStreamBytes - aggregateUsage.totalBytes
        )
        let limit = min(streamLimit, remainingAggregate)

        do {
            return try HwpInflate.decompress(data, limit: limit)
        } catch HwpInflate.Failure.corrupted {
            throw HwpError.streamDecompressFailed(name: streamName)
        } catch let HwpInflate.Failure.limitExceeded(produced) {
            guard limit == streamLimit else {
                let (sum, overflow) = aggregateUsage.totalBytes
                    .addingReportingOverflow(produced)
                throw HwpError.aggregateStreamSizeLimitExceeded(
                    name: streamName,
                    limit: readLimits.maxAggregateStreamBytes,
                    actual: overflow ? Int.max : sum
                )
            }
            throw HwpError.streamSizeLimitExceeded(
                name: streamName, limit: streamLimit, actual: produced
            )
        }
    }

    static func validateStreamByteCount(
        _ byteCount: UInt64,
        limit: Int,
        for streamName: HwpStreamName
    ) throws {
        guard byteCount <= UInt64(limit) else {
            throw HwpError.streamSizeLimitExceeded(
                name: streamName,
                limit: limit,
                actual: clampedInt(byteCount)
            )
        }
    }

    static func validateStreamByteCount(
        _ byteCount: Int,
        limit: Int,
        for streamName: HwpStreamName
    ) throws {
        guard byteCount <= limit else {
            throw HwpError.streamSizeLimitExceeded(
                name: streamName,
                limit: limit,
                actual: byteCount
            )
        }
    }

    private static func clampedInt(_ value: UInt64) -> Int {
        if value > UInt64(Int.max) {
            return Int.max
        }
        return Int(value)
    }
}

private extension StreamReader {
    static func validateOptionalStorageChildTypes(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName
    ) throws {
        guard streamName == .binData else {
            return
        }

        if let child = children.first(where: { $0.type != .stream }) {
            throw HwpError.invalidOLEFile(
                reason: "Directory entry '\(streamName.rawValue)/\(child.name)' is " +
                    "\(child.type), expected stream"
            )
        }
    }

    static func validateRequiredStorageChildTypes(
        _ children: [(name: String, type: StorageType)],
        for streamName: HwpStreamName
    ) throws {
        guard streamName == .bodyText else {
            return
        }

        if let child = children.first(where: {
            sectionIndex($0.name) != nil && $0.type != .stream
        }) {
            throw HwpError.invalidOLEFile(
                reason: "Directory entry '\(streamName.rawValue)/\(child.name)' is " +
                    "\(child.type), expected stream"
            )
        }
    }
}

extension StreamReader {
    static func validateUniqueStorageChildNames(
        _ names: [String],
        for streamName: HwpStreamName
    ) throws {
        var seenNames = Set<String>()
        var duplicateNames = Set<String>()

        for name in names where !seenNames.insert(name).inserted {
            duplicateNames.insert(name)
        }

        guard duplicateNames.isEmpty else {
            throw HwpError.invalidOLEFile(
                reason: "Duplicate \(streamName.rawValue) directory entry names: " +
                    duplicateNames.sorted().joined(separator: ", ")
            )
        }
    }

    static func rootStreams(from entries: [DirectoryEntry]) throws -> [String: DirectoryEntry] {
        var streams = [String: DirectoryEntry]()
        var duplicateNames = [String]()

        for entry in entries {
            if streams[entry.name] != nil {
                duplicateNames.append(entry.name)
            } else {
                streams[entry.name] = entry
            }
        }

        guard duplicateNames.isEmpty else {
            throw HwpError.invalidOLEFile(
                reason: "Duplicate root directory entry names: " +
                    duplicateNames.sorted().joined(separator: ", ")
            )
        }

        return streams
    }
}
