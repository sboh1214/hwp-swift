@testable import CoreHwp
import Nimble
import XCTest

final class CommonCtrlPropertyRealFixtureTests: XCTestCase {
    func testHancomFixturesDecodeCommonPropertyInfoBits() throws {
        let equationProperty = try commonProperty(0x0C2A_2311, in: openHwp(#file, "equation"))
        let nooriTableProperty = try commonProperty(0x082A_0211, in: openHwp(#file, "noori"))
        let textBoxProperty = try commonProperty(0x046A_4000, in: openHwp(#file, "text-box"))

        expect(equationProperty.propertyInfo.restrictInPage) == true
        expect(equationProperty.propertyInfo.effectiveAllowOverlap) == false
        expect(equationProperty.propertyInfo.widthRelativeTo) == .absolute
        expect(equationProperty.propertyInfo.heightRelativeTo) == .absolute
        expect(equationProperty.propertyInfo.textWrap) == .topAndBottom
        expect(equationProperty.propertyInfo.numberingCategory) == .equation

        expect(nooriTableProperty.propertyInfo.restrictInPage) == false
        expect(nooriTableProperty.propertyInfo.widthRelativeTo) == .absolute
        expect(nooriTableProperty.propertyInfo.heightRelativeTo) == .absolute
        expect(nooriTableProperty.propertyInfo.textWrap) == .topAndBottom
        expect(nooriTableProperty.propertyInfo.numberingCategory) == .table

        expect(textBoxProperty.propertyInfo.restrictInPage) == false
        expect(textBoxProperty.propertyInfo.allowOverlap) == true
        expect(textBoxProperty.propertyInfo.effectiveAllowOverlap) == true
        expect(textBoxProperty.propertyInfo.widthRelativeTo) == .absolute
        expect(textBoxProperty.propertyInfo.heightRelativeTo) == .absolute
        expect(textBoxProperty.propertyInfo.textWrap) == .inFrontOfText
        expect(textBoxProperty.propertyInfo.numberingCategory) == .figure
    }
}

private func commonProperty(_ rawValue: UInt32, in hwp: HwpFile) throws -> HwpCommonCtrlProperty {
    guard let property = commonProperties(in: hwp).first(where: { $0.property == rawValue }) else {
        fail("Expected fixture to contain common control property \(String(rawValue, radix: 16))")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    expect(property.propertyInfo.rawValue) == rawValue
    return property
}

private func commonProperties(in hwp: HwpFile) -> [HwpCommonCtrlProperty] {
    FixtureDerivedValues.tables(from: hwp).map(\.commonCtrlProperty)
        + FixtureDerivedValues.genShapeObjects(from: hwp).map(\.commonCtrlProperty)
        + FixtureDerivedValues.shapeControls(from: hwp).compactMap(\.commonCtrlProperty)
}
