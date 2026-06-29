import Foundation

/// Data to [bytes]
extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }

    var bits: [Bool] {
        reduce([Bool]()) { $0 + $1.bits }
    }

    var stringASCII: String? {
        guard allSatisfy({ $0 < 0x80 }) else {
            return nil
        }
        return String(data: self, encoding: .ascii)
    }

    func readUInt8(at offset: Int) throws -> UInt8 {
        try readFixedWidthInteger(UInt8.self, at: offset)
    }

    func readLittleEndianUInt16(at offset: Int) throws -> UInt16 {
        UInt16(littleEndian: try readFixedWidthInteger(UInt16.self, at: offset))
    }

    func readLittleEndianUInt32(at offset: Int) throws -> UInt32 {
        UInt32(littleEndian: try readFixedWidthInteger(UInt32.self, at: offset))
    }

    func littleEndianUInt16ArrayIfAligned() -> [UInt16]? {
        guard count.isMultiple(of: MemoryLayout<UInt16>.size) else {
            return nil
        }

        do {
            return try stride(from: 0, to: count, by: MemoryLayout<UInt16>.size)
                .map { try readLittleEndianUInt16(at: $0) }
        } catch {
            return nil
        }
    }

    func littleEndianUInt32ArrayWithTrailing(
        minimumValueCount: Int = 0
    ) -> (values: [UInt32], rawTrailing: Data)? {
        guard minimumValueCount >= 0 else {
            return nil
        }

        let wordByteCount = MemoryLayout<UInt32>.size
        let wordCount = count / wordByteCount
        guard wordCount >= minimumValueCount else {
            return nil
        }

        do {
            let values = try (0 ..< wordCount).map { index in
                try readLittleEndianUInt32(at: index * wordByteCount)
            }
            return (
                values: values,
                rawTrailing: Data(dropFirst(wordCount * wordByteCount))
            )
        } catch {
            return nil
        }
    }

    private func readFixedWidthInteger<T: FixedWidthInteger>(
        _: T.Type,
        at offset: Int
    ) throws -> T {
        guard offset >= 0 else {
            throw HwpError.invalidDataLength(length: "offset \(offset)")
        }

        let byteCount = MemoryLayout<T>.size
        let endOffset = offset.addingReportingOverflow(byteCount)
        guard !endOffset.overflow else {
            throw HwpError.invalidDataLength(length: "offset \(offset) + \(byteCount) bytes")
        }
        guard offset <= count, endOffset.partialValue <= count else {
            let actual = offset < count ? count - offset : 0
            throw HwpError.truncatedData(expected: byteCount, actual: actual)
        }

        return withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }
}
