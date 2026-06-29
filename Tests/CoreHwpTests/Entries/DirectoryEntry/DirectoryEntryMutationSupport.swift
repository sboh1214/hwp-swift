@testable import CoreHwp
import Foundation
import Nimble

let directoryEntryOleStorageType = UInt8(1)
let directoryEntryOleStreamType = UInt8(2)

struct DirectoryEntryRename {
    let entryName: String
    let newName: String
    let entryType: UInt8
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    changingEntry entryName: String,
    fromType: UInt8,
    toType: UInt8
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))
    let offset = try directoryEntryTypeOffset(
        in: data,
        entryName: entryName,
        expectedType: fromType
    )
    data[offset] = toType

    return try writeTemporaryDirectoryEntryHwp(data)
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    swappingEntry firstEntryName: String,
    with secondEntryName: String,
    entryType: UInt8
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))
    let firstEncodedName = directoryEntryNamePrefix(firstEntryName)
    let secondEncodedName = directoryEntryNamePrefix(secondEntryName)
    guard firstEncodedName.count == secondEncodedName.count else {
        throw HwpError.invalidOLEFile(
            reason: "Directory entry swap '\(firstEntryName)' <-> '\(secondEntryName)' " +
                "changes name length"
        )
    }

    let firstOffset = try directoryEntryOffset(
        in: data,
        entryName: firstEntryName,
        expectedType: entryType
    )
    let secondOffset = try directoryEntryOffset(
        in: data,
        entryName: secondEntryName,
        expectedType: entryType
    )
    data.replaceSubrange(
        firstOffset ..< firstOffset + secondEncodedName.count,
        with: secondEncodedName
    )
    data.replaceSubrange(
        secondOffset ..< secondOffset + firstEncodedName.count,
        with: firstEncodedName
    )

    return try writeTemporaryDirectoryEntryHwp(data)
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    renamingEntry entryName: String,
    to newName: String,
    entryType: UInt8
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))
    let oldEncodedName = directoryEntryNamePrefix(entryName)
    let newEncodedName = directoryEntryNamePrefix(newName)
    guard oldEncodedName.count == newEncodedName.count else {
        throw HwpError.invalidOLEFile(
            reason: "Directory entry rename '\(entryName)' -> '\(newName)' changes name length"
        )
    }

    let offset = try directoryEntryOffset(
        in: data,
        entryName: entryName,
        expectedType: entryType
    )
    data.replaceSubrange(offset ..< offset + newEncodedName.count, with: newEncodedName)

    return try writeTemporaryDirectoryEntryHwp(data)
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    renamingEntries entries: [DirectoryEntryRename]
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))

    for entry in entries {
        let oldEncodedName = directoryEntryNamePrefix(entry.entryName)
        let newEncodedName = directoryEntryNamePrefix(entry.newName)
        guard oldEncodedName.count == newEncodedName.count else {
            throw HwpError.invalidOLEFile(
                reason: "Directory entry rename '\(entry.entryName)' -> " +
                    "'\(entry.newName)' changes name length"
            )
        }

        let offset = try directoryEntryOffset(
            in: data,
            entryName: entry.entryName,
            expectedType: entry.entryType
        )
        data.replaceSubrange(offset ..< offset + newEncodedName.count, with: newEncodedName)
    }

    return try writeTemporaryDirectoryEntryHwp(data)
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    renamingEntryAllowingLengthChange entryName: String,
    to newName: String,
    entryType: UInt8
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))
    let newEncodedName = directoryEntryNamePrefix(newName)
    guard newEncodedName.count <= directoryEntryNameBufferByteCount else {
        throw HwpError.invalidOLEFile(
            reason: "Directory entry rename '\(entryName)' -> '\(newName)' exceeds name buffer"
        )
    }

    let offset = try directoryEntryOffset(
        in: data,
        entryName: entryName,
        expectedType: entryType
    )
    let paddedName = newEncodedName +
        Data(repeating: 0, count: directoryEntryNameBufferByteCount - newEncodedName.count)
    data.replaceSubrange(
        offset ..< offset + directoryEntryNameBufferByteCount,
        with: paddedName
    )
    data.replaceSubrange(
        offset + directoryEntryNameByteCountOffset ..< offset + directoryEntryTypeOffset,
        with: directoryEntryLittleEndianData(UInt16(newEncodedName.count))
    )

    return try writeTemporaryDirectoryEntryHwp(data)
}

func temporaryDirectoryEntryHwp(
    basedOnFixture fixture: String,
    renamingEntryAllowingLengthChange entryName: String,
    to newName: String,
    fromType: UInt8,
    toType: UInt8
) throws -> URL {
    var data = try Data(contentsOf: hwpURL(#file, fixture))
    let newEncodedName = directoryEntryNamePrefix(newName)
    guard newEncodedName.count <= directoryEntryNameBufferByteCount else {
        throw HwpError.invalidOLEFile(
            reason: "Directory entry rename '\(entryName)' -> '\(newName)' exceeds name buffer"
        )
    }

    let offset = try directoryEntryOffset(
        in: data,
        entryName: entryName,
        expectedType: fromType
    )
    let paddedName = newEncodedName +
        Data(repeating: 0, count: directoryEntryNameBufferByteCount - newEncodedName.count)
    data.replaceSubrange(
        offset ..< offset + directoryEntryNameBufferByteCount,
        with: paddedName
    )
    data.replaceSubrange(
        offset + directoryEntryNameByteCountOffset ..< offset + directoryEntryTypeOffset,
        with: directoryEntryLittleEndianData(UInt16(newEncodedName.count))
    )
    data[offset + directoryEntryTypeOffset] = toType

    return try writeTemporaryDirectoryEntryHwp(data)
}

func removeTemporaryDirectoryEntryFile(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("Failed to remove temporary file: \(error)")
    }
}

private func writeTemporaryDirectoryEntryHwp(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreHwp-\(UUID().uuidString).hwp")
    try data.write(to: url, options: .atomic)
    return url
}

private func directoryEntryTypeOffset(
    in data: Data,
    entryName: String,
    expectedType: UInt8
) throws -> Int {
    try directoryEntryOffset(
        in: data,
        entryName: entryName,
        expectedType: expectedType
    ) + directoryEntryTypeOffset
}

private let directoryEntryNameBufferByteCount = 64
private let directoryEntryNameByteCountOffset = 64
private let directoryEntryTypeOffset = 66

private func directoryEntryOffset(
    in data: Data,
    entryName: String,
    expectedType: UInt8
) throws -> Int {
    let encodedName = directoryEntryNamePrefix(entryName)
    let expectedNameByteCount = UInt16(encodedName.count)
    var searchRange = data.startIndex ..< data.endIndex

    while let range = data.range(of: encodedName, options: [], in: searchRange) {
        let offset = range.lowerBound
        if isMatchingDirectoryEntry(
            data,
            at: offset,
            expectedNameByteCount: expectedNameByteCount,
            expectedType: expectedType
        ) {
            return offset
        }
        searchRange = range.upperBound ..< data.endIndex
    }

    throw HwpError.invalidOLEFile(reason: "Directory entry '\(entryName)' was not found")
}

private func isMatchingDirectoryEntry(
    _ data: Data,
    at offset: Int,
    expectedNameByteCount: UInt16,
    expectedType: UInt8
) -> Bool {
    let nameLengthOffset = offset + directoryEntryNameByteCountOffset
    let typeOffset = offset + directoryEntryTypeOffset
    let colorOffset = offset + 67
    guard colorOffset < data.endIndex,
          let nameByteCount = directoryEntryLittleEndianUInt16(data, at: nameLengthOffset)
    else {
        return false
    }

    return nameByteCount == expectedNameByteCount &&
        data[typeOffset] == expectedType &&
        data[colorOffset] <= 1 &&
        isZeroPaddedDirectoryEntryName(data, at: offset, nameByteCount: nameByteCount)
}

private func isZeroPaddedDirectoryEntryName(
    _ data: Data,
    at offset: Int,
    nameByteCount: UInt16
) -> Bool {
    let nameEndOffset = offset + Int(nameByteCount)
    let bufferEndOffset = offset + directoryEntryNameBufferByteCount
    guard nameEndOffset <= bufferEndOffset, bufferEndOffset <= data.endIndex else {
        return false
    }

    return data[nameEndOffset ..< bufferEndOffset].allSatisfy { $0 == 0 }
}

private func directoryEntryNamePrefix(_ name: String) -> Data {
    var data = Data()
    for codeUnit in name.utf16 {
        data.append(directoryEntryLittleEndianData(UInt16(codeUnit)))
    }
    data.append(directoryEntryLittleEndianData(UInt16(0)))
    return data
}

private func directoryEntryLittleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
    guard offset >= data.startIndex, offset + 1 < data.endIndex else {
        return nil
    }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func directoryEntryLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
