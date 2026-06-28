@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileCommonShapeControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyClassifiesCommonShapeControls()
        throws
    {
        let streams = try commonShapeAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedCommonShapeControls()
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

        expectCommonShapeControls(in: hwp, match: injected)
        expectCommonShapeControls(in: decoded, match: injected)
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct CommonShapeAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedCommonShapeControls {
    let cases: [InjectedCommonShapeControl]
    let recordData: Data

    init() {
        let ids: [HwpCommonCtrlId] = [
            .line,
            .ellipse,
            .arc,
            .polygon,
            .curve,
            .ole,
            .container,
        ]
        cases = ids.enumerated().map { index, id in
            InjectedCommonShapeControl(ctrlId: id, index: index)
        }
        recordData = cases.reduce(into: Data()) { data, shapeCase in
            data.append(shapeCase.recordData)
        }
    }
}

private struct InjectedCommonShapeControl {
    let ctrlId: HwpCommonCtrlId
    let recordData: Data
    let commonPayload: Data
    let controlPayload: Data
    let rawTrailing: Data
    let childTagId: UInt32
    let childPayload: Data
    let grandchildTagId: UInt32
    let grandchildPayload: Data

    init(ctrlId: HwpCommonCtrlId, index: Int) {
        self.ctrlId = ctrlId
        commonPayload = commonShapePropertyPayload(
            ctrlId: ctrlId,
            width: HWPUNIT(0x1000 + index),
            height: HWPUNIT(0x2000 + index),
            instanceId: UInt32(0x3000 + index)
        )
        rawTrailing = Data([BYTE(0x40 + index), BYTE(0x50 + index)])
        controlPayload = commonPayload + rawTrailing
        childTagId = 0x3E0 + UInt32(index)
        childPayload = Data([BYTE(0x60 + index)])
        grandchildTagId = 0x3E8 + UInt32(index)
        grandchildPayload = Data([BYTE(0x70 + index), BYTE(0x80 + index)])

        var data = commonShapeRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: controlPayload
        )
        data.append(commonShapeRecordData(tagId: childTagId, level: 2, payload: childPayload))
        data.append(commonShapeRecordData(
            tagId: grandchildTagId,
            level: 3,
            payload: grandchildPayload
        ))
        recordData = data
    }
}

private func commonShapeAssemblyStreams(
    fromFixture id: String
) throws -> CommonShapeAssemblyStreams {
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

    return CommonShapeAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectCommonShapeControls(
    in hwp: HwpFile,
    match injected: InjectedCommonShapeControls
) {
    let controls = hwp.sectionArray.flatMap(\.paragraph).flatMap {
        $0.ctrlHeaderArray ?? []
    }
    for shapeCase in injected.cases {
        let control = commonShapeControl(shapeCase.ctrlId, in: controls)
        expect(control?.ctrlId) == shapeCase.ctrlId
        expect(control?.commonCtrlProperty?.commonCtrlId) == shapeCase.ctrlId
        expect(control?.commonCtrlProperty?.rawPayload) == shapeCase.commonPayload
        expect(control?.rawPayload) == shapeCase.controlPayload
        expect(control?.rawTrailing) == shapeCase.rawTrailing
        expect(control?.shapeComponentArray).to(beEmpty())
        expect(control?.unknownChildren) == [
            commonShapeUnknownRecord(
                tagId: shapeCase.childTagId,
                level: 2,
                payload: shapeCase.childPayload,
                children: [
                    commonShapeUnknownRecord(
                        tagId: shapeCase.grandchildTagId,
                        level: 3,
                        payload: shapeCase.grandchildPayload
                    ),
                ]
            ),
        ]
    }
}

private func commonShapeControl(
    _ ctrlId: HwpCommonCtrlId,
    in controls: [HwpCtrlId]
) -> HwpShapeControl? {
    controls.compactMap { control in
        switch (ctrlId, control) {
        case let (.line, .line(shapeControl)),
             let (.ellipse, .ellipse(shapeControl)),
             let (.arc, .arc(shapeControl)),
             let (.polygon, .polygon(shapeControl)),
             let (.curve, .curve(shapeControl)),
             let (.ole, .ole(shapeControl)),
             let (.container, .container(shapeControl)):
            shapeControl
        default:
            nil
        }
    }.last
}

private func commonShapePropertyPayload(
    ctrlId: HwpCommonCtrlId,
    width: HWPUNIT,
    height: HWPUNIT,
    instanceId: UInt32
) -> Data {
    var data = Data()
    data.append(commonShapeLittleEndianData(ctrlId.rawValue))
    data.append(commonShapeLittleEndianData(UInt32(0x0102_0304)))
    data.append(commonShapeLittleEndianData(HWPUNIT(0x1111)))
    data.append(commonShapeLittleEndianData(HWPUNIT(0x2222)))
    data.append(commonShapeLittleEndianData(width))
    data.append(commonShapeLittleEndianData(height))
    data.append(commonShapeLittleEndianData(Int32(7)))
    data.append(commonShapeLittleEndianData(HWPUNIT16(1)))
    data.append(commonShapeLittleEndianData(HWPUNIT16(2)))
    data.append(commonShapeLittleEndianData(HWPUNIT16(3)))
    data.append(commonShapeLittleEndianData(HWPUNIT16(4)))
    data.append(commonShapeLittleEndianData(instanceId))
    data.append(commonShapeLittleEndianData(Int32(1)))
    data.append(commonShapeLittleEndianData(WORD(0)))
    return data
}

private func commonShapeRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = commonShapeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func commonShapeUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func commonShapeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
