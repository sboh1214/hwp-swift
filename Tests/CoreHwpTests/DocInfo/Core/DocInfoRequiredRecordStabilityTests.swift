@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoRequiredRecordStabilityTests: XCTestCase {
    func testMissingDocumentPropertiesThrowsTypedError() {
        let data = recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload()
        )

        expectRecordDoesNotExist(tag: HwpDocInfoTag.documentProperties.rawValue) {
            _ = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))
        }
    }

    func testMissingIdMappingsThrowsTypedError() {
        let data = recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: documentPropertiesPayload()
        )

        expectRecordDoesNotExist(tag: HwpDocInfoTag.idMappings.rawValue) {
            _ = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))
        }
    }

    func testDuplicateRequiredSingletonRecordIsPreservedAsUnknown() throws {
        let duplicatePayload = Data([0xDE, 0xAD])
        let duplicateChildPayload = Data([0xBE, 0xEF])
        var data = recordData(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: documentPropertiesPayload()
        )
        data.append(recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: idMappingsPayload()
        ))
        data.append(recordData(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: duplicatePayload
        ))
        data.append(recordData(tagId: 0x2EF, level: 1, payload: duplicateChildPayload))

        let docInfo = try HwpDocInfo.load(data, HwpVersion(5, 0, 3, 2))

        expect(docInfo.unknownRecords) == [
            expectedTestUnknownRecord(
                tagId: HwpDocInfoTag.idMappings.rawValue,
                level: 0,
                payload: duplicatePayload,
                children: [
                    expectedTestRecord(tagId: 0x2EF, level: 1, payload: duplicateChildPayload),
                ]
            ),
        ]
    }
}

private func expectRecordDoesNotExist(
    tag expectedTag: UInt32,
    _ expression: @escaping () throws -> Void
) {
    expect {
        try expression()
    }.to(throwError { error in
        guard case let HwpError.recordDoesNotExist(tag) = error else {
            return fail("Expected recordDoesNotExist, got \(error)")
        }
        expect(tag) == expectedTag
    })
}

private func documentPropertiesPayload() -> Data {
    concatenatedData(littleEndianData(UInt16(1)), Data(repeating: 0, count: 24))
}

private func idMappingsPayload(_ counts: [Int32] = Array(repeating: Int32(0), count: 18)) -> Data {
    counts.reduce(into: Data()) { data, count in
        data.append(littleEndianData(count))
    }
}

private func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = littleEndianData(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
