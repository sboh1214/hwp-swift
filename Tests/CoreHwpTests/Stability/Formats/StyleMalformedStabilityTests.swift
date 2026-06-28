@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class StyleMalformedStabilityTests: XCTestCase {
    func testStyleRejectsTruncatedLocalNameWithTypedError() {
        let payload = littleEndianData(UInt16(2)) + littleEndianData(WCHAR(0x004C))

        expect {
            _ = try HwpStyle.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 4
            expect(actual) == 2
        })
    }

    func testStyleRejectsTruncatedEnglishNameWithTypedError() {
        let payload = wcharStringData("Local")
            + littleEndianData(UInt16(3))
            + littleEndianData(WCHAR(0x0045))

        expect {
            _ = try HwpStyle.load(payload)
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 6
            expect(actual) == 2
        })
    }

    func testStyleRejectsInvalidEnglishNameWithTypedError() {
        let payload = stylePayloadWithInvalidEnglishName()

        expect {
            _ = try HwpStyle.load(payload)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }
}

private func stylePayloadWithInvalidEnglishName() -> Data {
    var data = wcharStringData("Local")
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(WCHAR(0xD800)))
    data.append(littleEndianData(BYTE(0)))
    data.append(littleEndianData(BYTE(1)))
    data.append(littleEndianData(Int16(1042)))
    data.append(littleEndianData(UInt16(2)))
    data.append(littleEndianData(UInt16(3)))
    data.append(contentsOf: [0, 0])
    return data
}

private func wcharStringData(_ string: String) -> Data {
    var data = littleEndianData(UInt16(string.utf16.count))
    for codeUnit in string.utf16 {
        data.append(littleEndianData(codeUnit))
    }
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
