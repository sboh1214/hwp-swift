@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ExcludeEquatableTests: XCTestCase {
    func testWrappedValueDoesNotAffectEqualityOrHash() {
        let first = ExcludeEquatable(wrappedValue: Data([0x01, 0x02, 0x03]))
        let second = ExcludeEquatable(wrappedValue: Data([0xAA, 0xBB, 0xCC]))

        expect(first) == second
        expect(first.hashValue) == second.hashValue
        expect(Set([first, second]).count) == 1
    }
}
