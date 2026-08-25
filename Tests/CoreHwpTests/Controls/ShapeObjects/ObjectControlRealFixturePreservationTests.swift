@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ObjectFixturePreservationTests: XCTestCase {
    func testChartFixtureOleComponentPreservesBinaryDataReferenceAndPayloads() throws {
        let hwp = try openHwp(#file, "chart")
        let object = try chartObject(in: hwp)

        assertChartBinaryDataStorage(hwp)
        assertChartDocInfoBinDataMapping(hwp)
        assertChartOleObject(object)
    }

    func testImageFixturePictureComponentsPreserveBinaryDataReferencesAndPayloads() throws {
        let hwp = try openHwp(#file, "BinData")
        let pictures = FixtureDerivedValues
            .allGenShapeObjects(from: hwp)
            .flatMap(\.shapeComponentArray)
            .flatMap(\.pictureArray)

        assertBinDataPictureStorage(hwp)
        assertBinDataPictureComponents(pictures)
    }

    func testEquationFixtureEqEditParsesVersionInfoAfterUnknownBaselineField() throws {
        let hwp = try openHwp(#file, "equation")
        let edit = try equationEdit(in: hwp)

        expect(edit.property) == 0
        expect(edit.equationTextLength) == 3
        expect(edit.equationText) == "x=1"
        expect(edit.letterSize) == 1000
        expect(edit.textColor) == HwpColor(0, 0, 0)
        expect(edit.unknownAfterBaseline) == 0
        expect(edit.unknownAfterBaselineRawPayload) == Data([0, 0])
        expect(edit.versionInfoLength) == 19
        expect(edit.versionInfo) == "Equation Version 60"
        expect(edit.fontNameLength) == 9
        expect(edit.fontName) == "HancomEQN"
        expect(edit.rawTrailing) == Data()
    }

    func testLegacyFixturePolygonObjectPreservesLegacyCommonPropertyAndPayloads() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let object = try legacyPolygonObject(in: hwp)

        assertLegacyPolygonObject(object)
    }
}

private func chartObject(in hwp: HwpFile) throws -> HwpGenShapeObject {
    guard let object = FixtureDerivedValues
        .allGenShapeObjects(from: hwp)
        .first(where: { object in
            object.shapeComponentArray
                .flatMap(\.oleArray)
                .contains { $0.binaryDataId == 1 }
        })
    else {
        fail("Expected chart fixture to contain OLE shape object")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    return object
}

private func legacyPolygonObject(in hwp: HwpFile) throws -> HwpGenShapeObject {
    guard let object = FixtureDerivedValues
        .allGenShapeObjects(from: hwp)
        .first(where: { object in
            object.commonCtrlProperty.rawPayload.count == 44
                && object.shapeComponentArray.contains { $0.ctrlId == .polygon }
        })
    else {
        fail("Expected legacy fixture to contain polygon genShapeObject")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    return object
}

private func equationEdit(in hwp: HwpFile) throws -> HwpEquationEdit {
    let edits = FixtureDerivedValues.shapeControls(from: hwp).flatMap(\.eqEditArray)
    guard let edit = edits.first else {
        fail("Expected equation fixture to contain an EQEDIT record")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.eqEdit.rawValue)
    }

    expect(edits.count) == 1
    return edit
}

private func assertChartBinaryDataStorage(_ hwp: HwpFile) {
    expect(hwp.binaryDataArray.map(\.name)) == ["BIN0001.OLE"]
    expect(hwp.binaryDataArray.map(\.streamId)) == [1]
    expect(hwp.binaryDataArray.map(\.extensionName)) == ["OLE"]
    expect(hwp.binaryDataArray.map(\.data.count)) == [15876]
    expect(hwp.binaryDataArray.map { Array($0.data.prefix(8)) }) == [
        [0, 62, 0, 0, 208, 207, 17, 224],
    ]
    expect(hwp.binaryDataArray.map { Array($0.data.suffix(8)) }) == [
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]
}

private func assertChartDocInfoBinDataMapping(_ hwp: HwpFile) {
    let binData = hwp.docInfo.idMappings.binDataArray
    expect(binData.map(\.streamId)) == [1]
    expect(binData.map(\.extensionName)) == ["OLE"]
    expect(binData.map(\.rawPayload.count)) == [12]
    expect(binData.map(\.rawPayload)) == [
        Data([2, 0, 1, 0, 3, 0, 79, 0, 76, 0, 69, 0]),
    ]
}

private func assertBinDataPictureStorage(_ hwp: HwpFile) {
    expect(hwp.binaryDataArray.map(\.name)) == [
        "BIN0001.png",
        "BIN0002.jpeg",
        "BIN0003.gif",
    ]
    expect(hwp.binaryDataArray.map(\.streamId)) == [1, 2, 3]
    expect(hwp.binaryDataArray.map(\.extensionName)) == ["png", "jpeg", "gif"]
    expect(hwp.binaryDataArray.map(\.data.count)) == [62875, 51551, 20462]
    expect(hwp.docInfo.idMappings.binDataArray.map(\.streamId)) == [1, 2, 3]
    expect(hwp.docInfo.idMappings.binDataArray.map(\.extensionName)) == ["png", "jpeg", "gif"]
}

private func assertBinDataPictureComponents(_ pictures: [HwpShapeComponentPicture]) {
    let expectedRawTrailingSuffix: [UInt8] = [0, 0, 0, 128, 50, 2, 0, 104, 60, 1, 0, 0]

    expect(pictures.count) == 3
    expect(pictures.map(\.binaryDataId)) == [1, 2, 3]
    expect(pictures.map(\.rawPayload.count)) == [91, 91, 91]
    expect(pictures.map(\.unknownChildren.count)) == [0, 0, 0]

    for picture in pictures {
        let expectedRawTrailing = Data(picture.rawPayload.dropFirst(73))
        expect(picture.rawTrailing) == Optional(expectedRawTrailing)
        expect(picture.rawTrailing?.count) == 18
        expect(Array((picture.rawTrailing ?? Data()).suffix(expectedRawTrailingSuffix.count))) ==
            expectedRawTrailingSuffix
    }
}

private func assertChartOleObject(_ object: HwpGenShapeObject) {
    expect(object.commonCtrlProperty.commonCtrlId) == .genShapeObject
    expect(object.commonCtrlProperty.width) == 32250
    expect(object.commonCtrlProperty.height) == 18750
    expect(object.commonCtrlProperty.rawPayload.count) == 46
    expect(Array(object.commonCtrlProperty.rawPayload.prefix(12))) == [
        32, 111, 115, 103, 16, 34, 10, 20, 0, 0, 0, 0,
    ]
    expect(object.rawPayload) == object.commonCtrlProperty.rawPayload
    expect(object.rawTrailing).to(beEmpty())
    expect(object.unknownChildren).to(beEmpty())

    expect(object.shapeComponentArray.count) == 1
    let component = object.shapeComponentArray.first
    expect(component?.rawCtrlId) == HwpCommonCtrlId.ole.rawValue
    expect(component?.ctrlId) == .ole
    expect(component?.rawPayload.count) == 196
    expect(component.map { Array($0.rawPayload.prefix(12)) }) == [
        101, 108, 111, 36, 101, 108, 111, 36, 0, 0, 0, 0,
    ]
    expect(component.map { Array($0.rawPayload.suffix(12)) }) == [
        0, 0, 240, 63, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
    expect(component?.unknownChildren).to(beEmpty())

    expect(component?.oleArray.count) == 1
    let ole = component?.oleArray.first
    expect(ole?.binaryDataId) == 1
    expect(ole?.rawPayload.count) == 30
    expect(ole?.rawTrailing) == ole.map { Data($0.rawPayload.dropFirst(4)) }
    expect(ole.map { Array($0.rawPayload.prefix(12)) }) == [
        1, 0, 0, 0, 32, 28, 0, 0, 32, 28, 0, 0,
    ]
    expect(ole.map { Array($0.rawPayload.suffix(12)) }) == [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
    expect(ole?.unknownChildren).to(beEmpty())
    expect(component?.oleRecords.map(\.payload)) == [ole?.rawPayload].compactMap { $0 }
}

private func assertLegacyPolygonObject(_ object: HwpGenShapeObject) {
    expect(object.commonCtrlProperty.commonCtrlId) == .genShapeObject
    expect(object.commonCtrlProperty.width) == 283
    expect(object.commonCtrlProperty.height) == 283
    expect(object.commonCtrlProperty.rawPayload.count) == 44
    expect(Array(object.commonCtrlProperty.rawPayload.prefix(12))) == [
        32, 111, 115, 103, 0, 64, 106, 4, 36, 72, 0, 0,
    ]
    expect(Array(object.commonCtrlProperty.rawPayload.suffix(12))) == [
        0, 0, 0, 0, 124, 67, 101, 102, 0, 0, 0, 0,
    ]
    expect(object.rawPayload) == object.commonCtrlProperty.rawPayload
    expect(object.rawTrailing).to(beEmpty())

    expect(object.shapeComponentArray.count) == 1
    let component = object.shapeComponentArray.first
    expect(component?.rawCtrlId) == HwpCommonCtrlId.polygon.rawValue
    expect(component?.ctrlId) == .polygon
    expect(component?.rawPayload.count) == 239
    expect(component.map { Array($0.rawPayload.prefix(12)) }) == [
        108, 111, 112, 36, 108, 111, 112, 36, 0, 0, 0, 0,
    ]
    expect(component.map { Array($0.rawPayload.suffix(12)) }) == [
        0, 0, 0, 0, 0, 0, 125, 67, 101, 38, 0, 0,
    ]
    expect(component?.unknownChildren).to(beEmpty())

    expect(component?.polygonArray.count) == 1
    let polygon = component?.polygonArray.first
    expect(polygon?.rawPayload.count) == 24
    expect(polygon.map { Array($0.rawPayload.prefix(12)) }) == [
        2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
    expect(polygon.map { Array($0.rawPayload.suffix(12)) }) == [
        27, 1, 0, 0, 27, 1, 0, 0, 0, 0, 0, 0,
    ]
    expect(polygon?.unknownChildren).to(beEmpty())
}
