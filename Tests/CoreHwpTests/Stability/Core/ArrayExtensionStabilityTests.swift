@testable import CoreHwp
import Nimble
import XCTest

final class ArrayExtensionStabilityTests: XCTestCase {
    func testPopRejectsNegativeCountWithTypedError() {
        expect {
            var values = [1, 2, 3]
            _ = try values.pop(Int(-1))
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("invalid record count -1"))
        })
    }

    func testPopRejectsUnrepresentableCountWithTypedError() {
        let count = UInt64(Int.max) + 1

        expect {
            var values = [1, 2, 3]
            _ = try values.pop(count)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("invalid record count \(count)"))
        })
    }

    func testPopRejectsCountGreaterThanAvailableValuesWithTypedError() {
        expect {
            var values = [1, 2, 3]
            _ = try values.pop(4)
        }.to(throwError { error in
            guard case let HwpError.invalidRecordTree(reason) = error else {
                return fail("Expected invalidRecordTree, got \(error)")
            }
            expect(reason).to(contain("record count 4 exceeds available child records 3"))
        })
    }

    func testPopZeroDoesNotMutateValues() throws {
        var values = [1, 2, 3]

        expect(try values.pop(0)).to(beEmpty())
        expect(values) == [1, 2, 3]
    }
}
