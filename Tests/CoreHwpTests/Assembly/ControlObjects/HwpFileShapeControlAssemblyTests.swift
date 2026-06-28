@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileShapeControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesPictureAndEquationThroughCodableRoundTrip()
        throws
    {
        let streams = try shapeAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedShapeControls(
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

        expectPictureControl(in: hwp, match: injected.picture)
        expectPictureControl(in: decoded, match: injected.picture)
        expectEquationControl(in: hwp, match: injected.equation)
        expectEquationControl(in: decoded, match: injected.equation)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct ShapeAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedShapeControls {
    let sectionData: Data
    let picture: InjectedPictureShapeControl
    let equation: InjectedEquationShapeControl

    init(baseSectionData: Data) {
        picture = InjectedPictureShapeControl()
        equation = InjectedEquationShapeControl()
        sectionData = baseSectionData + picture.recordData + equation.recordData
    }
}

private struct InjectedPictureShapeControl {
    let recordData: Data
    let commonPayload: Data
    let controlPayload: Data
    let controlRawTrailing: Data
    let componentPayload: Data
    let componentRawTrailing: Data
    let picturePayload: Data
    let pictureRawTrailing: Data
    let pictureUnknownPayload: Data
    let componentUnknownPayload: Data
    let controlUnknownPayload: Data
    let controlUnknownGrandchildPayload: Data

    init() {
        commonPayload = shapeCommonCtrlPropertyPayload(
            ctrlId: .picture,
            width: 0x1111_2222,
            height: 0x3333_4444,
            instanceId: 0x5555_6666
        )
        controlRawTrailing = Data([0xCA, 0xFE])
        controlPayload = commonPayload + controlRawTrailing
        componentRawTrailing = Data([0xA1, 0xA2])
        componentPayload = shapeLittleEndianData(HwpCommonCtrlId.picture.rawValue)
            + componentRawTrailing
        pictureRawTrailing = Data([0xA3, 0xA4])
        picturePayload = Data(repeating: 0xAB, count: 71)
            + shapeLittleEndianData(UInt16(9))
            + pictureRawTrailing
        pictureUnknownPayload = Data([0xA5])
        componentUnknownPayload = Data([0xA6])
        controlUnknownPayload = Data([0xA7])
        controlUnknownGrandchildPayload = Data([0xA8])

        recordData = shapeRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: controlPayload
        )
            + shapeRecordData(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: componentPayload
            )
            + shapeRecordData(
                tagId: HwpSectionTag.shapeComponentPicture.rawValue,
                level: 3,
                payload: picturePayload
            )
            + shapeRecordData(tagId: 0x3B0, level: 4, payload: pictureUnknownPayload)
            + shapeRecordData(tagId: 0x3B1, level: 3, payload: componentUnknownPayload)
            + shapeRecordData(tagId: 0x3B2, level: 2, payload: controlUnknownPayload)
            + shapeRecordData(tagId: 0x3B3, level: 3, payload: controlUnknownGrandchildPayload)
    }
}

private struct InjectedEquationShapeControl {
    let recordData: Data
    let commonPayload: Data
    let controlPayload: Data
    let controlRawTrailing: Data
    let equationText: String
    let equationTextLengthRawPayload: Data
    let equationTextRawPayload: Data
    let eqEditPayload: Data
    let eqEditRawTrailing: Data
    let eqEditUnknownPayload: Data
    let controlUnknownPayload: Data

    init() {
        commonPayload = shapeCommonCtrlPropertyPayload(
            ctrlId: .equation,
            width: 0x0102_0304,
            height: 0x0506_0708,
            instanceId: 0x090A_0B0C
        )
        controlRawTrailing = Data([0xE1, 0xE2])
        controlPayload = commonPayload + controlRawTrailing
        equationText = "x=1"
        equationTextLengthRawPayload = Data([0x03, 0x00])
        equationTextRawPayload = Data([0x78, 0x00, 0x3D, 0x00, 0x31, 0x00])
        eqEditRawTrailing = Data([0xE3, 0xE4])
        eqEditPayload = shapeEquationEditPayload(text: equationText)
            + eqEditRawTrailing
        eqEditUnknownPayload = Data([0xE5])
        controlUnknownPayload = Data([0xE6])

        recordData = shapeRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: controlPayload
        )
            + shapeRecordData(
                tagId: HwpSectionTag.eqEdit.rawValue,
                level: 2,
                payload: eqEditPayload
            )
            + shapeRecordData(tagId: 0x3C0, level: 3, payload: eqEditUnknownPayload)
            + shapeRecordData(tagId: 0x3C1, level: 2, payload: controlUnknownPayload)
    }
}

private func shapeAssemblyStreams(fromFixture id: String) throws -> ShapeAssemblyStreams {
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

    return ShapeAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectPictureControl(
    in hwp: HwpFile,
    match injected: InjectedPictureShapeControl
) {
    let control = pictureControls(from: hwp).last

    expect(control?.ctrlId) == .picture
    expect(control?.commonCtrlProperty?.commonCtrlId) == .picture
    expect(control?.commonCtrlProperty?.rawPayload) == injected.commonPayload
    expect(control?.commonCtrlProperty?.width) == 0x1111_2222
    expect(control?.commonCtrlProperty?.height) == 0x3333_4444
    expect(control?.commonCtrlProperty?.instanceId) == 0x5555_6666
    expect(control?.rawPayload) == injected.controlPayload
    expect(control?.rawTrailing) == injected.controlRawTrailing
    expect(control?.shapeComponentArray.count) == 1
    expect(control?.unknownChildren) == [
        expectedShapeUnknownRecord(
            tagId: 0x3B2,
            level: 2,
            payload: injected.controlUnknownPayload,
            children: [
                expectedShapeUnknownRecord(
                    tagId: 0x3B3,
                    level: 3,
                    payload: injected.controlUnknownGrandchildPayload
                ),
            ]
        ),
    ]

    let component = control?.shapeComponentArray.first
    expect(component?.rawPayload) == injected.componentPayload
    expect(component?.rawCtrlId) == HwpCommonCtrlId.picture.rawValue
    expect(component?.ctrlId) == .picture
    expect(component?.rawTrailing) == injected.componentRawTrailing
    expect(component?.pictureArray.count) == 1
    expect(component?.unknownChildren) == [
        expectedShapeUnknownRecord(
            tagId: 0x3B1,
            level: 3,
            payload: injected.componentUnknownPayload
        ),
    ]

    let picture = component?.pictureArray.first
    expect(picture?.rawPayload) == injected.picturePayload
    expect(picture?.binaryDataId) == 9
    expect(picture?.rawTrailing) == injected.pictureRawTrailing
    expect(picture?.unknownChildren) == [
        expectedShapeUnknownRecord(
            tagId: 0x3B0,
            level: 4,
            payload: injected.pictureUnknownPayload
        ),
    ]
}

private func expectEquationControl(
    in hwp: HwpFile,
    match injected: InjectedEquationShapeControl
) {
    let control = equationControls(from: hwp).last

    expect(control?.ctrlId) == .equation
    expect(control?.commonCtrlProperty?.commonCtrlId) == .equation
    expect(control?.commonCtrlProperty?.rawPayload) == injected.commonPayload
    expect(control?.commonCtrlProperty?.width) == 0x0102_0304
    expect(control?.commonCtrlProperty?.height) == 0x0506_0708
    expect(control?.commonCtrlProperty?.instanceId) == 0x090A_0B0C
    expect(control?.rawPayload) == injected.controlPayload
    expect(control?.rawTrailing) == injected.controlRawTrailing
    expect(control?.eqEditArray.count) == 1
    expect(control?.eqEditRecords) == [
        expectedShapeUnknownRecord(
            tagId: HwpSectionTag.eqEdit.rawValue,
            level: 2,
            payload: injected.eqEditPayload,
            children: [
                expectedShapeUnknownRecord(
                    tagId: 0x3C0,
                    level: 3,
                    payload: injected.eqEditUnknownPayload
                ),
            ]
        ),
    ]
    expect(control?.unknownChildren) == [
        expectedShapeUnknownRecord(
            tagId: 0x3C1,
            level: 2,
            payload: injected.controlUnknownPayload
        ),
    ]

    let edit = control?.eqEditArray.first
    expect(edit?.rawPayload) == injected.eqEditPayload
    expect(edit?.equationTextLength) == UInt16(injected.equationText.utf16.count)
    expect(edit?.equationTextLengthRawPayload) == injected.equationTextLengthRawPayload
    expect(edit?.equationText) == injected.equationText
    expect(edit?.equationTextRawPayload) == injected.equationTextRawPayload
    expect(edit?.rawTrailing) == injected.eqEditRawTrailing
    expect(edit?.unknownChildren) == [
        expectedShapeUnknownRecord(
            tagId: 0x3C0,
            level: 3,
            payload: injected.eqEditUnknownPayload
        ),
    ]
}

private func pictureControls(from hwp: HwpFile) -> [HwpShapeControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .picture(shapeControl) = control else {
                return nil
            }
            return shapeControl
        }
    }
}

private func equationControls(from hwp: HwpFile) -> [HwpShapeControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .equation(shapeControl) = control else {
                return nil
            }
            return shapeControl
        }
    }
}

private func shapeCommonCtrlPropertyPayload(
    ctrlId: HwpCommonCtrlId,
    width: HWPUNIT,
    height: HWPUNIT,
    instanceId: UInt32
) -> Data {
    var data = Data()
    data.append(shapeLittleEndianData(ctrlId.rawValue))
    data.append(shapeLittleEndianData(UInt32(0x0102_0304)))
    data.append(shapeLittleEndianData(HWPUNIT(0x1111)))
    data.append(shapeLittleEndianData(HWPUNIT(0x2222)))
    data.append(shapeLittleEndianData(width))
    data.append(shapeLittleEndianData(height))
    data.append(shapeLittleEndianData(Int32(7)))
    data.append(shapeLittleEndianData(HWPUNIT16(1)))
    data.append(shapeLittleEndianData(HWPUNIT16(2)))
    data.append(shapeLittleEndianData(HWPUNIT16(3)))
    data.append(shapeLittleEndianData(HWPUNIT16(4)))
    data.append(shapeLittleEndianData(instanceId))
    data.append(shapeLittleEndianData(Int32(1)))
    data.append(shapeLittleEndianData(WORD(0)))
    return data
}

private func shapeEquationEditPayload(text: String) -> Data {
    var data = Data([0, 0, 0, 0])
    data.append(shapeLittleEndianData(UInt16(text.utf16.count)))
    for codeUnit in text.utf16 {
        data.append(shapeLittleEndianData(WCHAR(codeUnit)))
    }
    return data
}

private func shapeRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = shapeLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func expectedShapeUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func shapeLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
