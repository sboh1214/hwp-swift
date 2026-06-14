import CoreHwp
import Nimble
import XCTest

class HwpErrorTests: XCTestCase {
    func test() {
        expect { try openHwp(#file, "") }.to(throwError())
    }
}
