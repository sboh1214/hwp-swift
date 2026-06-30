import CoreHwp
import Nimble
import XCTest

final class ParaShapePropertyInfoTests: XCTestCase {
    func testParaShapeProperty1InfoDecodesParagraphBorderBits() throws {
        let property = try HwpParaShapeProperty1.load(0x3000_0000)

        expect(property.rawValue) == 0x3000_0000
        expect(property.borderConnect) == true
        expect(property.borderIgnoreMargin) == true

        let defaultProperty = HwpParaShapeProperty1(rawValue: 0)
        expect(defaultProperty.borderConnect) == false
        expect(defaultProperty.borderIgnoreMargin) == false
    }

    func testParaShapeProperty1DefaultInitializerUsesEmptyBitField() {
        let property = HwpParaShapeProperty1()

        expect(property.rawValue) == 0
        expect(property.borderConnect) == false
        expect(property.borderIgnoreMargin) == false
    }

    func testParaShapeProperty1InfoIsWiredFromRealFixture() throws {
        let hwp = try openHwp(#file, "noori")
        let paraShapes = hwp.docInfo.idMappings.paraShapeArray

        expect(paraShapes).toNot(beEmpty())
        expect(paraShapes[0].property1) == 128
        expect(paraShapes[0].property1Info.rawValue) == paraShapes[0].property1
        expect(paraShapes[0].property1Info.borderConnect) == false
        expect(paraShapes[0].property1Info.borderIgnoreMargin) == false
        expect(paraShapes.contains { $0.property1Info.borderConnect }) == false
        expect(paraShapes.contains { $0.property1Info.borderIgnoreMargin }) == false
    }
}
