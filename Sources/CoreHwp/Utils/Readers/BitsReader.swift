import Foundation

struct BitsReader<T: BinaryInteger> {
    private var bits: [Bool]
    private var offset: Int = 0

    init(from int: T) {
        bits = int.bits
    }

    var isEOF: Bool {
        offset == bits.count
    }

    var remainBits: Int {
        bits.count - offset
    }

    mutating func readBit() throws -> Bool {
        guard remainBits >= 1 else {
            throw HwpError.truncatedBits(expected: 1, actual: remainBits)
        }
        defer {
            offset += 1
        }
        return bits[offset]
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
        return Array(bits[offset ..< (offset + count)])
    }

    mutating func readInt(_ count: Int) throws -> Int {
        guard count < Int.bitWidth else {
            throw HwpError.invalidDataLength(length: "\(count) bits cannot fit in Int")
        }
        let array = try readBits(count)
        return array.enumerated().reduce(0) { value, current in
            let (index, bit) = current
            guard bit else {
                return value
            }
            return value | (1 << index)
        }
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
