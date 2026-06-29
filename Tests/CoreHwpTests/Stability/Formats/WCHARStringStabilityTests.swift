@testable import CoreHwp
import Nimble
import XCTest

final class WCHARStringStabilityTests: XCTestCase {
    func testWCHARStringDecodesSurrogatePairs() throws {
        let values = [WCHAR(0xD55C), WCHAR(0xD83D), WCHAR(0xDE00)]

        expect(try values.string) == "한😀"
        expect(values.stringIfValid) == "한😀"
        expect([WCHAR]("한😀")) == values
    }

    func testWCHARStringRejectsUnpairedHighSurrogate() {
        expect {
            _ = try [WCHAR(0xD800)].string
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
        expect([WCHAR(0xD800)].stringIfValid).to(beNil())
    }

    func testWCHARStringRejectsUnpairedLowSurrogate() {
        expect {
            _ = try [WCHAR(0xDE00)].string
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xDE00
        })
        expect([WCHAR(0xDE00)].stringIfValid).to(beNil())
    }
}
