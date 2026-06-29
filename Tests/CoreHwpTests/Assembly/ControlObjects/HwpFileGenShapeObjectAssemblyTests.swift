@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileGenShapeObjectAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesGenShapeObjectThroughCodableRoundTrip()
        throws
    {
        let streams = try genShapeAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedGenShapeObject(
            baseSectionData: try XCTUnwrap(streams.sectionDataArray.first)
        )
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0] = injected.sectionData

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expectGenShapeObject(in: hwp, match: injected)
        expectGenShapeObject(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct GenShapeAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedGenShapeObject {
    let sectionData: Data
    let commonPayload: Data
    let controlPayload: Data
    let rawTrailing: Data
    let componentPayload: Data
    let componentRawTrailing: Data
    let rectanglePayload: Data
    let rectangleUnknownPayload: Data
    let componentCtrlDataPayload: Data
    let componentCtrlDataUnknownPayload: Data
    let componentUnknownPayload: Data
    let topCtrlDataPayload: Data
    let topCtrlDataUnknownPayload: Data
    let objectUnknownPayload: Data
    let objectGrandchildPayload: Data

    init(baseSectionData: Data) {
        commonPayload = genShapeCommonPropertyPayload(
            width: 0x1111_2222,
            height: 0x3333_4444,
            instanceId: 0x5555_6666
        )
        rawTrailing = Data([0xDE, 0xAD])
        controlPayload = concatenatedData(commonPayload, rawTrailing)
        componentRawTrailing = Data([0xA0, 0xA1])
        componentPayload = concatenatedData(
            genShapeLittleEndianData(HwpCommonCtrlId.rectangle.rawValue),
            componentRawTrailing
        )
        rectanglePayload = Data([0x10, 0x11])
        rectangleUnknownPayload = Data([0x20])
        componentCtrlDataPayload = Data([0xCC])
        componentCtrlDataUnknownPayload = Data([0x30])
        componentUnknownPayload = Data([0xDD])
        topCtrlDataPayload = Data([0xEE])
        topCtrlDataUnknownPayload = Data([0x50])
        objectUnknownPayload = Data([0xFF])
        objectGrandchildPayload = Data([0xFE])

        let recordParts = GenShapeRecordParts(
            controlPayload: controlPayload,
            componentPayload: componentPayload,
            rectanglePayload: rectanglePayload,
            rectangleUnknownPayload: rectangleUnknownPayload,
            componentCtrlDataPayload: componentCtrlDataPayload,
            componentCtrlDataUnknownPayload: componentCtrlDataUnknownPayload,
            componentUnknownPayload: componentUnknownPayload,
            topCtrlDataPayload: topCtrlDataPayload,
            topCtrlDataUnknownPayload: topCtrlDataUnknownPayload,
            objectUnknownPayload: objectUnknownPayload,
            objectGrandchildPayload: objectGrandchildPayload
        )
        sectionData = assembledGenShapeData(
            baseSectionData: baseSectionData,
            parts: recordParts
        )
    }
}

private struct GenShapeRecordParts {
    let controlPayload: Data
    let componentPayload: Data
    let rectanglePayload: Data
    let rectangleUnknownPayload: Data
    let componentCtrlDataPayload: Data
    let componentCtrlDataUnknownPayload: Data
    let componentUnknownPayload: Data
    let topCtrlDataPayload: Data
    let topCtrlDataUnknownPayload: Data
    let objectUnknownPayload: Data
    let objectGrandchildPayload: Data
}

private func assembledGenShapeData(
    baseSectionData: Data,
    parts: GenShapeRecordParts
) -> Data {
    var data = baseSectionData
    data.append(genShapeRecordData(
        tagId: HwpSectionTag.ctrlHeader.rawValue,
        level: 1,
        payload: parts.controlPayload
    ))
    data.append(genShapeRecordData(
        tagId: HwpSectionTag.shapeComponent.rawValue,
        level: 2,
        payload: parts.componentPayload
    ))
    data.append(genShapeRecordData(
        tagId: HwpSectionTag.shapeComponentRectangle.rawValue,
        level: 3,
        payload: parts.rectanglePayload
    ))
    data.append(genShapeRecordData(tagId: 0x3D0, level: 4, payload: parts.rectangleUnknownPayload))
    data.append(genShapeRecordData(
        tagId: HwpSectionTag.ctrlData.rawValue,
        level: 3,
        payload: parts.componentCtrlDataPayload
    ))
    data.append(genShapeRecordData(
        tagId: 0x3D1,
        level: 4,
        payload: parts.componentCtrlDataUnknownPayload
    ))
    data.append(genShapeRecordData(tagId: 0x3D2, level: 3, payload: parts.componentUnknownPayload))
    data.append(genShapeRecordData(
        tagId: HwpSectionTag.ctrlData.rawValue,
        level: 2,
        payload: parts.topCtrlDataPayload
    ))
    data.append(genShapeRecordData(
        tagId: 0x3D3,
        level: 3,
        payload: parts.topCtrlDataUnknownPayload
    ))
    data.append(genShapeRecordData(tagId: 0x3D4, level: 2, payload: parts.objectUnknownPayload))
    data.append(genShapeRecordData(tagId: 0x3D5, level: 3, payload: parts.objectGrandchildPayload))
    return data
}

private func genShapeAssemblyStreams(fromFixture id: String) throws -> GenShapeAssemblyStreams {
    let fixture = try FixtureLoader.load(id: id)
    let ole: OLEFile
    do {
        ole = try OLEFile(fixture.documentURL.path)
    } catch {
        throw HwpError.invalidOLEFile(reason: String(describing: error))
    }

    let streams = try StreamReader.rootStreams(from: ole.root.children)
    let reader = StreamReader(ole, streams)
    let fileHeader = try HwpFileHeader.load(reader.getDataFromStream(.fileHeader, false))
    let docInfoData = try reader.getDataFromStream(
        .docInfo,
        fileHeader.fileProperty.isCompressed
    )
    let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)
    let sectionDataArray = try reader.getDataFromStorage(
        .bodyText,
        fileHeader.fileProperty.isCompressed,
        expectedCount: Int(docInfo.documentProperties.sectionSize)
    )

    return GenShapeAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectGenShapeObject(
    in hwp: HwpFile,
    match injected: InjectedGenShapeObject
) {
    let object = genShapeObjects(from: hwp).last

    expectGenShapeObjectHeader(object, match: injected)
    expectGenShapeObjectComponent(object?.shapeComponentArray.first, match: injected)
}

private func expectGenShapeObjectHeader(
    _ object: HwpGenShapeObject?,
    match injected: InjectedGenShapeObject
) {
    expect(object?.commonCtrlProperty.commonCtrlId) == .genShapeObject
    expect(object?.commonCtrlProperty.rawPayload) == injected.commonPayload
    expect(object?.commonCtrlProperty.width) == 0x1111_2222
    expect(object?.commonCtrlProperty.height) == 0x3333_4444
    expect(object?.commonCtrlProperty.instanceId) == 0x5555_6666
    expect(object?.rawPayload) == injected.controlPayload
    expect(object?.rawTrailing) == injected.rawTrailing
    expect(object?.shapeComponentArray.count) == 1
    expect(object?.ctrlDataRecords.map(\.rawPayload)) == [injected.topCtrlDataPayload]
    expect(object?.ctrlDataRecords.first?.unknownChildren) == [
        expectedGenShapeUnknownRecord(
            tagId: 0x3D3,
            level: 3,
            payload: injected.topCtrlDataUnknownPayload
        ),
    ]
    expect(object?.unknownChildren) == [
        expectedGenShapeUnknownRecord(
            tagId: 0x3D4,
            level: 2,
            payload: injected.objectUnknownPayload,
            children: [
                expectedGenShapeUnknownRecord(
                    tagId: 0x3D5,
                    level: 3,
                    payload: injected.objectGrandchildPayload
                ),
            ]
        ),
    ]
}

private func expectGenShapeObjectComponent(
    _ component: HwpShapeComponent?,
    match injected: InjectedGenShapeObject
) {
    expect(component?.rawPayload) == injected.componentPayload
    expect(component?.rawCtrlId) == HwpCommonCtrlId.rectangle.rawValue
    expect(component?.ctrlId) == .rectangle
    expect(component?.rawTrailing) == injected.componentRawTrailing
    expect(component?.rectangleArray.map(\.rawPayload)) == [injected.rectanglePayload]
    expect(component?.rectangleArray.first?.unknownChildren) == [
        expectedGenShapeUnknownRecord(
            tagId: 0x3D0,
            level: 4,
            payload: injected.rectangleUnknownPayload
        ),
    ]
    expect(component?.ctrlDataRecords.map(\.rawPayload)) == [injected.componentCtrlDataPayload]
    expect(component?.ctrlDataRecords.first?.unknownChildren) == [
        expectedGenShapeUnknownRecord(
            tagId: 0x3D1,
            level: 4,
            payload: injected.componentCtrlDataUnknownPayload
        ),
    ]
    expect(component?.unknownChildren) == [
        expectedGenShapeUnknownRecord(
            tagId: 0x3D2,
            level: 3,
            payload: injected.componentUnknownPayload
        ),
    ]
}

private func genShapeObjects(from hwp: HwpFile) -> [HwpGenShapeObject] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .genShapeObject(object) = control else {
                return nil
            }
            return object
        }
    }
}

private func genShapeCommonPropertyPayload(
    width: HWPUNIT,
    height: HWPUNIT,
    instanceId: UInt32
) -> Data {
    var data = Data()
    data.append(genShapeLittleEndianData(HwpCommonCtrlId.genShapeObject.rawValue))
    data.append(genShapeLittleEndianData(UInt32(0x0102_0304)))
    data.append(genShapeLittleEndianData(HWPUNIT(0x1111)))
    data.append(genShapeLittleEndianData(HWPUNIT(0x2222)))
    data.append(genShapeLittleEndianData(width))
    data.append(genShapeLittleEndianData(height))
    data.append(genShapeLittleEndianData(Int32(7)))
    data.append(genShapeLittleEndianData(HWPUNIT16(1)))
    data.append(genShapeLittleEndianData(HWPUNIT16(2)))
    data.append(genShapeLittleEndianData(HWPUNIT16(3)))
    data.append(genShapeLittleEndianData(HWPUNIT16(4)))
    data.append(genShapeLittleEndianData(instanceId))
    data.append(genShapeLittleEndianData(Int32(1)))
    data.append(genShapeLittleEndianData(WORD(0)))
    return data
}

private func genShapeRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = genShapeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func expectedGenShapeUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func genShapeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
