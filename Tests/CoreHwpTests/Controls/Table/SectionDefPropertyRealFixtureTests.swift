@testable import CoreHwp
import Nimble
import XCTest

final class SectionDefPropertyRealFixtureTests: XCTestCase {
    func testSectionDefPropertyDefaultInitializerUsesEmptyBitField() {
        let property = HwpSectionDefProperty()

        expect(property.rawValue) == 0
        expect(property.hideHeader) == false
        expect(property.hideFooter) == false
        expect(property.hideMasterPage) == false
        expect(property.hideBorder) == false
        expect(property.hideFill) == false
        expect(property.hidePageNumberPosition) == false
        expect(property.showFirstPageBorderOnly) == false
        expect(property.showFirstPageFillOnly) == false
        expect(property.textDirectionRawValue) == 0
        expect(property.hideEmptyLine) == false
        expect(property.newPageNumberApplyRawValue) == 0
        expect(property.applyManuscriptPaper) == false
    }

    func testHancomFixtureDecodesSectionDefPropertyAndAlignedFields() throws {
        let hwp = try openHwp(#file, "plain-text-minimal")
        let sectionDef = try firstSectionDef(in: hwp)

        expect(sectionDef.ctrlId) == HwpOtherCtrlId.section.rawValue
        expect(sectionDef.property) == 0
        expect(sectionDef.propertyInfo.rawValue) == 0
        expect(sectionDef.propertyInfo.hideMasterPage) == false
        expect(sectionDef.propertyInfo.hideEmptyLine) == false
        expect(sectionDef.columnSpacing) == 1134
        expect(sectionDef.verticalLineAlign) == 0
        expect(sectionDef.horizontalLineAlign) == 0
        expect(sectionDef.defaultTabSpacing) == 8000
        expect(sectionDef.numberParaShapeId) == 1
        expect(sectionDef.pageStartNumber) == 0
        expect(sectionDef.pictureStartNumber) == 0
        expect(sectionDef.tableStartNumber) == 0
        expect(sectionDef.equationNumber) == 0
        expect(sectionDef.defaultLanguage) == 0
        expect(sectionDef.unknown.count) == 17
    }
}

private func firstSectionDef(in hwp: HwpFile) throws -> HwpSectionDef {
    guard let sectionDef = FixtureDerivedValues.sectionDefinitions(from: hwp).first else {
        fail("Expected fixture to contain a section definition")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }
    return sectionDef
}
