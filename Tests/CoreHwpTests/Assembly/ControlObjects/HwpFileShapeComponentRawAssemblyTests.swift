@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileShapeComponentRawAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesRawShapeComponentChildren()
        throws
    {
        let streams = try rawShapeAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedRawShapeComponentControl()
        var sectionDataArray = streams.sectionDataArray
        sectionDataArray[0].append(injected.recordData)

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: sectionDataArray
        )
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expectRawShapeComponent(in: hwp, match: injected)
        expectRawShapeComponent(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct RawShapeAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedRawShapeComponentControl {
    let recordData: Data
    let commonPayload: Data
    let controlPayload: Data
    let controlRawTrailing: Data
    let componentPayload: Data
    let componentRawTrailing: Data
    let linePayload: Data
    let lineUnknownPayload: Data
    let rectanglePayload: Data
    let rectangleUnknownPayload: Data
    let ellipsePayload: Data
    let arcPayload: Data
    let polygonPayload: Data
    let curvePayload: Data
    let olePayload: Data
    let oleRawTrailing: Data
    let oleUnknownPayload: Data
    let containerPayload: Data
    let chartDataPayload: Data
    let chartDataUnknownPayload: Data
    let textartPayload: Data
    let formObjectPayload: Data
    let memoShapePayload: Data
    let memoListPayload: Data
    let videoDataPayload: Data
    let shapeComponentUnknownPayload: Data
    let ctrlDataPayload: Data
    let ctrlDataUnknownPayload: Data
    let componentUnknownPayload: Data

    // swiftlint:disable:next function_body_length
    init() {
        commonPayload = rawShapeCommonCtrlPropertyPayload(
            ctrlId: .rectangle,
            width: 0x1122_3344,
            height: 0x5566_7788,
            instanceId: 0x99AA_BBCC
        )
        controlRawTrailing = Data([0xC1, 0xC2])
        controlPayload = concatenatedData(commonPayload, controlRawTrailing)
        componentRawTrailing = Data([0xD1, 0xD2, 0xD3])
        componentPayload = concatenatedData(
            rawShapeLittleEndianData(HwpCommonCtrlId.rectangle.rawValue),
            componentRawTrailing
        )
        linePayload = Data([0x10, 0x11])
        lineUnknownPayload = Data([0x12])
        rectanglePayload = Data([0x20, 0x21, 0x22])
        rectangleUnknownPayload = Data([0x23])
        ellipsePayload = Data([0x30])
        arcPayload = Data([0x40, 0x41])
        polygonPayload = Data([0x50, 0x51, 0x52])
        curvePayload = Data([0x60])
        oleRawTrailing = Data([0x70, 0x71])
        olePayload = concatenatedData(rawShapeLittleEndianData(UInt32(7)), oleRawTrailing)
        oleUnknownPayload = Data([0x72])
        containerPayload = Data([0x80])
        chartDataPayload = Data([0x90, 0x91])
        chartDataUnknownPayload = Data([0x92])
        textartPayload = Data([0xA0])
        formObjectPayload = Data([0xA1, 0xA2])
        memoShapePayload = Data([0xA3])
        memoListPayload = Data([0xA4, 0xA5])
        videoDataPayload = Data([0xA6])
        shapeComponentUnknownPayload = Data([0xA7, 0xA8])
        ctrlDataPayload = Data([0xB0, 0xB1])
        ctrlDataUnknownPayload = Data([0xB2])
        componentUnknownPayload = Data([0xB3, 0xB4])

        var data = Data()
        data.append(rawShapeRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: controlPayload
        ))
        data.append(rawShapeRecordData(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: componentPayload
        ))
        data.append(rawShapeRecordData(
            tagId: HwpSectionTag.shapeComponentLine.rawValue,
            level: 3,
            payload: linePayload
        ))
        data.append(rawShapeRecordData(tagId: 0x3D0, level: 4, payload: lineUnknownPayload))
        data.append(rawShapeRecordData(
            tagId: HwpSectionTag.shapeComponentRectangle.rawValue,
            level: 3,
            payload: rectanglePayload
        ))
        data.append(rawShapeRecordData(
            tagId: 0x3D1,
            level: 4,
            payload: rectangleUnknownPayload
        ))
        data.append(rawShapeComponentRecord(.shapeComponentEllipse, ellipsePayload))
        data.append(rawShapeComponentRecord(.shapeComponentArc, arcPayload))
        data.append(rawShapeComponentRecord(.shapeComponentPolygon, polygonPayload))
        data.append(rawShapeComponentRecord(.shapeComponentCurve, curvePayload))
        data.append(rawShapeComponentRecord(.shapeComponentOle, olePayload))
        data.append(rawShapeRecordData(tagId: 0x3D2, level: 4, payload: oleUnknownPayload))
        data.append(rawShapeComponentRecord(.shapeComponentContainer, containerPayload))
        data.append(rawShapeComponentRecord(.chartData, chartDataPayload))
        data.append(rawShapeRecordData(
            tagId: 0x3D3,
            level: 4,
            payload: chartDataUnknownPayload
        ))
        data.append(rawShapeComponentRecord(.shapeComponentTextart, textartPayload))
        data.append(rawShapeComponentRecord(.formObject, formObjectPayload))
        data.append(rawShapeComponentRecord(.memoShape, memoShapePayload))
        data.append(rawShapeComponentRecord(.memoList, memoListPayload))
        data.append(rawShapeComponentRecord(.videoData, videoDataPayload))
        data.append(rawShapeComponentRecord(.shapeComponentUnknown, shapeComponentUnknownPayload))
        data.append(rawShapeComponentRecord(.ctrlData, ctrlDataPayload))
        data.append(rawShapeRecordData(tagId: 0x3D4, level: 4, payload: ctrlDataUnknownPayload))
        data.append(rawShapeRecordData(tagId: 0x3D5, level: 3, payload: componentUnknownPayload))
        recordData = data
    }
}

private func rawShapeAssemblyStreams(fromFixture id: String) throws -> RawShapeAssemblyStreams {
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

    return RawShapeAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectRawShapeComponent(
    in hwp: HwpFile,
    match injected: InjectedRawShapeComponentControl
) {
    let control = rawRectangleControls(from: hwp).last
    expect(control?.ctrlId) == .rectangle
    expect(control?.commonCtrlProperty?.commonCtrlId) == .rectangle
    expect(control?.commonCtrlProperty?.rawPayload) == injected.commonPayload
    expect(control?.rawPayload) == injected.controlPayload
    expect(control?.rawTrailing) == injected.controlRawTrailing
    expect(control?.shapeComponentArray.count) == 1
    expect(control?.unknownChildren).to(beEmpty())

    let component = control?.shapeComponentArray.first
    expect(component?.rawPayload) == injected.componentPayload
    expect(component?.rawCtrlId) == HwpCommonCtrlId.rectangle.rawValue
    expect(component?.ctrlId) == .rectangle
    expect(component?.rawTrailing) == injected.componentRawTrailing
    expect(component?.unknownChildren) == [
        rawShapeUnknownRecord(
            tagId: 0x3D5,
            level: 3,
            payload: injected.componentUnknownPayload
        ),
    ]

    expectRawBackedArrays(on: component, match: injected)
    expectOleAndCtrlData(on: component, match: injected)
}

private func expectRawBackedArrays(
    on component: HwpShapeComponent?,
    match injected: InjectedRawShapeComponentControl
) {
    expect(component?.lineArray.map(\.rawPayload)) == [injected.linePayload]
    expect(component?.lineArray.first?.unknownChildren) == [
        rawShapeUnknownRecord(tagId: 0x3D0, level: 4, payload: injected.lineUnknownPayload),
    ]
    expect(component?.rectangleArray.map(\.rawPayload)) == [injected.rectanglePayload]
    expect(component?.rectangleArray.first?.unknownChildren) == [
        rawShapeUnknownRecord(
            tagId: 0x3D1,
            level: 4,
            payload: injected.rectangleUnknownPayload
        ),
    ]
    expect(component?.ellipseArray.map(\.rawPayload)) == [injected.ellipsePayload]
    expect(component?.arcArray.map(\.rawPayload)) == [injected.arcPayload]
    expect(component?.polygonArray.map(\.rawPayload)) == [injected.polygonPayload]
    expect(component?.curveArray.map(\.rawPayload)) == [injected.curvePayload]
    expect(component?.containerArray.map(\.rawPayload)) == [injected.containerPayload]
    expect(component?.chartDataArray.map(\.rawPayload)) == [injected.chartDataPayload]
    expect(component?.chartDataArray.first?.unknownChildren) == [
        rawShapeUnknownRecord(
            tagId: 0x3D3,
            level: 4,
            payload: injected.chartDataUnknownPayload
        ),
    ]
    expect(component?.textartArray.map(\.rawPayload)) == [injected.textartPayload]
    expect(component?.formObjectArray.map(\.rawPayload)) == [injected.formObjectPayload]
    expect(component?.memoShapeArray.map(\.rawPayload)) == [injected.memoShapePayload]
    expect(component?.memoListArray.map(\.rawPayload)) == [injected.memoListPayload]
    expect(component?.videoDataArray.map(\.rawPayload)) == [injected.videoDataPayload]
    expect(component?.shapeComponentUnknownArray.map(\.rawPayload)) ==
        [injected.shapeComponentUnknownPayload]
}

private func expectOleAndCtrlData(
    on component: HwpShapeComponent?,
    match injected: InjectedRawShapeComponentControl
) {
    let ole = component?.oleArray.first
    expect(component?.oleArray.map(\.rawPayload)) == [injected.olePayload]
    expect(component?.oleRecords) == [
        rawShapeUnknownRecord(
            tagId: HwpSectionTag.shapeComponentOle.rawValue,
            level: 3,
            payload: injected.olePayload,
            children: [
                rawShapeUnknownRecord(
                    tagId: 0x3D2,
                    level: 4,
                    payload: injected.oleUnknownPayload
                ),
            ]
        ),
    ]
    expect(ole?.binaryDataId) == 7
    expect(ole?.rawTrailing) == injected.oleRawTrailing
    expect(ole?.unknownChildren) == [
        rawShapeUnknownRecord(tagId: 0x3D2, level: 4, payload: injected.oleUnknownPayload),
    ]

    expect(component?.ctrlDataRecords.map(\.rawPayload)) == [injected.ctrlDataPayload]
    expect(component?.ctrlDataRecords.first?.unknownChildren) == [
        rawShapeUnknownRecord(tagId: 0x3D4, level: 4, payload: injected.ctrlDataUnknownPayload),
    ]
}

private func rawRectangleControls(from hwp: HwpFile) -> [HwpShapeControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .rectangle(shapeControl) = control else {
                return nil
            }
            return shapeControl
        }
    }
}

private func rawShapeCommonCtrlPropertyPayload(
    ctrlId: HwpCommonCtrlId,
    width: HWPUNIT,
    height: HWPUNIT,
    instanceId: UInt32
) -> Data {
    var data = Data()
    data.append(rawShapeLittleEndianData(ctrlId.rawValue))
    data.append(rawShapeLittleEndianData(UInt32(0x0102_0304)))
    data.append(rawShapeLittleEndianData(HWPUNIT(0x1111)))
    data.append(rawShapeLittleEndianData(HWPUNIT(0x2222)))
    data.append(rawShapeLittleEndianData(width))
    data.append(rawShapeLittleEndianData(height))
    data.append(rawShapeLittleEndianData(Int32(7)))
    data.append(rawShapeLittleEndianData(HWPUNIT16(1)))
    data.append(rawShapeLittleEndianData(HWPUNIT16(2)))
    data.append(rawShapeLittleEndianData(HWPUNIT16(3)))
    data.append(rawShapeLittleEndianData(HWPUNIT16(4)))
    data.append(rawShapeLittleEndianData(instanceId))
    data.append(rawShapeLittleEndianData(Int32(1)))
    data.append(rawShapeLittleEndianData(WORD(0)))
    return data
}

private func rawShapeComponentRecord(_ tag: HwpSectionTag, _ payload: Data) -> Data {
    rawShapeRecordData(tagId: tag.rawValue, level: 3, payload: payload)
}

private func rawShapeRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = rawShapeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func rawShapeUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func rawShapeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
