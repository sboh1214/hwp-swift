@testable import CoreHwp
import Nimble
import XCTest

final class PageNumberPositionRealFixtureTests: XCTestCase {
    func testNooriFixtureDecodesPageNumberPositionPropertyBits() throws {
        let hwp = try openHwp(#file, "noori")
        guard let position = FixtureDerivedValues.pageNumberPositions(from: hwp).first else {
            fail("Expected noori fixture to contain a page-number-position control")
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
        }

        expect(position.property) == 0x0000_0500
        expect(position.propertyInfo.rawValue) == 0x0000_0500
        expect(position.propertyInfo.numberFormat) == 0
        expect(position.propertyInfo.displayPosition) == 5
    }
}
