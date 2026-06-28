import Nimble
import XCTest

final class NooriSectionTests: XCTestCase {
    func testParagraph() throws {
        let hwp = try openHwp(#file, "noori")

        for index in 0 ... 20 {
            expect(hwp.sectionArray[0].paragraph[index]).notTo(beNil())
        }
    }

    func testParaText() throws {
        let hwp = try openHwp(#file, "noori")

        let text = hwp.sectionArray[0].paragraph[0].paraText
        expect(try XCTUnwrap(text?.charArray[0].type)) == .extended
        expect(try XCTUnwrap(text?.charArray[3].type)) == .char

        expect(try XCTUnwrap(text?.charArray[0].value)) == 2
        expect(try XCTUnwrap(text?.charArray[2].value)) == 11
        expect(try XCTUnwrap(text?.charArray[3].value)) == 13

        expect(hwp.sectionArray[0].paragraph[15].paraText).to(beNil())
        expect(hwp.sectionArray[0].paragraph[16].paraText).to(beNil())
        expect(hwp.sectionArray[0].paragraph[17].paraText).to(beNil())
    }

    func testParaCharShape() throws {
        let hwp = try openHwp(#file, "noori")

        expect(hwp.sectionArray[0].paragraph[0].paraCharShape.startingIndex[0]) == 0
        expect(hwp.sectionArray[0].paragraph[0].paraCharShape.shapeId[0]) == 19
        expect(hwp.sectionArray[0].paragraph[20].paraCharShape.startingIndex[0]) == 0
        expect(hwp.sectionArray[0].paragraph[20].paraCharShape.shapeId[0]) == 30
    }

    func testParaLineSeg() throws {
        let hwp = try openHwp(#file, "noori")

        let seg0 = hwp.sectionArray[0].paragraph[0].paraLineSeg.paraLineSegInternalArray[0]
        expect(seg0.textStartingIndex) == 0
        expect(seg0.lineLocation) == 0
        expect(seg0.lineHeight) == 6134
        expect(seg0.textHeight) == 6134
        expect(seg0.baselineDistance) == 5214
        expect(seg0.lineSpacing) == 840
        expect(seg0.startingLocation) == 0
        expect(seg0.width) == 48188

        expect(hwp.sectionArray[0].paragraph[20].paraLineSeg).notTo(beNil())
    }

    func testTable() throws {
        let hwp = try openHwp(#file, "noori")

        switch try XCTUnwrap(hwp.sectionArray[0].paragraph[1].ctrlHeaderArray?[0]) {
        case let .table(hwpTable):
            expect(hwpTable.commonCtrlProperty.verticalOffset) == 0
            expect(hwpTable.commonCtrlProperty.horizontalOffset) == 0
            expect(hwpTable.commonCtrlProperty.width) == 48230
            expect(hwpTable.commonCtrlProperty.height) == 6869
            expect(hwpTable.commonCtrlProperty.zOrder) == 0
        default:
            fail("Ctrl is not Table")
        }
    }

    func testGenShapeObject() throws {
        let hwp = try openHwp(#file, "noori")

        switch try XCTUnwrap(hwp.sectionArray[0].paragraph[0].ctrlHeaderArray?[2]) {
        case let .genShapeObject(hwpGenShapeObject):
            expect(hwpGenShapeObject.commonCtrlProperty.verticalOffset) == 0
            expect(hwpGenShapeObject.commonCtrlProperty.horizontalOffset) == 0
            expect(hwpGenShapeObject.commonCtrlProperty.width) == 48104
            expect(hwpGenShapeObject.commonCtrlProperty.height) == 6134
            expect(hwpGenShapeObject.commonCtrlProperty.zOrder) == 8
        default:
            fail("Ctrl is not GenShapeObject")
        }
    }

    func testColumn() throws {
        let hwp = try openHwp(#file, "noori")

        switch try XCTUnwrap(hwp.sectionArray[0].paragraph[0].ctrlHeaderArray?[1]) {
        case let .column(hwpColumn):
            expect(hwpColumn.widthArray).to(beNil())
        default:
            fail("Ctrl is not Column")
        }
    }
}
