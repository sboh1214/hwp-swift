@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileRawOtherAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesRawOtherControlsThroughCodableRoundTrip()
        throws
    {
        let streams = try rawOtherAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedRawOtherControls(
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

        for spec in injected.specs {
            expectRawOtherControl(in: hwp, match: spec)
            expectRawOtherControl(in: decoded, match: spec)
        }
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct RawOtherAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedRawOtherControls {
    let sectionData: Data
    let specs: [InjectedRawOtherControl]

    init(baseSectionData: Data) {
        specs = [
            InjectedRawOtherControl(ctrlId: .pageCT, index: 0),
            InjectedRawOtherControl(ctrlId: .overlapping, index: 1),
            InjectedRawOtherControl(ctrlId: .comment, index: 2),
            InjectedRawOtherControl(ctrlId: .hiddenComment, index: 3),
            InjectedRawOtherControl(ctrlId: .form, index: 4),
        ]
        sectionData = specs.reduce(into: baseSectionData) { data, spec in
            data.append(spec.recordData)
        }
    }
}

private struct InjectedRawOtherControl {
    let ctrlId: HwpOtherCtrlId
    let recordData: Data
    let payload: Data
    let rawTrailing: Data
    let unknownPayload: Data
    let grandchildPayload: Data
    let unknownTagId: UInt32
    let grandchildTagId: UInt32

    init(ctrlId: HwpOtherCtrlId, index: UInt8) {
        self.ctrlId = ctrlId
        rawTrailing = Data([0xA0 + index, 0xB0 + index])
        payload = concatenatedData(
            rawOtherLittleEndianData(ctrlId.rawValue),
            rawTrailing
        )
        unknownPayload = Data([0xC0 + index])
        grandchildPayload = Data([0xD0 + index])
        unknownTagId = 0x370 + UInt32(index)
        grandchildTagId = 0x380 + UInt32(index)

        recordData = concatenatedData(
            rawOtherRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: payload
            ),
            rawOtherRecordData(tagId: unknownTagId, level: 2, payload: unknownPayload),
            rawOtherRecordData(tagId: grandchildTagId, level: 3, payload: grandchildPayload)
        )
    }
}

private func rawOtherAssemblyStreams(fromFixture id: String) throws -> RawOtherAssemblyStreams {
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

    return RawOtherAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectRawOtherControl(
    in hwp: HwpFile,
    match spec: InjectedRawOtherControl
) {
    let control = rawOtherControl(spec.ctrlId, in: hwp)

    expect(control?.ctrlId) == spec.ctrlId
    expect(control?.rawPayload) == spec.payload
    expect(control?.rawTrailing) == spec.rawTrailing
    expect(control?.numberingInfo).to(beNil())
    expect(control?.pageHideInfo).to(beNil())
    expect(control?.indexmarkInfo).to(beNil())
    expect(control?.bookmarkInfo).to(beNil())
    expect(control?.ctrlDataRecords).to(beEmpty())
    expect(control?.unknownChildren) == [
        expectedRawOtherUnknownRecord(
            tagId: spec.unknownTagId,
            level: 2,
            payload: spec.unknownPayload,
            children: [
                expectedRawOtherUnknownRecord(
                    tagId: spec.grandchildTagId,
                    level: 3,
                    payload: spec.grandchildPayload
                ),
            ]
        ),
    ]
}

private func rawOtherControl(_ ctrlId: HwpOtherCtrlId, in hwp: HwpFile) -> HwpOtherControl? {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control -> HwpOtherControl? in
            switch (ctrlId, control) {
            case let (.pageCT, .pageCT(other)),
                 let (.overlapping, .overlapping(other)),
                 let (.comment, .comment(other)),
                 let (.hiddenComment, .hiddenComment(other)),
                 let (.form, .form(other)):
                return other
            default:
                return nil
            }
        }
    }.last
}

private func rawOtherRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = rawOtherLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func expectedRawOtherUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpUnknownRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(tagId: tagId, level: level, payload: payload, children: children)
}

private func rawOtherLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
