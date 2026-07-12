import Foundation

struct DataReader {
    private let data: Data
    private var offset: Int = 0
    /// 로드 옵션 — rawPayload 보존 여부를 파싱 트리 전체에 전파한다.
    let options: HwpLoadOptions

    init(_ data: Data, options: HwpLoadOptions = .default) {
        self.data = data
        self.options = options
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

    /// 보존용 원본 슬라이스. `preserveRawPayload == false`면 경계 검증만 하고
    /// 빈 Data를 반환해 스트림 버퍼 참조가 남지 않게 한다.
    func consumedData(from startOffset: Int) throws -> Data {
        guard startOffset >= 0, startOffset <= offset else {
            throw HwpError.invalidDataLength(
                length: "offset \(startOffset) for \(offset) consumed bytes"
            )
        }
        guard options.preserveRawPayload else {
            return Data()
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

    /// 스칼라 읽기 — 핫패스 (문자·모양 엔트리마다 호출)라 `Data` 슬라이스를
    /// 만들지 않고 버퍼에서 직접 load한다. 경계 검증은 readBytes와 동일
    /// (읽기 전 truncatedData).
    mutating func read<T>(_ type: T.Type) throws -> T {
        let length = try byteLength(for: type)
        guard length <= remainBytes else {
            throw HwpError.truncatedData(expected: length, actual: remainBytes)
        }
        defer {
            offset += length
        }
        return data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }

    mutating func read<T>(_: T.Type, _ length: some BinaryInteger) throws -> [T] {
        let count = try validatedLength(length)
        let typeByteLength = try byteLength(for: T.self)
        let requiredByteCount = try byteCount(typeByteLength, multipliedBy: count)
        guard requiredByteCount <= remainBytes else {
            throw HwpError.truncatedData(expected: requiredByteCount, actual: remainBytes)
        }
        defer {
            offset += requiredByteCount
        }
        let start = offset
        return data.withUnsafeBytes { buffer in
            (0 ..< count).map { index in
                buffer.loadUnaligned(
                    fromByteOffset: start + index * typeByteLength,
                    as: T.self
                )
            }
        }
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
