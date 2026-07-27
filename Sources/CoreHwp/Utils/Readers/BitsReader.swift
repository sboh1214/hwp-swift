import Foundation

/// 정수 속성값의 LSB-first 비트 리더. 속성 파싱 핫패스에서 쓰이므로
/// [Bool] 배열을 만들지 않고 시프트/마스크로 직접 읽는다
/// (readBits의 [Bool] 반환 API는 호출 시에만 생성 — 사용처 무수정).
struct BitsReader<T: BinaryInteger> {
    private let value: T
    private let bitCount: Int
    private var offset: Int = 0

    init(from int: T) {
        value = int
        bitCount = int.bitWidth
    }

    var isEOF: Bool {
        offset == bitCount
    }

    var remainBits: Int {
        bitCount - offset
    }

    private func bit(at position: Int) -> Bool {
        (value >> position) & 1 == 1
    }

    mutating func readBit() throws -> Bool {
        guard remainBits >= 1 else {
            throw HwpError.truncatedBits(expected: 1, actual: remainBits)
        }
        defer {
            offset += 1
        }
        return bit(at: offset)
    }

    @discardableResult mutating func readBits(_ count: Int) throws -> [Bool] {
        guard count >= 0 else {
            throw HwpError.invalidDataLength(length: String(count))
        }
        guard remainBits >= count else {
            throw HwpError.truncatedBits(expected: count, actual: remainBits)
        }
        defer {
            offset += count
        }
        let start = offset
        return (0 ..< count).map { bit(at: start + $0) }
    }

    mutating func readInt(_ count: Int) throws -> Int {
        guard count < Int.bitWidth else {
            throw HwpError.invalidDataLength(length: "\(count) bits cannot fit in Int")
        }
        guard count >= 0 else {
            throw HwpError.invalidDataLength(length: String(count))
        }
        guard remainBits >= count else {
            throw HwpError.truncatedBits(expected: count, actual: remainBits)
        }
        defer {
            offset += count
        }
        var result = 0
        for index in 0 ..< count where bit(at: offset + index) {
            result |= 1 << index
        }
        return result
    }
}

func getBitValue<T: FixedWidthInteger>(mask: T, start: Int, end: Int) -> T {
    guard start >= 0, end >= start, end < T.bitWidth else {
        return 0
    }

    let target = mask >> start
    let width = end - start + 1
    let bitMask: T = if width == T.bitWidth {
        ~T.zero
    } else {
        (0 ..< width).reduce(T.zero) { mask, bitOffset in
            mask | (T(1) << bitOffset)
        }
    }

    return target & bitMask
}
