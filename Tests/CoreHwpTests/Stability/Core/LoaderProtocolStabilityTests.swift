@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class LoaderProtocolStabilityTests: XCTestCase {
    func testFromDataLoaderRejectsUnreadBytes() {
        expect {
            _ = try PartialDataModel.load(Data([0x01, 0x02]))
        }.to(throwError { error in
            assertBytesAreNotEOF(error, modelName: "PartialDataModel", remain: 1)
        })
    }

    func testFromDataWithVersionLoaderRejectsUnreadBytes() {
        expect {
            _ = try PartialDataWithVersionModel.load(Data([0x01, 0x02]), HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            assertBytesAreNotEOF(error, modelName: "PartialDataWithVersionModel", remain: 1)
        })
    }

    func testFromDataWithVersionLoaderPassesVersionAndConsumesAllBytes() throws {
        let model = try PartialDataWithVersionModel.load(Data([0x01]), HwpVersion(5, 0, 1, 1))

        expect(model.value) == 0x01
        expect(model.majorVersion) == 5
    }

    func testFromRecordLoaderRejectsUnreadBytes() {
        let record = HwpRecord(tagId: 0x2FE, level: 0, payload: Data([0x01, 0x02]))

        expect {
            _ = try PartialRecordModel.load(record)
        }.to(throwError { error in
            assertBytesAreNotEOF(error, modelName: "PartialRecordModel", remain: 1)
        })
    }

    func testFromRecordLoaderPassesChildrenAndConsumesAllBytes() throws {
        let child = HwpRecord(tagId: 0x2FD, level: 1, payload: Data([0xAA]))
        let record = HwpRecord(tagId: 0x2FE, level: 0, payload: Data([0x01]))
        record.children = [child]

        let model = try PartialRecordModel.load(record)

        expect(model.value) == 0x01
        expect(model.childCount) == 1
    }

    func testFromRecordWithVersionLoaderRejectsUnreadBytes() {
        let record = HwpRecord(tagId: 0x2FE, level: 0, payload: Data([0x01, 0x02]))

        expect {
            _ = try PartialRecordWithVersionModel.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            assertBytesAreNotEOF(error, modelName: "PartialRecordWithVersionModel", remain: 1)
        })
    }

    func testFromRecordWithVersionLoaderPassesChildrenVersionAndConsumesAllBytes() throws {
        let child = HwpRecord(tagId: 0x2FD, level: 1, payload: Data([0xAA]))
        let record = HwpRecord(tagId: 0x2FE, level: 0, payload: Data([0x01]))
        record.children = [child]

        let model = try PartialRecordWithVersionModel.load(record, HwpVersion(5, 0, 1, 1))

        expect(model.value) == 0x01
        expect(model.childCount) == 1
        expect(model.majorVersion) == 5
    }

    func testFromUIntLoaderRejectsUnreadBits() {
        expect {
            _ = try PartialUIntModel.load(UInt8(0b0000_0011))
        }.to(throwError { error in
            guard case let HwpError.bitsAreNotEOF(model, remain) = error else {
                return fail("Expected bitsAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "PartialUIntModel"
            expect(remain) == 7
        })
    }

    func testFromUIntLoaderReturnsModelWhenAllBitsAreConsumed() throws {
        let model = try FullUIntModel.load(UInt8(0b1010_0101))

        expect(model.bits) == [
            true, false, true, false,
            false, true, false, true,
        ]
    }
}

private struct PartialDataModel: HwpFromData {
    let value: UInt8

    init(_ reader: inout DataReader) throws {
        value = try reader.read(UInt8.self)
    }
}

private struct PartialDataWithVersionModel: HwpFromDataWithVersion {
    let value: UInt8
    let majorVersion: UInt8

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        value = try reader.read(UInt8.self)
        majorVersion = version.major
    }
}

private struct PartialRecordModel: HwpFromRecord {
    let value: UInt8
    let childCount: Int

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        value = try reader.read(UInt8.self)
        childCount = children.count
    }
}

private struct PartialRecordWithVersionModel: HwpFromRecordWithVersion {
    let value: UInt8
    let childCount: Int
    let majorVersion: UInt8

    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws {
        value = try reader.read(UInt8.self)
        childCount = children.count
        majorVersion = version.major
    }
}

private struct PartialUIntModel: HwpFromUInt {
    let value: Bool

    init(_ reader: inout BitsReader<UInt8>) throws {
        value = try reader.readBit()
    }
}

private struct FullUIntModel: HwpFromUInt {
    let bits: [Bool]

    init(_ reader: inout BitsReader<UInt8>) throws {
        bits = try (0 ..< UInt8.bitWidth).map { _ in
            try reader.readBit()
        }
    }
}

private func assertBytesAreNotEOF(_ error: Error, modelName: String, remain: Int) {
    guard case let HwpError.bytesAreNotEOF(model, actualRemain) = error else {
        return fail("Expected bytesAreNotEOF, got \(error)")
    }
    expect(String(describing: model)) == modelName
    expect(actualRemain) == remain
}
