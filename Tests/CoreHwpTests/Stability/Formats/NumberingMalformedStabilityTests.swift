@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class NumberingMalformedStabilityTests: XCTestCase {
    func testNumberingRejectsTruncatedFormatStringWithTypedError() {
        var payload = numberingMalformedFormatHeader(formatLength: 3)
        payload.append(numberingMalformedLittleEndianData(WCHAR(0x005E)))

        expect {
            _ = try HwpNumbering.load(payload, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 3 * MemoryLayout<WCHAR>.size
            expect(actual) == MemoryLayout<WCHAR>.size
        })
    }

    func testNumberingRejectsOversizedFormatStringLengthBeforeIterating() {
        let payload = numberingMalformedFormatHeader(formatLength: UInt16.max)

        expect {
            _ = try HwpNumbering.load(payload, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == Int(UInt16.max) * MemoryLayout<WCHAR>.size
            expect(actual) == 0
        })
    }

    func testNumberingRejectsInvalidFormatUnicodeWithTypedError() {
        var payload = numberingMalformedFormatHeader(formatLength: 1)
        payload.append(numberingMalformedLittleEndianData(WCHAR(0xD800)))

        expect {
            _ = try HwpNumbering.load(payload, HwpVersion(5, 0, 1, 1))
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }

    func testNumberingRejectsMissingCurrentVersionStartingIndexesAsSingleTypedError() {
        let payload = numberingMalformedCompleteLegacyFormats()

        expect {
            _ = try HwpNumbering.load(payload, HwpVersion(5, 1, 0, 0))
        }.to(throwError { error in
            guard case let HwpError.truncatedData(expected, actual) = error else {
                return fail("Expected truncatedData, got \(error)")
            }
            expect(expected) == 7 * MemoryLayout<UInt32>.size
            expect(actual) == 0
        })
    }
}

private func numberingMalformedCompleteLegacyFormats() -> Data {
    var data = Data()
    for index in 1 ... 7 {
        data.append(numberingMalformedFormatPayload(index: index))
    }
    data.append(numberingMalformedLittleEndianData(UInt16(0)))
    return data
}

private func numberingMalformedFormatPayload(index: Int) -> Data {
    var data = numberingMalformedFormatHeader(formatLength: UInt16("^\(index)".utf16.count))
    for value in "^\(index)".utf16 {
        data.append(numberingMalformedLittleEndianData(value))
    }
    return data
}

private func numberingMalformedFormatHeader(formatLength: UInt16) -> Data {
    var data = Data(repeating: 0, count: 12)
    data.append(numberingMalformedLittleEndianData(formatLength))
    return data
}

private func numberingMalformedLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
