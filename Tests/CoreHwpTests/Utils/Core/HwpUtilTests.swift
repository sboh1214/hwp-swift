@testable import CoreHwp
import Nimble
import SWCompression
import XCTest

final class HwpUtilTests: XCTestCase {
    func testBitsFromInt8() {
        let byte = UInt8(0x4A)
        let bits = [false, true, false, false, true, false, true, false].reversed() as [Bool]
        expect(bits) == byte.bits
    }

    func testUInt32ToBits() {
        let uint32 = UInt32(1)
        let bits = [true] + Array(repeating: false, count: 31)
        expect(uint32.bits) == bits
    }

    func testGetBitValue() {
        expect(2) == getBitValue(mask: 1024, start: 9, end: 10)
        expect(4) == getBitValue(mask: 1024, start: 8, end: 10)
    }

    func testGetBitValueSupportsFullWidthRangeWithoutTrap() {
        expect(getBitValue(mask: UInt8.max, start: 0, end: UInt8.bitWidth - 1)) == UInt8.max
        expect(getBitValue(mask: UInt16.max, start: 0, end: UInt16.bitWidth - 1)) ==
            UInt16.max
    }

    func testGetBitValueSupportsSignedNearFullWidthRangeWithoutTrap() {
        expect(getBitValue(mask: Int.max, start: 0, end: Int.bitWidth - 2)) == Int.max
        expect(getBitValue(mask: Int.min, start: Int.bitWidth - 1, end: Int.bitWidth - 1)) ==
            1
    }

    func testGetBitValueRejectsInvalidRangesWithoutTrap() {
        expect(getBitValue(mask: 1024, start: 11, end: 10)) == 0
        expect(getBitValue(mask: 1024, start: -1, end: 1)) == 0
        expect(getBitValue(mask: 1024, start: 0, end: Int.bitWidth)) == 0
    }

    func testCompressUncompress() throws {
        guard let testData = "Hello World".data(using: .utf16LittleEndian) else {
            return fail("Expected UTF-16LE test data")
        }

        let compressed = Deflate.compress(data: testData)
        let decompressed = try Deflate.decompress(data: compressed)

        expect(testData) == decompressed
    }
}
