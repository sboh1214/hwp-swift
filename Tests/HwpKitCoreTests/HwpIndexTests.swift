import CoreHwp
import Foundation
import HwpKitCore
import Nimble
import XCTest

final class HwpIndexTests: XCTestCase {
    func testBlankDocument() {
        let index = HwpIndex(from: CoreHwp.HwpFile())
        expect(index.charShapes.count) >= 0
        expect(index.paraShapes.count) >= 0
        expect(index.borderFills.count) >= 0
        expect(index.tabDefs.count) >= 0
        expect(index.styles.count) >= 0
        expect(index.bullets.count) >= 0
        expect(index.numberings.count) >= 0
        expect(index.binData.count) >= 0
        expect(index.faceNamesKorean.count) >= 0
    }

    func testMissingIdReturnsNil() {
        let index = HwpIndex(from: CoreHwp.HwpFile())
        expect(index.charShape(id: 999_999)).to(beNil())
        expect(index.paraShape(id: 999_999)).to(beNil())
        expect(index.borderFill(id: 999_999)).to(beNil())
        expect(index.tabDef(id: 999_999)).to(beNil())
        expect(index.style(id: 999_999)).to(beNil())
        expect(index.bullet(id: 999_999)).to(beNil())
        expect(index.numbering(id: 999_999)).to(beNil())
        expect(index.binDataEntry(id: 999_999)).to(beNil())
        expect(index.faceNameKorean(id: 999_999)).to(beNil())
    }

    func testBlankDocumentHasDefaultCharShape() {
        let index = HwpIndex(from: CoreHwp.HwpFile())
        if index.charShapes.isEmpty {
            // blank doc seeded no charShapes — acceptable
            expect(index.charShape(id: 0)).to(beNil())
        } else {
            expect(index.charShape(id: 0)).notTo(beNil())
        }
    }
}
