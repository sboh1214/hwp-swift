@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DataReaderStabilityTests: XCTestCase {
    func testDataLittleEndianReadersHandleNonZeroStartIndexPayload() throws {
        let data = Data([0xFF, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE]).dropFirst(1)

        expect(try data.readLittleEndianUInt16(at: 0)) == UInt16(0x1234)
        expect(try data.readLittleEndianUInt32(at: 2)) == UInt32(0xDEAD_BEEF)
        expect(try data.readUInt8(at: 1)) == UInt8(0x12)
    }

    func testDataLittleEndianReadersRejectNegativeOffsetWithTypedError() {
        expect {
            _ = try Data([0xAA]).readLittleEndianUInt16(at: -1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "offset -1"
        })
    }

    func testDataLittleEndianReadersRejectOutOfRangeOffsetWithTypedError() {
        expect {
            _ = try Data([0xAA, 0xBB]).readLittleEndianUInt32(at: 1)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 1
        })
    }

    func testDataLittleEndianReadersRejectBoundaryAndOverflowOffsetsWithTypedErrors() {
        expect {
            _ = try Data([0xAA, 0xBB]).readLittleEndianUInt16(at: 2)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 2
            expect(actual) == 0
        })

        expect {
            _ = try Data([0xAA, 0xBB]).readLittleEndianUInt32(at: Int.max)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "offset \(Int.max) + 4 bytes"
        })
    }

    func testReadBytesAndValuesHandleNonZeroStartIndexPayload() throws {
        var reader = DataReader(Data([0xFF, 0x34, 0x12, 0xAB]).dropFirst(1))

        expect(try reader.read(UInt16.self)) == UInt16(0x1234)
        expect(try reader.readBytes(1)) == Data([0xAB])
        expect(reader.isEOF) == true
    }

    func testReadBytesRejectsNegativeLengthWithTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xAA]))

        expect {
            _ = try reader.readBytes(-1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })

        expect(try reader.read(UInt8.self)) == 0xAA
    }

    func testReadBytesRejectsTruncatedReadWithTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xAA, 0xBB]))

        expect {
            _ = try reader.readBytes(3)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 3
            expect(actual) == 2
        })

        expect(try reader.readBytes(2)) == Data([0xAA, 0xBB])
    }

    func testArrayReadRejectsNegativeCountWithTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xAA]))

        expect {
            _ = try reader.read(UInt8.self, -1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "-1"
        })

        expect(try reader.read(UInt8.self)) == 0xAA
    }

    func testArrayReadRejectsTruncatedPayloadWithTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xAA, 0xBB, 0xCC]))

        expect {
            _ = try reader.read(UInt16.self, 2)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 3
        })

        expect(try reader.read(UInt8.self, 3)) == [0xAA, 0xBB, 0xCC]
    }

    func testArrayReadByteCountOverflowThrowsTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xEF, 0xBE, 0xAD, 0xDE]))

        expect {
            _ = try reader.read(UInt32.self, Int.max)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length) == "\(Int.max) values of 4 bytes"
        })

        expect(try reader.read(UInt32.self)) == UInt32(0xDEAD_BEEF)
    }

    func testUnsupportedReadTypeThrowsTypedErrorBeforeReading() throws {
        var reader = DataReader(Data([0xAA]))

        expect {
            _ = try reader.read(UInt64.self)
        }.to(throwError { error in
            guard case let HwpError.unsupportedDataReadType(type) = error else {
                return fail("Expected unsupportedDataReadType, got \(error)")
            }
            expect(type) == "UInt64"
        })

        expect(try reader.read(UInt8.self)) == 0xAA
    }

    func testConsumedDataRejectsOutOfRangeStartOffsetWithTypedError() {
        expect {
            var reader = DataReader(Data([0x01]))
            _ = try reader.read(UInt8.self)
            _ = try reader.consumedData(from: 2)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length).to(contain("offset 2"))
        })
    }

    func testConsumedDataRejectsNegativeStartOffsetWithTypedError() {
        expect {
            var reader = DataReader(Data([0x01]))
            _ = try reader.read(UInt8.self)
            _ = try reader.consumedData(from: -1)
        }.to(throwError { error in
            guard case let HwpError.invalidDataLength(length) = error else {
                return fail("Expected invalidDataLength, got \(error)")
            }
            expect(length).to(contain("offset -1"))
        })
    }
}
