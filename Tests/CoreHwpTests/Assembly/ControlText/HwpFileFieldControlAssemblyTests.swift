@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileFieldControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyClassifiesGenericFieldThroughCodableRoundTrip()
        throws
    {
        let streams = try fieldControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedGenericFieldControl(
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

        expectGenericFieldControl(in: hwp, match: injected)
        expectGenericFieldControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyClassifiesMemoFieldThroughCodableRoundTrip()
        throws
    {
        let streams = try fieldControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedMemoFieldControl(
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

        expectMemoFieldControl(in: hwp, match: injected)
        expectMemoFieldControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct FieldControlAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedGenericFieldControl {
    let sectionData: Data
    let ctrlId: HwpFieldCtrlId
    let parameter: String
    let fieldPayload: Data
    let parameterPayload: Data
    let fieldRawTrailing: Data
    let parameterRawTrailing: Data
    let fieldChildPayload: Data
    let fieldGrandchildPayload: Data

    init(baseSectionData: Data) {
        ctrlId = .date
        parameter = "CoreHwp field parameter"
        parameterPayload = fieldControlUTF16Payload(parameter)
        parameterRawTrailing = Data([0xCA, 0xFE])
        fieldRawTrailing = fieldControlParameterTrailing(parameter)
            + parameterRawTrailing
        fieldPayload = fieldControlLittleEndianData(ctrlId.rawValue)
            + fieldRawTrailing
        fieldChildPayload = Data([0xD0, 0xD1])
        fieldGrandchildPayload = Data([0xD2])

        sectionData = baseSectionData
            + fieldControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: fieldPayload
            )
            + fieldControlRecordData(
                tagId: 0x2F6,
                level: 2,
                payload: fieldChildPayload
            )
            + fieldControlRecordData(
                tagId: 0x2F5,
                level: 3,
                payload: fieldGrandchildPayload
            )
    }
}

private struct InjectedMemoFieldControl {
    let sectionData: Data
    let ctrlId: HwpFieldCtrlId
    let parameter: String
    let fieldPayload: Data
    let parameterPayload: Data
    let fieldRawTrailing: Data
    let parameterRawTrailing: Data
    let fieldChildPayload: Data
    let fieldGrandchildPayload: Data

    init(baseSectionData: Data) {
        ctrlId = .unknown
        parameter = "MEMO/1/2/3/4/writer/body"
        parameterPayload = fieldControlUTF16Payload(parameter)
        parameterRawTrailing = Data([0xB3, 0xB4])
        fieldRawTrailing = fieldControlParameterTrailing(parameter)
            + parameterRawTrailing
        fieldPayload = fieldControlLittleEndianData(ctrlId.rawValue)
            + fieldRawTrailing
        fieldChildPayload = Data([0xE0, 0xE1])
        fieldGrandchildPayload = Data([0xE2])

        sectionData = baseSectionData
            + fieldControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: fieldPayload
            )
            + fieldControlRecordData(
                tagId: 0x2F4,
                level: 2,
                payload: fieldChildPayload
            )
            + fieldControlRecordData(
                tagId: 0x2F3,
                level: 3,
                payload: fieldGrandchildPayload
            )
    }
}

private func fieldControlAssemblyStreams(
    fromFixture id: String
) throws -> FieldControlAssemblyStreams {
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

    return FieldControlAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectGenericFieldControl(
    in hwp: HwpFile,
    match injected: InjectedGenericFieldControl
) {
    let field = genericFieldControls(from: hwp).last

    expect(field?.ctrlId) == injected.ctrlId
    expect(field?.semanticKind) == .field
    expect(field?.isMemoField) == false
    expect(field?.isRevisionField) == false
    expect(field?.rawPayload) == injected.fieldPayload
    expect(field?.rawTrailing) == injected.fieldRawTrailing
    expect(field?.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
    expect(field?.fieldParameterCharacterCount) == injected.parameter.utf16.count
    expect(field?.fieldParameterLengthRawPayload) ==
        fieldControlLittleEndianData(WORD(injected.parameter.utf16.count))
    expect(field?.fieldParameter) == injected.parameter
    expect(field?.fieldParameterRawPayload) == injected.parameterPayload
    expect(field?.fieldParameterRawTrailing) == injected.parameterRawTrailing
    expect(field?.memoParameter).to(beNil())
    expect(field?.unknownChildren ?? []) == [
        fieldControlExpectedUnknownRecord(
            tagId: 0x2F6,
            level: 2,
            payload: injected.fieldChildPayload,
            children: [
                fieldControlExpectedRecord(
                    tagId: 0x2F5,
                    level: 3,
                    payload: injected.fieldGrandchildPayload
                ),
            ]
        ),
    ]
}

private func expectMemoFieldControl(
    in hwp: HwpFile,
    match injected: InjectedMemoFieldControl
) {
    let memo = memoFieldControls(from: hwp).last

    expect(memo?.ctrlId) == injected.ctrlId
    expect(memo?.semanticKind) == .memo
    expect(memo?.isMemoField) == true
    expect(memo?.isRevisionField) == false
    expect(memo?.rawPayload) == injected.fieldPayload
    expect(memo?.rawTrailing) == injected.fieldRawTrailing
    expect(memo?.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
    expect(memo?.fieldParameterCharacterCount) == injected.parameter.utf16.count
    expect(memo?.fieldParameterLengthRawPayload) ==
        fieldControlLittleEndianData(WORD(injected.parameter.utf16.count))
    expect(memo?.fieldParameter) == injected.parameter
    expect(memo?.fieldParameterRawPayload) == injected.parameterPayload
    expect(memo?.fieldParameterRawTrailing) == injected.parameterRawTrailing
    expect(memo?.memoParameter?.rawValue) == injected.parameter
    expect(memo?.memoParameter?.rawPayload) == injected.parameterPayload
    expect(memo?.memoParameter?.components) == [
        "MEMO", "1", "2", "3", "4", "writer", "body",
    ]
    expect(memo?.memoParameter?.fields) == ["1", "2", "3", "4", "writer", "body"]
    expect(memo?.memoParameter?.author) == "writer"
    expect(memo?.memoParameter?.rawTrailing) == injected.parameterRawTrailing
    expect(memo?.unknownChildren ?? []) == [
        fieldControlExpectedUnknownRecord(
            tagId: 0x2F4,
            level: 2,
            payload: injected.fieldChildPayload,
            children: [
                fieldControlExpectedRecord(
                    tagId: 0x2F3,
                    level: 3,
                    payload: injected.fieldGrandchildPayload
                ),
            ]
        ),
    ]
}

private func genericFieldControls(from hwp: HwpFile) -> [HwpFieldControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .field(field) = control else {
                return nil
            }
            return field
        }
    }
}

private func memoFieldControls(from hwp: HwpFile) -> [HwpFieldControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .memo(field) = control else {
                return nil
            }
            return field
        }
    }
}

private func fieldControlRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = fieldControlLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func fieldControlExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        fieldControlExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func fieldControlExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func fieldControlParameterTrailing(_ parameter: String) -> Data {
    var data = fieldControlLittleEndianData(UInt32(0x8001))
    data.append(fieldControlLittleEndianData(WORD(parameter.utf16.count)))
    data.append(fieldControlUTF16Payload(parameter))
    return data
}

private func fieldControlUTF16Payload(_ string: String) -> Data {
    string.utf16.reduce(into: Data()) { data, codeUnit in
        data.append(fieldControlLittleEndianData(WCHAR(codeUnit)))
    }
}

private func fieldControlLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
