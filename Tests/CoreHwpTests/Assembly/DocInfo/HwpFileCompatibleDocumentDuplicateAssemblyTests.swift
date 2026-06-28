@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class CompatibleDocDuplicateAssemblyTests: XCTestCase {
    func testActualFixtureBasedDuplicateCompatibleDocumentSurvivesAsUnknownThroughCodable()
        throws
    {
        let streams = try compatibleDocumentStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.compatibleDocument).notTo(beNil())

        let injected = DuplicateCompatibleDocumentFixture(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectCompatibleDocumentDuplicate(
            in: hwp.docInfo,
            baseDocInfo: baseDocInfo,
            matches: injected
        )
        expectCompatibleDocumentDuplicate(
            in: decoded.docInfo,
            baseDocInfo: baseDocInfo,
            matches: injected
        )
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }
}

private struct CompatibleDocumentStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct DuplicateCompatibleDocumentFixture {
    let docInfoData: Data
    let firstPayload: Data
    let firstLayoutPayload: Data
    let firstUnknownPayload: Data
    let firstUnknownGrandchildPayload: Data
    let duplicatePayload: Data
    let duplicateChildPayload: Data

    init(baseDocInfoData: Data) {
        firstPayload = compatibleDocumentLittleEndianData(UInt32(1))
        firstLayoutPayload = compatibleDocumentLayoutPayload(11, 12, 13, 14, 15)
        firstUnknownPayload = Data([0xC1, 0xC2])
        firstUnknownGrandchildPayload = Data([0xC3])
        duplicatePayload = compatibleDocumentLittleEndianData(UInt32(2))
        duplicateChildPayload = Data([0xC4, 0xC5])
        docInfoData = baseDocInfoData
            + compatibleDocumentRecordData(.compatibleDocument, payload: firstPayload)
            + compatibleDocumentRecordData(
                .layoutCompatibility,
                level: 1,
                payload: firstLayoutPayload
            )
            + compatibleDocumentRecordData(tagId: 0x31D, level: 1, payload: firstUnknownPayload)
            + compatibleDocumentRecordData(
                tagId: 0x31E,
                level: 2,
                payload: firstUnknownGrandchildPayload
            )
            + compatibleDocumentRecordData(.compatibleDocument, payload: duplicatePayload)
            + compatibleDocumentRecordData(tagId: 0x31F, level: 1, payload: duplicateChildPayload)
    }
}

private func compatibleDocumentStreams(
    fromFixture id: String
) throws -> CompatibleDocumentStreams {
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

    return CompatibleDocumentStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectCompatibleDocumentDuplicate(
    in docInfo: HwpDocInfo,
    baseDocInfo: HwpDocInfo,
    matches injected: DuplicateCompatibleDocumentFixture
) {
    expect(docInfo.compatibleDocument?.rawPayload) ==
        baseDocInfo.compatibleDocument?.rawPayload
    expect(docInfo.compatibleDocument?.targetDocumentRawPayload) ==
        baseDocInfo.compatibleDocument?.targetDocumentRawPayload
    expect(docInfo.compatibleDocument?.targetDocument) ==
        baseDocInfo.compatibleDocument?.targetDocument
    expect(docInfo.compatibleDocument?.layoutCompatibility?.rawPayload) ==
        baseDocInfo.compatibleDocument?.layoutCompatibility?.rawPayload
    expect(docInfo.compatibleDocument?.trackChangeArray.map(\.rawPayload)) ==
        baseDocInfo.compatibleDocument?.trackChangeArray.map(\.rawPayload)
    expect(docInfo.compatibleDocument?.unknownChildren) ==
        baseDocInfo.compatibleDocument?.unknownChildren
    expect(Array(docInfo.unknownRecords.suffix(2))) ==
        expectedDuplicateCompatibleDocumentUnknownRecords(injected)
}

private func expectedDuplicateCompatibleDocumentUnknownRecords(
    _ injected: DuplicateCompatibleDocumentFixture
) -> [HwpUnknownRecord] {
    [
        expectedTestUnknownRecord(
            tagId: HwpDocInfoTag.compatibleDocument.rawValue,
            level: 0,
            payload: injected.firstPayload,
            children: [
                expectedTestRecord(
                    tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
                    level: 1,
                    payload: injected.firstLayoutPayload
                ),
                expectedTestRecord(
                    tagId: 0x31D,
                    level: 1,
                    payload: injected.firstUnknownPayload,
                    children: [
                        expectedTestRecord(
                            tagId: 0x31E,
                            level: 2,
                            payload: injected.firstUnknownGrandchildPayload
                        ),
                    ]
                ),
            ]
        ),
        expectedTestUnknownRecord(
            tagId: HwpDocInfoTag.compatibleDocument.rawValue,
            level: 0,
            payload: injected.duplicatePayload,
            children: [
                expectedTestRecord(
                    tagId: 0x31F,
                    level: 1,
                    payload: injected.duplicateChildPayload
                ),
            ]
        ),
    ]
}

private func compatibleDocumentLayoutPayload(_ values: UInt32...) -> Data {
    values.reduce(into: Data()) { data, value in
        data.append(compatibleDocumentLittleEndianData(value))
    }
}

private func compatibleDocumentRecordData(_ tag: HwpDocInfoTag, payload: Data) -> Data {
    compatibleDocumentRecordData(tagId: tag.rawValue, level: 0, payload: payload)
}

private func compatibleDocumentRecordData(
    _ tag: HwpDocInfoTag,
    level: UInt32,
    payload: Data
) -> Data {
    compatibleDocumentRecordData(tagId: tag.rawValue, level: level, payload: payload)
}

private func compatibleDocumentRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = compatibleDocumentLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func compatibleDocumentLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
