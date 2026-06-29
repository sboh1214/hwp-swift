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

    func testChartFixtureOleComponentSurvivesCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "chart")
        let object = try chartObject(in: hwp)
        let encoded = try JSONEncoder().encode(HwpCtrlId.genShapeObject(object))
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        guard case let .genShapeObject(roundTripped) = decoded else {
            return fail("Expected genShapeObject after Codable round-trip")
        }

        assertChartOleObject(roundTripped)
    }

    func testChartFixtureOleComponentSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "chart")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let object = try chartObject(in: decoded)

        assertChartBinaryDataStorage(decoded)
        assertChartDocInfoBinDataMapping(decoded)
        assertChartOleObject(object)
        expect(decoded.binaryDataArray.map(\.data)) == hwp.binaryDataArray.map(\.data)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
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

    func testImageFixturePictureComponentsSurviveHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "BinData")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let pictures = FixtureDerivedValues
            .allGenShapeObjects(from: decoded)
            .flatMap(\.shapeComponentArray)
            .flatMap(\.pictureArray)

        assertBinDataPictureStorage(decoded)
        assertBinDataPictureComponents(pictures)
        expect(decoded.binaryDataArray.map(\.data)) == hwp.binaryDataArray.map(\.data)
        expect(decoded.docInfo.idMappings.binDataArray.map(\.rawPayload)) ==
            hwp.docInfo.idMappings.binDataArray.map(\.rawPayload)
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testEquationFixtureShapeControlSurvivesHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "equation")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let shapeControls = try equationShapeControlExpectations(fixture)

        FixtureAssertions.assertShapeControls(shapeControls, decoded)
        assertShapeControlPayloadsMatch(
            FixtureDerivedValues.shapeControls(from: decoded),
            FixtureDerivedValues.shapeControls(from: hwp)
        )
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testTextBoxFixtureGenShapeObjectSurvivesHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "text-box")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let genShapeObjects = try textBoxGenShapeObjectExpectations(fixture)

        FixtureAssertions.assertGenShapeObjects(genShapeObjects, decoded)
        assertGenShapeObjectPayloadsMatch(
            FixtureDerivedValues.genShapeObjects(from: decoded),
            FixtureDerivedValues.genShapeObjects(from: hwp)
        )
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testLegacyFixturePolygonObjectPreservesLegacyCommonPropertyAndPayloads() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let object = try legacyPolygonObject(in: hwp)

        assertLegacyPolygonObject(object)
    }

    func testLegacyFixturePolygonObjectSurvivesCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let object = try legacyPolygonObject(in: hwp)
        let encoded = try JSONEncoder().encode(HwpCtrlId.genShapeObject(object))
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        guard case let .genShapeObject(roundTripped) = decoded else {
            return fail("Expected genShapeObject after Codable round-trip")
        }

        assertLegacyPolygonObject(roundTripped)
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

private func equationShapeControlExpectations(
    _ fixture: LoadedFixture
) throws -> [FixtureShapeControlExpectations] {
    guard let controls = fixture.manifest.expectations.shapeControls else {
        fail("Expected equation fixture manifest to declare shape controls")
        return []
    }

    return controls
}

private func textBoxGenShapeObjectExpectations(
    _ fixture: LoadedFixture
) throws -> [FixtureGenShapeObjectExpectations] {
    guard let objects = fixture.manifest.expectations.genShapeObjects else {
        fail("Expected text-box fixture manifest to declare gen shape objects")
        return []
    }

    return objects
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

private func assertShapeControlPayloadsMatch(
    _ decoded: [HwpShapeControl],
    _ original: [HwpShapeControl]
) {
    expect(decoded.map(\.ctrlId)) == original.map(\.ctrlId)
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map { $0.commonCtrlProperty?.rawPayload }) ==
        original.map { $0.commonCtrlProperty?.rawPayload }
    expect(decoded.map { $0.eqEditArray.map(\.rawPayload) }) ==
        original.map { $0.eqEditArray.map(\.rawPayload) }
    expect(decoded.map { $0.eqEditRecords.map(\.payload) }) ==
        original.map { $0.eqEditRecords.map(\.payload) }
    expect(decoded.map { $0.ctrlDataRecords.map(\.rawPayload) }) ==
        original.map { $0.ctrlDataRecords.map(\.rawPayload) }
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
    assertShapeComponentPayloadsMatch(
        decoded.flatMap(\.shapeComponentArray),
        original.flatMap(\.shapeComponentArray)
    )
}

private func assertGenShapeObjectPayloadsMatch(
    _ decoded: [HwpGenShapeObject],
    _ original: [HwpGenShapeObject]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map(\.commonCtrlProperty.rawPayload)) ==
        original.map(\.commonCtrlProperty.rawPayload)
    expect(decoded.map { $0.ctrlDataRecords.map(\.rawPayload) }) ==
        original.map { $0.ctrlDataRecords.map(\.rawPayload) }
    assertShapeComponentPayloadsMatch(
        decoded.flatMap(\.shapeComponentArray),
        original.flatMap(\.shapeComponentArray)
    )
}

private func assertShapeComponentPayloadsMatch(
    _ decoded: [HwpShapeComponent],
    _ original: [HwpShapeComponent]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawCtrlId)) == original.map(\.rawCtrlId)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map { $0.ctrlDataRecords.map(\.rawPayload) }) ==
        original.map { $0.ctrlDataRecords.map(\.rawPayload) }
    expect(decoded.map { $0.rectangleArray.map(\.rawPayload) }) ==
        original.map { $0.rectangleArray.map(\.rawPayload) }
    expect(decoded.map { $0.pictureArray.map(\.rawPayload) }) ==
        original.map { $0.pictureArray.map(\.rawPayload) }
    expect(decoded.map { $0.pictureArray.compactMap(\.binaryDataId) }) ==
        original.map { $0.pictureArray.compactMap(\.binaryDataId) }
    expect(decoded.map { $0.pictureArray.compactMap(\.rawTrailing) }) ==
        original.map { $0.pictureArray.compactMap(\.rawTrailing) }
    expect(decoded.map { $0.oleArray.map(\.rawPayload) }) ==
        original.map { $0.oleArray.map(\.rawPayload) }
    expect(decoded.map { $0.oleArray.compactMap(\.binaryDataId) }) ==
        original.map { $0.oleArray.compactMap(\.binaryDataId) }
    expect(decoded.map { $0.oleArray.compactMap(\.rawTrailing) }) ==
        original.map { $0.oleArray.compactMap(\.rawTrailing) }
    expect(decoded.map { $0.oleRecords.map(\.payload) }) ==
        original.map { $0.oleRecords.map(\.payload) }
    assertRawBackedShapeComponentPayloadsMatch(decoded, original)
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
    assertTextBoxListPayloadsMatch(
        decoded.flatMap(\.textBoxListArray),
        original.flatMap(\.textBoxListArray)
    )
}

private func assertRawBackedShapeComponentPayloadsMatch(
    _ decoded: [HwpShapeComponent],
    _ original: [HwpShapeComponent]
) {
    assertRawBackedShapeComponentRawPayloadsMatch(decoded, original)
    assertRawBackedShapeComponentUnknownChildrenMatch(decoded, original)
}

private func assertRawBackedShapeComponentRawPayloadsMatch(
    _ decoded: [HwpShapeComponent],
    _ original: [HwpShapeComponent]
) {
    expect(decoded.map { $0.lineArray.map(\.rawPayload) }) ==
        original.map { $0.lineArray.map(\.rawPayload) }
    expect(decoded.map { $0.ellipseArray.map(\.rawPayload) }) ==
        original.map { $0.ellipseArray.map(\.rawPayload) }
    expect(decoded.map { $0.arcArray.map(\.rawPayload) }) ==
        original.map { $0.arcArray.map(\.rawPayload) }
    expect(decoded.map { $0.polygonArray.map(\.rawPayload) }) ==
        original.map { $0.polygonArray.map(\.rawPayload) }
    expect(decoded.map { $0.curveArray.map(\.rawPayload) }) ==
        original.map { $0.curveArray.map(\.rawPayload) }
    expect(decoded.map { $0.containerArray.map(\.rawPayload) }) ==
        original.map { $0.containerArray.map(\.rawPayload) }
    expect(decoded.map { $0.chartDataArray.map(\.rawPayload) }) ==
        original.map { $0.chartDataArray.map(\.rawPayload) }
    expect(decoded.map { $0.textartArray.map(\.rawPayload) }) ==
        original.map { $0.textartArray.map(\.rawPayload) }
    expect(decoded.map { $0.formObjectArray.map(\.rawPayload) }) ==
        original.map { $0.formObjectArray.map(\.rawPayload) }
    expect(decoded.map { $0.memoShapeArray.map(\.rawPayload) }) ==
        original.map { $0.memoShapeArray.map(\.rawPayload) }
    expect(decoded.map { $0.memoListArray.map(\.rawPayload) }) ==
        original.map { $0.memoListArray.map(\.rawPayload) }
    expect(decoded.map { $0.videoDataArray.map(\.rawPayload) }) ==
        original.map { $0.videoDataArray.map(\.rawPayload) }
    expect(decoded.map { $0.shapeComponentUnknownArray.map(\.rawPayload) }) ==
        original.map { $0.shapeComponentUnknownArray.map(\.rawPayload) }
}

private func assertRawBackedShapeComponentUnknownChildrenMatch(
    _ decoded: [HwpShapeComponent],
    _ original: [HwpShapeComponent]
) {
    expect(decoded.map { $0.lineArray.map(\.unknownChildren) }) ==
        original.map { $0.lineArray.map(\.unknownChildren) }
    expect(decoded.map { $0.ellipseArray.map(\.unknownChildren) }) ==
        original.map { $0.ellipseArray.map(\.unknownChildren) }
    expect(decoded.map { $0.arcArray.map(\.unknownChildren) }) ==
        original.map { $0.arcArray.map(\.unknownChildren) }
    expect(decoded.map { $0.polygonArray.map(\.unknownChildren) }) ==
        original.map { $0.polygonArray.map(\.unknownChildren) }
    expect(decoded.map { $0.curveArray.map(\.unknownChildren) }) ==
        original.map { $0.curveArray.map(\.unknownChildren) }
    expect(decoded.map { $0.containerArray.map(\.unknownChildren) }) ==
        original.map { $0.containerArray.map(\.unknownChildren) }
    expect(decoded.map { $0.chartDataArray.map(\.unknownChildren) }) ==
        original.map { $0.chartDataArray.map(\.unknownChildren) }
    expect(decoded.map { $0.textartArray.map(\.unknownChildren) }) ==
        original.map { $0.textartArray.map(\.unknownChildren) }
    expect(decoded.map { $0.formObjectArray.map(\.unknownChildren) }) ==
        original.map { $0.formObjectArray.map(\.unknownChildren) }
    expect(decoded.map { $0.memoShapeArray.map(\.unknownChildren) }) ==
        original.map { $0.memoShapeArray.map(\.unknownChildren) }
    expect(decoded.map { $0.memoListArray.map(\.unknownChildren) }) ==
        original.map { $0.memoListArray.map(\.unknownChildren) }
    expect(decoded.map { $0.videoDataArray.map(\.unknownChildren) }) ==
        original.map { $0.videoDataArray.map(\.unknownChildren) }
    expect(decoded.map { $0.shapeComponentUnknownArray.map(\.unknownChildren) }) ==
        original.map { $0.shapeComponentUnknownArray.map(\.unknownChildren) }
}

private func assertTextBoxListPayloadsMatch(
    _ decoded: [HwpListControlList],
    _ original: [HwpListControlList]
) {
    expect(decoded.map(\.headerRawPayload)) == original.map(\.headerRawPayload)
    expect(decoded.map(\.header.rawPayload)) == original.map(\.header.rawPayload)
    expect(decoded.map { $0.paragraphArray.map(\.paraHeader.rawPayload) }) ==
        original.map { $0.paragraphArray.map(\.paraHeader.rawPayload) }
    expect(decoded.map { $0.paragraphArray.map { $0.paraText?.rawPayload } }) ==
        original.map { $0.paragraphArray.map { $0.paraText?.rawPayload } }
    expect(decoded.map { $0.paragraphArray.map(\.paraCharShape.rawPayload) }) ==
        original.map { $0.paragraphArray.map(\.paraCharShape.rawPayload) }
    expect(decoded.map { $0.paragraphArray.map(\.paraLineSeg.rawPayload) }) ==
        original.map { $0.paragraphArray.map(\.paraLineSeg.rawPayload) }
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
