@testable import CoreHwp
import Nimble
import XCTest

final class BitsReaderTests: XCTestCase {
    func testReadBitPastEndThrowsTypedError() {
        expect {
            var reader = BitsReader(from: UInt8(0))
            _ = try reader.readBits(8)
            _ = try reader.readBit()
        }.to(throwError { error in
            guard case let HwpError.truncatedBits(expected, actual) = error else {
                return fail("Expected truncatedBits, got \(error)")
            }
            expect(expected) == 1
            expect(actual) == 0
        })
    }

    func testReadBitsPastEndThrowsTypedError() {
        expect {
            var reader = BitsReader(from: UInt8(0))
            _ = try reader.readBits(9)
        }.to(throwError { error in
            guard case let HwpError.truncatedBits(expected, actual) = error else {
                return fail("Expected truncatedBits, got \(error)")
            }
            expect(expected) == 9
            expect(actual) == 8
        })
    }

    func testReadBitsPastEndDoesNotAdvanceReader() throws {
        var reader = BitsReader(from: UInt8(0b0000_1010))

        expect {
            _ = try reader.readBits(9)
        }.to(throwError { error in
            guard case let HwpError.truncatedBits(expected, actual) = error else {
                return fail("Expected truncatedBits, got \(error)")
            }
            expect(expected) == 9
            expect(actual) == 8
        })

        expect(try reader.readInt(4)) == 0b1010
    }

    func testNegativeBitReadLengthThrowsTypedError() {
        expect {
            var reader = BitsReader(from: UInt8(0))
            _ = try reader.readBits(-1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })
    }

    func testNegativeBitReadLengthDoesNotAdvanceReader() throws {
        var reader = BitsReader(from: UInt8(0b0000_1010))

        expect {
            _ = try reader.readBits(-1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })

        expect(try reader.readInt(4)) == 0b1010
    }

    func testNegativeBitIntegerReadLengthThrowsTypedError() {
        expect {
            var reader = BitsReader(from: UInt8(0))
            _ = try reader.readInt(-1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })
    }

    func testTruncatedBitIntegerReadDoesNotAdvanceReader() throws {
        var reader = BitsReader(from: UInt8(0b0000_1010))

        expect {
            _ = try reader.readInt(9)
        }.to(throwError { error in
            guard case let HwpError.truncatedBits(expected, actual) = error else {
                return fail("Expected truncatedBits, got \(error)")
            }
            expect(expected) == 9
            expect(actual) == 8
        })

        expect(try reader.readInt(4)) == 0b1010
    }

    func testOversizedBitIntegerReadLengthThrowsTypedErrorBeforeOverflow() {
        var reader = BitsReader(from: UInt8(0b0000_1010))

        expect {
            _ = try reader.readInt(Int.bitWidth)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length).to(contain("\(Int.bitWidth) bits"))
        })

        expect(try? reader.readInt(4)) == 0b1010
    }

    func testBitIntegerReadUsesLittleEndianBitOrderWithoutFloatingPointMath() throws {
        var reader = BitsReader(from: UInt8(0b0000_1010))

        expect(try reader.readInt(4)) == 0b1010
    }
}
