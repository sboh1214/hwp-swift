@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoIdMappingCountStabilityTests: XCTestCase {
    func testIdMappingsNegativeRequiredRecordCountThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[0] = -1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("invalid DocInfo record count -1"))
            expect(reason).to(contain("tag \(HwpDocInfoTag.binData.rawValue)"))
        })
    }

    func testIdMappingsNegativeOptionalRecordCountThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[15] = -1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("invalid DocInfo record count -1"))
            expect(reason).to(contain("tag \(HwpDocInfoTag.memoShape.rawValue)"))
        })
    }

    func testIdMappingsTruncatedRequiredCountHeaderThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(Array(repeating: Int32(0), count: 14))
        )

        expectTruncatedIdMappingCountHeader {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }
    }

    func testIdMappingsTruncatedMemoShapeCountHeaderThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(Array(repeating: Int32(0), count: 15))
        )

        expectTruncatedIdMappingCountHeader {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 2, 1))
        }
    }

    func testIdMappingsTruncatedTrackChangeCountHeaderThrowsTypedError() {
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(Array(repeating: Int32(0), count: 17))
        )

        expectTruncatedIdMappingCountHeader {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))
        }
    }

    func testIdMappingsRejectsTrailingPayloadBytesForVersionedCountTable() {
        let counts = Array(repeating: Int32(0), count: 16)
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.bytesAreNotEOF(model, remain) = error else {
                return fail("Expected bytesAreNotEOF, got \(error)")
            }
            expect(String(describing: model)) == "HwpIdMappings"
            expect(remain) == MemoryLayout<Int32>.size
        })
    }

    func testIdMappingsSequentialFaceNameBucketShortageThrowsTypedError() {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[1] = 1
        counts[2] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )
        record.children = [
            HwpRecord(
                tagId: HwpDocInfoTag.faceName.rawValue,
                level: 1,
                payload: idMappingFaceNamePayload("CoreHwp")
            ),
        ]

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record count 1 exceeds available child records 0"))
        })
    }

    func testIdMappingsUnknownChildDoesNotSatisfyRequiredRecordCount() {
        var counts = Array(repeating: Int32(0), count: 15)
        counts[1] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: 0x2EF, level: 1, payload: Data([0xAA])),
        ]

        expect {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("expected 1 tag \(HwpDocInfoTag.faceName.rawValue)"))
            expect(reason).to(contain("got 0"))
        })
    }

    func testIdMappingsUnknownChildrenDoNotSatisfyOptionalMemoShapeRecordCount() {
        var counts = Array(repeating: Int32(0), count: 16)
        counts[15] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: 0x2EF, level: 1, payload: Data([0xAA])),
        ]

        expectMissingOptionalIdMappingRecord(.memoShape) {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 2, 1))
        }
    }

    func testIdMappingsUnknownChildrenDoNotSatisfyOptionalTrackChangeContentRecordCount() {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[16] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.memoShape.rawValue, level: 1, payload: Data([0xAA])),
        ]

        expectMissingOptionalIdMappingRecord(.trackChangeContent) {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))
        }
    }

    func testIdMappingsUnknownChildrenDoNotSatisfyOptionalTrackChangeAuthorRecordCount() {
        var counts = Array(repeating: Int32(0), count: 18)
        counts[17] = 1
        let record = HwpRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingCountPayload(counts)
        )
        record.children = [
            HwpRecord(tagId: HwpDocInfoTag.trackChangeContent.rawValue, level: 1, payload: Data()),
        ]

        expectMissingOptionalIdMappingRecord(.trackChangeAuthor) {
            _ = try HwpIdMappings.load(record, HwpVersion(5, 0, 3, 2))
        }
    }
}

private func expectTruncatedIdMappingCountHeader(_ expression: @escaping () throws -> Void) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.truncatedData(expected, actual) = error else {
            return fail("Expected truncatedData, got \(error)")
        }
        expect(expected) == 4
        expect(actual) == 0
    })
}

private func expectMissingOptionalIdMappingRecord(
    _ expectedTag: HwpDocInfoTag,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.invalidRecordTree(reason) = error else {
            return fail("Expected invalidRecordTree, got \(error)")
        }
        expect(reason).to(contain("expected 1 tag \(expectedTag.rawValue)"))
        expect(reason).to(contain("got 0"))
    })
}

private func idMappingCountPayload(_ counts: [Int32]) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(idMappingCountLittleEndianData(count))
    }
}

private func idMappingCountLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func idMappingFaceNamePayload(_ name: String) -> Data {
    var payload = Data([0])
    payload.append(idMappingCountLittleEndianData(UInt16(name.utf16.count)))
    for character in name.utf16 {
        payload.append(idMappingCountLittleEndianData(character))
    }
    return payload
}
