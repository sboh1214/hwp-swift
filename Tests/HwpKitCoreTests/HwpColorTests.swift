import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpColorTests: XCTestCase {
    @available(iOS 13.0, *)
    func testCGColorConversionRed() {
        let color = CoreHwp.HwpColor(255, 0, 0)
        let cgColor = color.cgColor
        let components = cgColor.components ?? []

        expect(components.count).to(equal(4))
        expect(components[0]).to(beCloseTo(1.0, within: 0.01))
        expect(components[1]).to(beCloseTo(0.0, within: 0.01))
        expect(components[2]).to(beCloseTo(0.0, within: 0.01))
        expect(components[3]).to(beCloseTo(1.0, within: 0.01))
    }

    @available(iOS 13.0, *)
    func testCGColorConversionBlack() {
        let color = CoreHwp.HwpColor(0, 0, 0)
        let cgColor = color.cgColor
        let components = cgColor.components ?? []

        expect(components.count).to(equal(4))
        expect(components[0]).to(beCloseTo(0.0, within: 0.01))
        expect(components[1]).to(beCloseTo(0.0, within: 0.01))
        expect(components[2]).to(beCloseTo(0.0, within: 0.01))
        expect(components[3]).to(beCloseTo(1.0, within: 0.01))
    }

    @available(iOS 13.0, *)
    func testCGColorConversionWhite() {
        let color = CoreHwp.HwpColor(255, 255, 255)
        let cgColor = color.cgColor
        let components = cgColor.components ?? []

        expect(components.count).to(equal(4))
        expect(components[0]).to(beCloseTo(1.0, within: 0.01))
        expect(components[1]).to(beCloseTo(1.0, within: 0.01))
        expect(components[2]).to(beCloseTo(1.0, within: 0.01))
        expect(components[3]).to(beCloseTo(1.0, within: 0.01))
    }

    func testTransparentConstant() {
        let transparent = CGColor.hwpTransparent
        let components = transparent.components ?? []

        expect(components.count).to(equal(4))
        expect(components[0]).to(beCloseTo(0.0, within: 0.01))
        expect(components[1]).to(beCloseTo(0.0, within: 0.01))
        expect(components[2]).to(beCloseTo(0.0, within: 0.01))
        expect(components[3]).to(beCloseTo(0.0, within: 0.01))
    }
}
