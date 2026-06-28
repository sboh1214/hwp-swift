import CoreHwp
import Foundation
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
        expect(korean[0].faceNameRawPayload) == utf16Data("굴림")
        expect(korean[0].alternativeFaceName).to(beNil())
        expect(korean[0].alternativeFaceNameRawPayload).to(beNil())
        expect(try XCTUnwrap(korean[0].defaultFaceName)) == "Gulim"
        expect(korean[0].defaultFaceNameRawPayload) == utf16Data("Gulim")

        expect(korean[1].faceName) == "굴림체"
        expect(korean[1].faceNameRawPayload) == utf16Data("굴림체")
        expect(korean[1].alternativeFaceName).to(beNil())
        expect(korean[1].alternativeFaceNameRawPayload).to(beNil())
        expect(try XCTUnwrap(korean[1].defaultFaceName)) == "GulimChe"
        expect(korean[1].defaultFaceNameRawPayload) == utf16Data("GulimChe")

        let user = hwp.docInfo.idMappings.faceNameUserArray
        expect(user[10].faceName) == "Myeongjo"
        expect(user[10].faceNameRawPayload) == utf16Data("Myeongjo")
        expect(try XCTUnwrap(user[10].alternativeFaceName)) == "명조"
        expect(user[10].alternativeFaceNameRawPayload) == utf16Data("명조")
        expect(user[10].defaultFaceName).to(beNil())
        expect(user[10].defaultFaceNameRawPayload).to(beNil())
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

    func testTabInfoRawPayloads() throws {
        let hwp = try openHwp(#file, "noori")

        let tabDefs = hwp.docInfo.idMappings.tabDefArray
        expect(tabDefs.count) == 3
        expect(tabDefs.reduce(0) { $0 + $1.rawPayload.count }) == 336
        expect(tabDefs.flatMap(\.tabInfoArray).reduce(0) { $0 + $1.rawPayload.count }) == 312

        for tabDef in tabDefs {
            var expectedTabDefPayload = littleEndianData(tabDef.property)
            expectedTabDefPayload.append(littleEndianData(tabDef.count))
            for tabInfo in tabDef.tabInfoArray {
                expect(tabInfo.rawPayload.count) == 8
                expect(tabInfo.rawPayload) == tabInfoPayload(tabInfo)
                expectedTabDefPayload.append(tabInfo.rawPayload)
            }
            expect(tabDef.rawPayload) == expectedTabDefPayload
        }
    }

    func testNumberingFormatRawPayloads() throws {
        let hwp = try openHwp(#file, "noori")

        let numberings = hwp.docInfo.idMappings.numberingArray
        expect(numberings.count) == 2

        for numbering in numberings {
            expect(numbering.formatArray.count) == 7
            assertNumberingFormatRawPayloads(numbering.formatArray)
            if let extendedFormatArray = numbering.extendedFormatArray {
                expect(extendedFormatArray.count) == 3
                assertNumberingFormatRawPayloads(extendedFormatArray)
            }
        }
        expect(numberings.flatMap(\.formatArray).contains { !$0.formatRawPayload.isEmpty }) == true
    }

    func testBulletRawPayloads() throws {
        let hwp = try openHwp(#file, "noori")

        let bullet = try XCTUnwrap(hwp.docInfo.idMappings.bulletArray.first)

        expect(bullet.charRawPayload) == Data([255, 255])
        expect(bullet.checkCharRawPayload) == Data([0, 0])
        expect(bullet.undocumentedTrailing) == [0, 0, 0, 0, 0]
    }

    func testCompatibleDocument() throws {
        let hwp = try openHwp(#file, "noori")

        let compatible = hwp.docInfo.compatibleDocument
        expect(try XCTUnwrap(compatible?.targetDocument)) == 0
        expect(try XCTUnwrap(compatible?.targetDocumentRawPayload)) ==
            Data(repeating: 0, count: 4)
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.char)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.paragraph)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.section)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.object)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.field)) == 0
        expect(try XCTUnwrap(compatible?.layoutCompatibility?.fixedFieldsRawPayload)) ==
            Data(repeating: 0, count: 20)
    }

    func testCompatibleTrackChangeRawPayload() throws {
        let hwp = try openHwp(#file, "noori")
        let compatible = try XCTUnwrap(hwp.docInfo.compatibleDocument)
        let trackChange = try XCTUnwrap(compatible.trackChangeArray.first)

        expect(hwp.docInfo.trackChangeArray).to(beEmpty())
        expect(compatible.trackChangeArray.count) == 1
        expect(trackChange.rawPayload.count) == 1032
        expect(Array(trackChange.rawPayload.prefix(8))) == [
            56, 0, 0, 0, 0, 0, 0, 0,
        ]
        expect(Array(trackChange.rawPayload.suffix(8))) == [
            0, 0, 0, 0, 0, 0, 0, 0,
        ]
        expect(trackChange.unknownChildren).to(beEmpty())
    }
}

private func utf16Data(_ string: String) -> Data {
    var data = Data()
    for codeUnit in string.utf16 {
        var littleEndian = codeUnit.littleEndian
        data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
    }
    return data
}

private func assertNumberingFormatRawPayloads(_ formats: [HwpNumberingFormat]) {
    for format in formats {
        expect(format.formatRawPayload.count) == Int(format.formatLength) * 2
        expect(format.formatRawPayload) == utf16Data(format.format)
    }
}

private func tabInfoPayload(_ tabInfo: HwpTabInfo) -> Data {
    var data = Data()
    data.append(littleEndianData(tabInfo.location))
    data.append(littleEndianData(tabInfo.type))
    data.append(littleEndianData(tabInfo.fillType))
    data.append(littleEndianData(tabInfo.reserved))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
