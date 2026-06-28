@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class RecordParserStabilityTests: XCTestCase {
    func testRecordParserHandlesNonZeroStartIndexPayload() throws {
        let payload = Data([0xAA, 0xBB])
        let data = (Data([0xFF, 0xFE]) + recordData(
            tagId: 16,
            level: 0,
            payload: payload
        )).dropFirst(2)

        let root = try parseTreeRecord(data: data)

        expect(root.children.count) == 1
        expect(root.children.first?.tagId) == 16
        expect(root.children.first?.payload) == payload
    }

    func testExtendedRecordPayloadIsParsed() throws {
        let payload = Data([0xAA, 0xBB, 0xCC, 0xDD])
        var data = recordHeaderData(tagId: 16, level: 0, size: 0xFFF)
        data.append(littleEndianData(UInt32(payload.count)))
        data.append(payload)

        let root = try parseTreeRecord(data: data)

        expect(root.children.count) == 1
        expect(root.children.first?.tagId) == 16
        expect(root.children.first?.level) == 0
        expect(root.children.first?.payload) == payload
    }

    func testRecordTreeReparentsChildrenAfterReturningToShallowLevel() throws {
        let data = recordData(tagId: 0x10, level: 0, payload: Data([0x10]))
            + recordData(tagId: 0x11, level: 1, payload: Data([0x11]))
            + recordData(tagId: 0x20, level: 0, payload: Data([0x20]))
            + recordData(tagId: 0x21, level: 1, payload: Data([0x21]))

        let root = try parseTreeRecord(data: data)

        expect(root.children.map(\.tagId)) == [0x10, 0x20]
        expect(root.children.first?.children.map(\.tagId)) == [0x11]
        expect(root.children.last?.children.map(\.tagId)) == [0x21]
        expect(root.children.last?.children.first?.payload) == Data([0x21])
    }

    func testTruncatedRecordHeaderThrowsTypedError() {
        expect {
            _ = try parseTreeRecord(data: Data([0x00, 0x01, 0x02]))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 3
        })
    }

    func testTruncatedInlineRecordPayloadThrowsTypedError() {
        var data = recordHeaderData(tagId: 16, level: 0, size: 3)
        data.append(0xAA)

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 3
            expect(actual) == 1
        })
    }

    func testTruncatedExtendedRecordSizeThrowsTypedError() {
        var data = recordHeaderData(tagId: 16, level: 0, size: 0xFFF)
        data.append(contentsOf: [0x01, 0x02])

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 2
        })
    }

    func testTruncatedExtendedRecordPayloadThrowsTypedError() {
        var data = recordHeaderData(tagId: 16, level: 0, size: 0xFFF)
        data.append(littleEndianData(UInt32(5)))
        data.append(contentsOf: [0xAA, 0xBB])

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 5
            expect(actual) == 2
        })
    }

    func testOversizedExtendedRecordPayloadThrowsTypedErrorWithoutAllocation() {
        var data = recordHeaderData(tagId: 16, level: 0, size: 0xFFF)
        data.append(littleEndianData(UInt32.max))
        data.append(0xAA)

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == Int(UInt32.max)
            expect(actual) == 1
        })
    }

    func testInvalidRecordLevelThrowsTypedError() {
        expect {
            _ = try parseTreeRecord(data: recordData(tagId: 16, level: 1, payload: Data()))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("has no parent"))
        })
    }

    func testRecordLevelJumpThrowsTypedError() {
        let data = recordData(tagId: 16, level: 0, payload: Data())
            + recordData(tagId: 17, level: 2, payload: Data())

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 2 has no parent"))
        })
    }

    func testInvalidRecordLevelIsRejectedBeforePayloadRead() {
        var data = recordHeaderData(tagId: 16, level: 2, size: 0xFFF)
        data.append(littleEndianData(UInt32.max))

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 2 has no parent"))
        })
    }

    func testInvalidRecordLevelIsRejectedBeforeExtendedSizeRead() {
        let data = recordHeaderData(tagId: 16, level: 2, size: 0xFFF)

        expect {
            _ = try parseTreeRecord(data: data)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record level 2 has no parent"))
        })
    }
}

private func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = recordHeaderData(tagId: tagId, level: level, size: UInt32(payload.count))
    data.append(payload)
    return data
}

private func recordHeaderData(tagId: UInt32, level: UInt32, size: UInt32) -> Data {
    littleEndianData(tagId | (level << 10) | (size << 20))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
