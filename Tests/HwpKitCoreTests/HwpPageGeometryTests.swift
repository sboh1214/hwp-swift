@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpPageGeometryTests: XCTestCase {
    func testA4PageSize() {
        var pageDef = HwpPageDef()
        pageDef.width = 59528
        pageDef.height = 84189
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.pageSize.width).to(beCloseTo(595.28, within: 0.5))
        expect(geo.pageSize.height).to(beCloseTo(841.89, within: 0.5))
    }

    func testLetterPageSize() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.pageSize.width) == 612.0
        expect(geo.pageSize.height) == 792.0
    }

    func testCustomMargins() {
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: nil)

        expect(geo.contentFrame.origin.x) == 72.0
        expect(geo.contentFrame.origin.y) == 72.0
        expect(geo.contentFrame.size.width) == geo.pageSize.width - 144.0
        expect(geo.contentFrame.size.height) == geo.pageSize.height - 144.0
    }

    func testTwoColumn() {
        // Column count lives in the Column control (CtrlHeader/Column/), not in HwpSectionDef.
        // v1 always returns [contentFrame]; this test verifies the single-column fallback.
        var pageDef = HwpPageDef()
        pageDef.width = 61200
        pageDef.height = 79200
        pageDef.marginTop = 7200
        pageDef.marginLeft = 7200
        pageDef.marginBottom = 7200
        pageDef.marginRight = 7200
        pageDef.marginHeader = 0
        pageDef.marginFootnote = 0

        var sectionDef = HwpSectionDef()
        sectionDef.columnSpacing = 1440

        let geo = HwpPageGeometry.compute(pageDef: pageDef, sectionDef: sectionDef)

        expect(geo.columnFrames.count) == 1
        expect(geo.columnFrames.first) == geo.contentFrame
    }
}
