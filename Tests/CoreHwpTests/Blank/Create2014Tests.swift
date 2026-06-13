import Nimble
import XCTest

/**
 doc version : unknown
 program version : 10.30.3(2478)
 */
final class Create2014Tests: XCTestCase {
    func testCreate() {
        // expect(expected, actual)
    }

    func testfileHeader() throws {
        let (this, official) = try createHwp(#file, "blank-mac2014vp")

        expect(this.fileHeader) == official.fileHeader
    }

    func testDocInfo() throws {
        let (this, official) = try createHwp(#file, "blank-mac2014vp")

        expect(official.docInfo.documentProperties) == this.docInfo.documentProperties
        expect(official.docInfo.compatibleDocument) == this.docInfo.compatibleDocument

        let officialMappings = official.docInfo.idMappings
        let thisMappings = this.docInfo.idMappings
        // expect(expectedMappings.faceNameArray) == actualMappings.faceNameArray
        expect(officialMappings.borderFillArray) == thisMappings.borderFillArray
        // expect(officialMappings.charShapeArray) == thisMappings.charShapeArray
        expect(officialMappings.paraShapeArray) == thisMappings.paraShapeArray
        expect(officialMappings.forbiddenCharArray) == thisMappings.forbiddenCharArray

        // expect(expected.docInfo, actual.docInfo)
    }

    func testSectionArray() throws {
        let (this, official) = try createHwp(#file, "blank-mac2014vp")

        expect(official.sectionArray.count) == this.sectionArray.count

        // expect(official.sectionArray, this.sectionArray)
    }
}
