@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class UnknownRecordCodableTests: XCTestCase {
    func testUnknownRecordPublicInitializerPreservesNestedPayloadsThroughCodable() throws {
        let grandchild = HwpUnknownRecord(
            tagId: 0x2FA,
            level: 2,
            payload: Data([0xFA, 0x01])
        )
        let child = HwpUnknownRecord(
            tagId: 0x2F9,
            level: 1,
            payload: Data([0xF9]),
            children: [grandchild]
        )
        let record = HwpUnknownRecord(
            tagId: 0x2F8,
            level: 0,
            payload: Data([0xF8, 0x00, 0x01]),
            children: [child]
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(HwpUnknownRecord.self, from: encoded)

        expect(decoded) == record
        expect(decoded.children.first?.children.first?.payload) == grandchild.payload
    }
}
