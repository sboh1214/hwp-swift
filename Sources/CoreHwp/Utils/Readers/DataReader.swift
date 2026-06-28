import Foundation

struct DataReader {
    private let data: Data
    private var offset: Int = 0

    init(_ data: Data) {
        self.data = data
    }

    var isEOF: Bool {
        offset == data.count
    }

    var remainBytes: Int {
        data.count - offset
    }

    var byteOffset: Int {
        offset
    }

    func consumedData(from startOffset: Int) throws -> Data {
        guard startOffset >= 0, startOffset <= offset else {
            throw HwpError.invalidDataLength(
                length: "offset \(startOffset) for \(offset) consumed bytes"
            )
        }
        let startIndex = data.index(data.startIndex, offsetBy: startOffset)
        let endIndex = data.index(data.startIndex, offsetBy: offset)
        return data[startIndex ..< endIndex]
    }

    @discardableResult mutating func readBytes(_ length: some BinaryInteger) throws -> Data {
        let byteCount = try validatedLength(length)
        guard byteCount <= remainBytes else {
            throw HwpError.truncatedData(expected: byteCount, actual: remainBytes)
        }
        let startIndex = data.index(data.startIndex, offsetBy: offset)
        let endIndex = data.index(startIndex, offsetBy: byteCount)
        defer {
            offset += byteCount
        }
        return data[startIndex ..< endIndex]
    }

    mutating func readToEnd() throws -> Data {
        try readBytes(data.count - offset)
    }

    mutating func read<T>(_ type: T.Type) throws -> T {
        let length = try byteLength(for: type)
        return try readBytes(length).withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw HwpError.truncatedData(expected: length, actual: 0)
            }
            return baseAddress.loadUnaligned(as: T.self)
        }
    }

    mutating func read<T>(_: T.Type, _ length: some BinaryInteger) throws -> [T] {
        let count = try validatedLength(length)
        let typeByteLength = try byteLength(for: T.self)
        let requiredByteCount = try byteCount(typeByteLength, multipliedBy: count)
        guard requiredByteCount <= remainBytes else {
            throw HwpError.truncatedData(expected: requiredByteCount, actual: remainBytes)
        }

        var array = [T]()
        for _ in 0 ..< count {
            array.append(try read(T.self))
        }
        return array
    }

    private func validatedLength(_ length: some BinaryInteger) throws -> Int {
        guard let count = Int(exactly: length), count >= 0 else {
            throw HwpError.invalidDataLength(length: String(describing: length))
        }
        return count
    }

    private func byteLength(for type: Any.Type) throws -> Int {
        switch type {
        case is UInt8.Type, is Int8.Type:
            return 1
        case is UInt16.Type, is Int16.Type:
            return 2
        case is UInt32.Type, is Int32.Type:
            return 4
        default:
            throw HwpError.unsupportedDataReadType(type: String(describing: type))
        }
    }

    private func byteCount(_ byteLength: Int, multipliedBy count: Int) throws -> Int {
        let result = byteLength.multipliedReportingOverflow(by: count)
        guard !result.overflow else {
            throw HwpError.invalidDataLength(length: "\(count) values of \(byteLength) bytes")
        }
        return result.partialValue
    }
}
