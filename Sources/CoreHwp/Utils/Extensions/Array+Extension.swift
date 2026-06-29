import Foundation

extension Array {
    /**
     * ## Examples:
     * var arr = [0,1,2,3]
     * arr.remove((0..<2)) // 0,1
     * arr // 2,3
     */
    mutating func pop(_ count: some BinaryInteger) throws -> Array {
        guard let count = Int(exactly: count), count >= 0 else {
            throw HwpError.invalidRecordTree(reason: "invalid record count \(count)")
        }
        guard count <= self.count else {
            throw HwpError.invalidRecordTree(
                reason: "record count \(count) exceeds available child records \(self.count)"
            )
        }

        let values = Array(self[0 ..< count])
        removeSubrange(0 ..< count)
        return values
    }
}

public extension [WCHAR] {
    var string: String {
        get throws {
            try decodedWCHARString(self)
        }
    }

    var stringIfValid: String? {
        do {
            return try string
        } catch {
            return nil
        }
    }

    init(_ string: String) {
        self = string.utf16.map { $0 }
    }
}

private func decodedWCHARString(_ values: [WCHAR]) throws -> String {
    var result = ""
    var index = values.startIndex

    while index < values.endIndex {
        let value = values[index]

        if isHighSurrogate(value) {
            let nextIndex = values.index(after: index)
            guard nextIndex < values.endIndex, isLowSurrogate(values[nextIndex]) else {
                throw HwpError.invalidUnicodeScalar(value: value)
            }

            let scalarValue = 0x10000
                + ((UInt32(value) - 0xD800) << 10)
                + (UInt32(values[nextIndex]) - 0xDC00)
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw HwpError.invalidUnicodeScalar(value: value)
            }

            result.append(Character(scalar))
            index = values.index(after: nextIndex)
        } else {
            guard !isLowSurrogate(value),
                  let scalar = UnicodeScalar(UInt32(value))
            else {
                throw HwpError.invalidUnicodeScalar(value: value)
            }

            result.append(Character(scalar))
            index = values.index(after: index)
        }
    }

    return result
}

private func isHighSurrogate(_ value: WCHAR) -> Bool {
    value >= 0xD800 && value <= 0xDBFF
}

private func isLowSurrogate(_ value: WCHAR) -> Bool {
    value >= 0xDC00 && value <= 0xDFFF
}

/// [bytes] to Data
extension [UInt8] {
    var data: Data {
        Data(self)
    }
}
