import Foundation
import OLEKit
import SWCompression

struct StreamReader {
    private let ole: OLEFile
    private let streams: [String: DirectoryEntry]
    private let readLimits: HwpReadLimits

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
        _ isCompressed: Bool
    ) throws -> [(name: String, data: Data)] {
        try getOptionalNamedDataFromStorage(streamName) { _ in isCompressed }
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
        if isCompressed {
            return try decompress(data, for: streamName)
        }
        return data
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
        return try sortedStorageChildrenWithoutRequiredValidation(
            storage,
            for: streamName
        ).map { entry in
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

    func decompress(_ data: Data, for streamName: HwpStreamName) throws -> Data {
        let decompressed: Data
        do {
            decompressed = try Deflate.decompress(data: data)
        } catch {
            throw HwpError.streamDecompressFailed(name: streamName)
        }

        try Self.validateStreamByteCount(
            decompressed.count,
            limit: readLimits.maxDecompressedStreamBytes,
            for: streamName
        )
        return decompressed
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
