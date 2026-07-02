import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpUnitsTests: XCTestCase {
    func testPointsFromHwpUnit() {
        // A4 width: 59528 HWPUNIT → 595.28 pt
        let a4Width = HwpUnits.points(fromHwpUnit: 59528)
        expect(a4Width).to(beCloseTo(595.28, within: 0.01))

        // Letter width: 61200 HWPUNIT → 612.0 pt
        let letterWidth = HwpUnits.points(fromHwpUnit: 61200)
        expect(letterWidth) == 612.0
    }

    func testPointsFromHwpUnitU() {
        // Unsigned variant: 59528 HWPUNIT → 595.28 pt
        let a4Width = HwpUnits.points(fromHwpUnitU: 59528)
        expect(a4Width).to(beCloseTo(595.28, within: 0.01))
    }

    func testPointsFromHwpUnit16() {
        // Positive value: 500 HWPUNIT → 5.0 pt
        let positive = HwpUnits.points(fromHwpUnit16: 500)
        expect(positive) == 5.0

        // Negative value: -500 HWPUNIT → -5.0 pt
        let negative = HwpUnits.points(fromHwpUnit16: -500)
        expect(negative) == -5.0
    }

    func testPixelsFromHwpUnit() {
        // Default DPI (96): 7200 HWPUNIT = 1 inch = 96 px
        let defaultDpi = HwpUnits.pixels(fromHwpUnit: 7200)
        expect(defaultDpi) == 96.0

        // Custom DPI (200): 7200 HWPUNIT = 1 inch = 200 px
        let customDpi = HwpUnits.pixels(fromHwpUnit: 7200, dpi: 200)
        expect(customDpi) == 200.0

        // Half inch at 96 DPI: 3600 HWPUNIT = 0.5 inch = 48 px
        let halfInch = HwpUnits.pixels(fromHwpUnit: 3600, dpi: 96)
        expect(halfInch) == 48.0
    }

    func testHwpUnitFromPoints() {
        // 612.0 pt → 61200 HWPUNIT
        let hwpUnit = HwpUnits.hwpUnit(fromPoints: 612.0)
        expect(hwpUnit) == 61200

        // 595.28 pt → 59528 HWPUNIT (with rounding)
        let a4Unit = HwpUnits.hwpUnit(fromPoints: 595.28)
        expect(a4Unit) == 59528
    }

    func testRoundTrip() {
        // Round-trip: hwpUnit → points → hwpUnit should be within ±1
        let original: Int32 = 12345
        let points = HwpUnits.points(fromHwpUnit: original)
        let roundTrip = HwpUnits.hwpUnit(fromPoints: points)
        expect(abs(roundTrip - original)) <= 1
    }

    func testSizeFromHwpUnit() {
        // A4 size: 59528 x 84188 HWPUNIT → 595.28 x 841.88 pt
        let a4Size = HwpUnits.size(fromHwpUnitWidth: 59528, height: 84188)
        expect(a4Size.width).to(beCloseTo(595.28, within: 0.01))
        expect(a4Size.height).to(beCloseTo(841.88, within: 0.01))

        // Letter size: 61200 x 79200 HWPUNIT → 612.0 x 792.0 pt
        let letterSize = HwpUnits.size(fromHwpUnitWidth: 61200, height: 79200)
        expect(letterSize.width) == 612.0
        expect(letterSize.height) == 792.0
    }
}
