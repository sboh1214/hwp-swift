@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileShapeControlFallbackAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesMalformedShapeControlsAsNotImplemented()
        throws
    {
        let streams = try shapeFallbackAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedShapeControlFallbacks(
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

        expectShapeControlFallbacks(in: hwp, match: injected)
        expectShapeControlFallbacks(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct ShapeFallbackAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedShapeControlFallbacks {
    let sectionData: Data
    let genShapePayload: Data
    let genShapeComponentPayload: Data
    let genShapeListHeaderPayload: Data
    let picturePayload: Data
    let pictureComponentPayload: Data
    let pictureListHeaderPayload: Data

    init(baseSectionData: Data) {
        genShapePayload = shapeFallbackCommonShapeControlPayload(
            ctrlId: HwpCommonCtrlId.genShapeObject.rawValue
        )
        genShapeComponentPayload = shapeFallbackLittleEndianData(
            HwpCommonCtrlId.rectangle.rawValue
        )
        genShapeListHeaderPayload = shapeFallbackListHeaderPayload(paragraphCount: 1)
        picturePayload = shapeFallbackCommonShapeControlPayload(
            ctrlId: HwpCommonCtrlId.picture.rawValue
        )
        pictureComponentPayload = shapeFallbackLittleEndianData(
            HwpCommonCtrlId.rectangle.rawValue
        )
        pictureListHeaderPayload = shapeFallbackListHeaderPayload(paragraphCount: 1)

        sectionData = concatenatedData(
            baseSectionData,
            shapeFallbackMalformedShapeControlRecordData(
                ctrlPayload: genShapePayload,
                componentPayload: genShapeComponentPayload,
                listHeaderPayload: genShapeListHeaderPayload
            ),
            shapeFallbackMalformedShapeControlRecordData(
                ctrlPayload: picturePayload,
                componentPayload: pictureComponentPayload,
                listHeaderPayload: pictureListHeaderPayload
            )
        )
    }
}

private func shapeFallbackAssemblyStreams(
    fromFixture id: String
) throws -> ShapeFallbackAssemblyStreams {
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

    return ShapeFallbackAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectShapeControlFallbacks(
    in hwp: HwpFile,
    match injected: InjectedShapeControlFallbacks
) {
    let controls = Array(FixtureDerivedValues.preservedControls(from: hwp).suffix(2))

    expect(controls.map(\.kind)) == ["notImplemented", "notImplemented"]
    expect(controls.map(\.header.ctrlId)) == [
        HwpCommonCtrlId.genShapeObject.rawValue,
        HwpCommonCtrlId.picture.rawValue,
    ]
    expect(controls.map(\.header.rawPayload)) == [
        injected.genShapePayload,
        injected.picturePayload,
    ]
    expect(controls.map(\.header.unknownChildren)) == [
        [
            shapeFallbackExpectedUnknownRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: injected.genShapeComponentPayload,
                children: [
                    shapeFallbackExpectedRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: injected.genShapeListHeaderPayload
                    ),
                ]
            ),
        ],
        [
            shapeFallbackExpectedUnknownRecord(
                tagId: HwpSectionTag.shapeComponent.rawValue,
                level: 2,
                payload: injected.pictureComponentPayload,
                children: [
                    shapeFallbackExpectedRecord(
                        tagId: HwpSectionTag.listHeader.rawValue,
                        level: 3,
                        payload: injected.pictureListHeaderPayload
                    ),
                ]
            ),
        ],
    ]
}

private func shapeFallbackMalformedShapeControlRecordData(
    ctrlPayload: Data,
    componentPayload: Data,
    listHeaderPayload: Data
) -> Data {
    concatenatedData(
        shapeFallbackRecordData(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: ctrlPayload
        ),
        shapeFallbackRecordData(
            tagId: HwpSectionTag.shapeComponent.rawValue,
            level: 2,
            payload: componentPayload
        ),
        shapeFallbackRecordData(
            tagId: HwpSectionTag.listHeader.rawValue,
            level: 3,
            payload: listHeaderPayload
        )
    )
}

private func shapeFallbackRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = shapeFallbackLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func shapeFallbackExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        shapeFallbackExpectedRecord(
            tagId: tagId,
            level: level,
            payload: payload,
            children: children
        )
    )
}

private func shapeFallbackExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func shapeFallbackCommonShapeControlPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(shapeFallbackLittleEndianData(ctrlId))
    data.append(shapeFallbackLittleEndianData(UInt32(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT(0)))
    data.append(shapeFallbackLittleEndianData(Int32(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(shapeFallbackLittleEndianData(HWPUNIT16(0)))
    data.append(shapeFallbackLittleEndianData(UInt32(0)))
    data.append(shapeFallbackLittleEndianData(Int32(0)))
    data.append(shapeFallbackLittleEndianData(WORD(0)))
    return data
}

private func shapeFallbackListHeaderPayload(paragraphCount: Int32) -> Data {
    concatenatedData(
        shapeFallbackLittleEndianData(paragraphCount),
        shapeFallbackLittleEndianData(UInt32(0))
    )
}

private func shapeFallbackLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
