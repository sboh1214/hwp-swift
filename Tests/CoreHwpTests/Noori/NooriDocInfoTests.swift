import CoreHwp
import Nimble
import XCTest

final class NooriDocInfoTests: XCTestCase {
    func testSectionSize() throws {
        let hwp = try openHwp(#file, "noori")

        expect(hwp.docInfo.documentProperties.sectionSize) == 1
    }

    func testStartingIndex() throws {
        let hwp = try openHwp(#file, "noori")

        let index = hwp.docInfo.documentProperties.startingIndex
        expect(index.page) == 1
        expect(index.footnote) == 1
        expect(index.endnote) == 1
        expect(index.picture) == 1
        expect(index.table) == 1
        expect(index.equation) == 1
    }

    func testCaratLocation() throws {
        let hwp = try openHwp(#file, "noori")

        let location = hwp.docInfo.documentProperties.caratLocation
        expect(location.listId) == 11
        expect(location.paragraphId) == 2
        expect(location.charIndex) == 14
    }

    func testBinData() throws {
        let hwp = try openHwp(#file, "noori")

        let bin = hwp.docInfo.idMappings.binDataArray
        expect(bin[0].extensionName) == "jpg"
        expect(bin[1].extensionName) == "bmp"
        expect(bin[2].extensionName) == "bmp"
        expect(bin[3].extensionName) == "jpg"
    }

    func testFaceName() throws {
        let hwp = try openHwp(#file, "noori")

        let korean = hwp.docInfo.idMappings.faceNameKoreanArray
        expect(korean[0].faceName) == "굴림"
        expect(korean[0].alternativeFaceName).to(beNil())
        expect(try XCTUnwrap(korean[0].defaultFaceName)) == "Gulim"

        expect(korean[1].faceName) == "굴림체"
        expect(korean[1].alternativeFaceName).to(beNil())
        expect(try XCTUnwrap(korean[1].defaultFaceName)) == "GulimChe"

        let user = hwp.docInfo.idMappings.faceNameUserArray
        expect(user[10].faceName) == "Myeongjo"
        expect(try XCTUnwrap(user[10].alternativeFaceName)) == "명조"
        expect(user[10].defaultFaceName).to(beNil())
    }

    func testBorderFill() throws {
        let hwp = try openHwp(#file, "noori")

        let border = hwp.docInfo.idMappings.borderFillArray
        expect(border[0].borderColor[0]) == HwpColor(0, 0, 0)
    }

    func testCharShape() throws {
        let hwp = try openHwp(#file, "noori")

        let char = hwp.docInfo.idMappings.charShapeArray
        // expect(char[0].property) == HwpCharShapeProperty()
        expect(char[0].faceColor) == HwpColor(0, 0, 0)
        expect(char[0].borderFillId) == 2
        expect(char[0].faceId) == [5, 5, 5, 5, 5, 5, 5]
        expect(char[0].faceLocation) == [0, 0, 0, 0, 0, 0, 0]
        expect(char[0].faceRelativeSize) == Array(repeating: 100, count: 7)
        expect(char[0].faceScaleX) == Array(repeating: 100, count: 7)
        expect(char[0].shadeColor) == HwpColor(255, 255, 255)
        expect(char[0].shadowColor) == HwpColor(178, 178, 178)
        expect(char[0].underlineColor) == HwpColor(0, 0, 0)
        expect(try XCTUnwrap(char[0].strikethroughColor)) == HwpColor(0, 0, 0)
    }

    func testTabDef() throws {
        let hwp = try openHwp(#file, "noori")

        let shape = hwp.docInfo.idMappings.paraShapeArray
        expect(shape[0].property1) == 128
        expect(shape[46].property1) == 268
    }

    func testCtrlHeader() {
        // expect(hwp.sectionArray[0].paragraph[2].ctrlHeaderArray![0].ctrlId) == 1885826672)
    }

    func testCompatibleDocument() throws {
        let hwp = try openHwp(#file, "noori")

        let compatible = hwp.docInfo.compatibleDocument
        expect(try XCTUnwrap(compatible?.targetDocument)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.char)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.paragraph)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.section)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.object)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.field)) == 0
    }
}
