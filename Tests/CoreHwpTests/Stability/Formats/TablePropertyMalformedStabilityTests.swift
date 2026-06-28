@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TablePropertyMalformedStabilityTests: XCTestCase {
    func testTablePropertyRejectsOversizedRowSizeArrayBeforeIterating() {
        var payload = Data()
        payload.append(tablePropertyMalformedLittleEndianData(UInt32(0)))
        payload.append(tablePropertyMalformedLittleEndianData(UInt16.max))
        payload.append(tablePropertyMalformedLittleEndianData(UInt16(1)))
        payload.append(Data(repeating: 0, count: MemoryLayout<UInt16>.size * 5))

        expect {
            _ = try HwpTableProperty.load(payload, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == Int(UInt16.max) * MemoryLayout<UInt16>.size
            expect(actual) == 0
        })
    }
}

private func tablePropertyMalformedLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
