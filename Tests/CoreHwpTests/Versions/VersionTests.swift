import CoreHwp
import Nimble
import XCTest

final class VersionTests: XCTestCase {
    func test2007() throws {
        let hwp = try openHwp(#file, "2007")
        expect(hwp.fileHeader.version) == HwpVersion(5, 0, 2, 2)
    }

    func test2014VP() throws {
        let hwp = try openHwp(#file, "2014VP")
        expect(hwp.fileHeader.version) == HwpVersion(5, 0, 5, 0)
    }
}
