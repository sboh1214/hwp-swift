@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class CtrlDataParameterSetStabilityTests: XCTestCase {
    func testStringItemRejectsPayloadBeforeStringHeader() {
        let payload = Data(repeating: 0, count: 11)

        let item = HwpCtrlDataParameterStringItem(payload, offset: 4)

        expect(item).to(beNil())
    }
}
