import CoreHwp
import Nimble
import XCTest

/**
 doc  version : 5.1.0.1.1
 program version : 10.0.0.5060
 */
class Create2018Tests: XCTestCase {
    func testCreate() throws {
        let (this, official) = try createHwp(#file, "blank-win2018")

        // expect(this) == official
    }

    func testfileHeader() throws {
        let (this, official) = try createHwp(#file, "blank-win2018")

        expect(this.fileHeader) == official.fileHeader
    }

    func testDocInfo() throws {
        let (this, official) = try createHwp(#file, "blank-win2018")

        expect(this.docInfo.documentProperties) == official.docInfo.documentProperties
        expect(this.docInfo.compatibleDocument) == official.docInfo.compatibleDocument

        let thisMappings = this.docInfo.idMappings
        let officialMappings = official.docInfo.idMappings

        expect(thisMappings.faceNameKoreanArray) == officialMappings.faceNameKoreanArray
        expect(thisMappings.faceNameEnglishArray) == officialMappings.faceNameEnglishArray
        expect(thisMappings.faceNameChineseArray) == officialMappings.faceNameChineseArray
        expect(thisMappings.faceNameJapaneseArray) == officialMappings.faceNameJapaneseArray
        expect(thisMappings.faceNameEtcArray) == officialMappings.faceNameEtcArray
        expect(thisMappings.faceNameSymbolArray) == officialMappings.faceNameSymbolArray
        expect(thisMappings.faceNameUserArray) == officialMappings.faceNameUserArray

        expect(thisMappings.borderFillArray) == officialMappings.borderFillArray
        // expect(thisMappings.charShapeArray) == officialMappings.charShapeArray
        expect(thisMappings.tabDefArray) == officialMappings.tabDefArray
        expect(thisMappings.numberingArray) == officialMappings.numberingArray
        expect(thisMappings.paraShapeArray) == officialMappings.paraShapeArray
        expect(thisMappings.styleArray) == officialMappings.styleArray

        // expect(this.docInfo) == official.docInfo
    }

    func testSectionArray() throws {
        let (this, official) = try createHwp(#file, "blank-win2018")

        expect(this.sectionArray.count) == official.sectionArray.count
        expect(this.sectionArray[0].paragraph.count) == official.sectionArray[0].paragraph.count

        let thisParagraph = this.sectionArray[0].paragraph[0]
        let officialParagraph = official.sectionArray[0].paragraph[0]

        expect(thisParagraph.paraHeader) == officialParagraph.paraHeader
        expect(thisParagraph.paraText) == officialParagraph.paraText
        expect(thisParagraph.paraCharShape) == officialParagraph.paraCharShape
        expect(thisParagraph.paraLineSeg) == officialParagraph.paraLineSeg
        expect(thisParagraph.paraRangeTagArray) == officialParagraph.paraRangeTagArray
        expect(thisParagraph.listHeaderArray) == officialParagraph.listHeaderArray

        // expect(thisParagraph.ctrlHeaderArray![0]) == officialParagraph.ctrlHeaderArray![0]
        // expect(thisParagraph.ctrlHeaderArray![1]) == officialParagraph.ctrlHeaderArray![1]

        for officialCtrlId in try XCTUnwrap(officialParagraph.ctrlHeaderArray) {
            switch officialCtrlId {
            case let .section(hwpSectionDef):
                dump(hwpSectionDef.footNoteShape.unknown)
                dump(hwpSectionDef.endNoteShape.unknown)
                dump(hwpSectionDef.unknown)
            default:
                break
            }
        }

        // expect(this.sectionArray) == official.sectionArray
    }

    func testPreviewText() throws {
        let (this, official) = try createHwp(#file, "blank-win2018")

        expect(this.previewText) == official.previewText
    }
}
