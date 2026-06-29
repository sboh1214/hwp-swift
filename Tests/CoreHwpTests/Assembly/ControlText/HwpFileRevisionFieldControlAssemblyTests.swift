@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileRevisionFieldControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyClassifiesRevisionFieldThroughCodableRoundTrip()
        throws
    {
        let streams = try revisionFieldAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedRevisionFieldControl(
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

        expectRevisionFieldControl(in: hwp, match: injected)
        expectRevisionFieldControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct RevisionFieldAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedRevisionFieldControl {
    let sectionData: Data
    let ctrlId: HwpFieldCtrlId
    let revisionPayload: Data
    let revisionChildPayload: Data
    let revisionGrandchildPayload: Data
    let rawTrailing: Data

    init(baseSectionData: Data) {
        ctrlId = .revisionDelete
        rawTrailing = Data([0xA1, 0xA2, 0xA3])
        revisionPayload = concatenatedData(
            revisionFieldLittleEndianData(ctrlId.rawValue),
            rawTrailing
        )
        revisionChildPayload = Data([0xB0, 0xB1])
        revisionGrandchildPayload = Data([0xB2])

        sectionData = concatenatedData(
            baseSectionData,
            revisionFieldRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: revisionPayload
            ),
            revisionFieldRecordData(
                tagId: 0x2F8,
                level: 2,
                payload: revisionChildPayload
            ),
            revisionFieldRecordData(
                tagId: 0x2F7,
                level: 3,
                payload: revisionGrandchildPayload
            )
        )
    }
}

private func revisionFieldAssemblyStreams(
    fromFixture id: String
) throws -> RevisionFieldAssemblyStreams {
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

    return RevisionFieldAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectRevisionFieldControl(
    in hwp: HwpFile,
    match injected: InjectedRevisionFieldControl
) {
    let revision = revisionControls(from: hwp).last

    expect(revision?.ctrlId) == injected.ctrlId
    expect(revision?.semanticKind) == .revision
    expect(revision?.isMemoField) == false
    expect(revision?.isRevisionField) == true
    expect(revision?.rawPayload) == injected.revisionPayload
    expect(revision?.rawTrailing) == injected.rawTrailing
    expect(revision?.fieldParameter).to(beNil())
    expect(revision?.fieldParameterRawPayload).to(beNil())
    expect(revision?.fieldParameterRawTrailing).to(beNil())
    expect(revision?.memoParameter).to(beNil())
    expect(revision?.unknownChildren ?? []) == [
        revisionExpectedUnknownRecord(
            tagId: 0x2F8,
            level: 2,
            payload: injected.revisionChildPayload,
            children: [
                revisionExpectedRecord(
                    tagId: 0x2F7,
                    level: 3,
                    payload: injected.revisionGrandchildPayload
                ),
            ]
        ),
    ]
}

private func revisionControls(from hwp: HwpFile) -> [HwpFieldControl] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .revision(field) = control else {
                return nil
            }
            return field
        }
    }
}

private func revisionFieldRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = revisionFieldLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func revisionExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        revisionExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func revisionExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func revisionFieldLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
