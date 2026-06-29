@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileDocInfoDuplicateAssemblyTests: XCTestCase {
    func testActualFixtureBasedDuplicateSingletonDocInfoRecordSurvivesAsUnknownThroughCodable()
        throws
    {
        let streams = try duplicateDocInfoActualStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.docData).to(beNil())

        let injected = DuplicateDocInfoSingletonInjection(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectDuplicateDocDataRecords(in: hwp.docInfo, match: injected)
        expectDuplicateDocDataRecords(in: decoded.docInfo, match: injected)
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }

    func testActualFixtureBasedDuplicateDistributeDocDataSurvivesAsUnknownThroughCodable()
        throws
    {
        let streams = try duplicateDocInfoActualStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.distributeDocData).to(beNil())

        let injected = DuplicateDistributeDocDataInjection(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectDuplicateDistributeDocDataRecords(in: hwp.docInfo, match: injected)
        expectDuplicateDistributeDocDataRecords(in: decoded.docInfo, match: injected)
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }

    func testActualFixtureBasedDuplicateLayoutCompatibilitySurvivesAsUnknownThroughCodable()
        throws
    {
        let streams = try duplicateDocInfoActualStreams(fromFixture: "plain-text-minimal")

        let injected = DuplicateLayoutCompatibilityInjection(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectDuplicateLayoutCompatibilityRecords(in: hwp.docInfo, match: injected)
        expectDuplicateLayoutCompatibilityRecords(in: decoded.docInfo, match: injected)
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }

    func testActualFixtureBasedDuplicateRequiredSingletonRecordsSurviveAsUnknownThroughCodable()
        throws
    {
        let streams = try duplicateDocInfoActualStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        let injected = DuplicateRequiredDocInfoInjection(
            baseDocInfoData: streams.docInfoData
        )

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectDuplicateRequiredDocInfoRecords(
            in: hwp.docInfo,
            baseDocInfo: baseDocInfo,
            match: injected
        )
        expectDuplicateRequiredDocInfoRecords(
            in: decoded.docInfo,
            baseDocInfo: baseDocInfo,
            match: injected
        )
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }
}

private struct DuplicateDocInfoActualStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct DuplicateDocInfoSingletonInjection {
    let docInfoData: Data
    let firstDocDataPayload: Data
    let firstDocDataChildPayload: Data
    let duplicateDocDataPayload: Data
    let duplicateDocDataChildPayload: Data

    init(baseDocInfoData: Data) {
        firstDocDataPayload = Data([0xD0, 0xC1])
        firstDocDataChildPayload = Data([0xF1])
        duplicateDocDataPayload = Data([0xD0, 0xC2, 0xD2])
        duplicateDocDataChildPayload = Data([0xF2, 0xF3])
        docInfoData = concatenatedData(
            baseDocInfoData,
            duplicateDocInfoRecordData(.docData, payload: firstDocDataPayload),
            duplicateDocInfoRecordData(
                tagId: 0x315,
                level: 1,
                payload: firstDocDataChildPayload
            ),
            duplicateDocInfoRecordData(.docData, payload: duplicateDocDataPayload),
            duplicateDocInfoRecordData(
                tagId: 0x316,
                level: 1,
                payload: duplicateDocDataChildPayload
            )
        )
    }
}

private struct DuplicateDistributeDocDataInjection {
    let docInfoData: Data
    let firstPayload: Data
    let firstChildPayload: Data
    let duplicatePayload: Data
    let duplicateChildPayload: Data

    init(baseDocInfoData: Data) {
        firstPayload = Data([0xD1, 0x57, 0x00, 0x01])
        firstChildPayload = Data([0xE1])
        duplicatePayload = Data([0xD2, 0x57, 0x00, 0x01, 0x99])
        duplicateChildPayload = Data([0xE2, 0xE3])
        docInfoData = concatenatedData(
            baseDocInfoData,
            duplicateDocInfoRecordData(.distributeDocData, payload: firstPayload),
            duplicateDocInfoRecordData(
                tagId: 0x317,
                level: 1,
                payload: firstChildPayload
            ),
            duplicateDocInfoRecordData(.distributeDocData, payload: duplicatePayload),
            duplicateDocInfoRecordData(
                tagId: 0x318,
                level: 1,
                payload: duplicateChildPayload
            )
        )
    }
}

private struct DuplicateLayoutCompatibilityInjection {
    let docInfoData: Data
    let firstPayload: Data
    let firstChildPayload: Data
    let duplicatePayload: Data
    let duplicateChildPayload: Data

    init(baseDocInfoData: Data) {
        firstPayload = duplicateDocInfoLayoutPayload(1, 2, 3, 4, 5)
        firstChildPayload = Data([0xE4])
        duplicatePayload = duplicateDocInfoLayoutPayload(6, 7, 8, 9, 10)
        duplicateChildPayload = Data([0xE5, 0xE6])
        docInfoData = concatenatedData(
            baseDocInfoData,
            duplicateDocInfoRecordData(.layoutCompatibility, payload: firstPayload),
            duplicateDocInfoRecordData(
                tagId: 0x319,
                level: 1,
                payload: firstChildPayload
            ),
            duplicateDocInfoRecordData(.layoutCompatibility, payload: duplicatePayload),
            duplicateDocInfoRecordData(
                tagId: 0x31A,
                level: 1,
                payload: duplicateChildPayload
            )
        )
    }
}

private struct DuplicateRequiredDocInfoInjection {
    let docInfoData: Data
    let documentPropertiesPayload: Data
    let documentPropertiesChildPayload: Data
    let idMappingsPayload: Data
    let idMappingsChildPayload: Data

    init(baseDocInfoData: Data) {
        documentPropertiesPayload = concatenatedData(
            duplicateDocInfoLittleEndianData(UInt16(7)),
            Data(repeating: 0xD0, count: 24)
        )
        documentPropertiesChildPayload = Data([0xD1, 0xD2])
        idMappingsPayload = Data([0xE0, 0xE1, 0xE2])
        idMappingsChildPayload = Data([0xE3])
        docInfoData = concatenatedData(
            baseDocInfoData,
            duplicateDocInfoRecordData(
                .documentProperties,
                payload: documentPropertiesPayload
            ),
            duplicateDocInfoRecordData(
                tagId: 0x31B,
                level: 1,
                payload: documentPropertiesChildPayload
            ),
            duplicateDocInfoRecordData(.idMappings, payload: idMappingsPayload),
            duplicateDocInfoRecordData(
                tagId: 0x31C,
                level: 1,
                payload: idMappingsChildPayload
            )
        )
    }
}

private func duplicateDocInfoActualStreams(
    fromFixture id: String
) throws -> DuplicateDocInfoActualStreams {
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

    return DuplicateDocInfoActualStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectDuplicateDocDataRecords(
    in docInfo: HwpDocInfo,
    match injected: DuplicateDocInfoSingletonInjection
) {
    expect(docInfo.docData?.rawPayload) == injected.firstDocDataPayload
    expect(docInfo.docData?.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x315,
            level: 1,
            payload: injected.firstDocDataChildPayload
        ),
    ]
    expect(docInfo.unknownRecords.last) == expectedDuplicateDocDataUnknownRecord(injected)
}

private func expectDuplicateDistributeDocDataRecords(
    in docInfo: HwpDocInfo,
    match injected: DuplicateDistributeDocDataInjection
) {
    expect(docInfo.distributeDocData?.rawPayload) == injected.firstPayload
    expect(docInfo.distributeDocData?.distributeDocDataInfo?.values) == [0x0100_57D1]
    expect(docInfo.distributeDocData?.distributeDocDataInfo?.valuesRawPayload) ==
        injected.firstPayload
    expect(docInfo.distributeDocData?.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x317,
            level: 1,
            payload: injected.firstChildPayload
        ),
    ]
    expect(docInfo.unknownRecords.last) == expectedDuplicateDistributeDocDataUnknownRecord(
        injected
    )
}

private func expectDuplicateLayoutCompatibilityRecords(
    in docInfo: HwpDocInfo,
    match injected: DuplicateLayoutCompatibilityInjection
) {
    expect(docInfo.layoutCompatibility?.rawPayload) == injected.firstPayload
    expect(docInfo.layoutCompatibility?.fixedFieldsRawPayload) == injected.firstPayload
    expect(docInfo.layoutCompatibility?.char) == 1
    expect(docInfo.layoutCompatibility?.paragraph) == 2
    expect(docInfo.layoutCompatibility?.section) == 3
    expect(docInfo.layoutCompatibility?.object) == 4
    expect(docInfo.layoutCompatibility?.field) == 5
    expect(docInfo.layoutCompatibility?.unknownChildren) == [
        expectedTestUnknownRecord(
            tagId: 0x319,
            level: 1,
            payload: injected.firstChildPayload
        ),
    ]
    expect(docInfo.unknownRecords.last) == expectedDuplicateLayoutCompatibilityUnknownRecord(
        injected
    )
}

private func expectDuplicateRequiredDocInfoRecords(
    in docInfo: HwpDocInfo,
    baseDocInfo: HwpDocInfo,
    match injected: DuplicateRequiredDocInfoInjection
) {
    expect(docInfo.documentProperties.rawPayload) == baseDocInfo.documentProperties.rawPayload
    expect(docInfo.idMappings) == baseDocInfo.idMappings
    expect(Array(docInfo.unknownRecords.suffix(2))) == [
        expectedTestUnknownRecord(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: injected.documentPropertiesPayload,
            children: [
                expectedTestRecord(
                    tagId: 0x31B,
                    level: 1,
                    payload: injected.documentPropertiesChildPayload
                ),
            ]
        ),
        expectedTestUnknownRecord(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: injected.idMappingsPayload,
            children: [
                expectedTestRecord(
                    tagId: 0x31C,
                    level: 1,
                    payload: injected.idMappingsChildPayload
                ),
            ]
        ),
    ]
}

private func expectedDuplicateDocDataUnknownRecord(
    _ injected: DuplicateDocInfoSingletonInjection
) -> HwpUnknownRecord {
    expectedTestUnknownRecord(
        tagId: HwpDocInfoTag.docData.rawValue,
        level: 0,
        payload: injected.duplicateDocDataPayload,
        children: [
            expectedTestRecord(
                tagId: 0x316,
                level: 1,
                payload: injected.duplicateDocDataChildPayload
            ),
        ]
    )
}

private func expectedDuplicateDistributeDocDataUnknownRecord(
    _ injected: DuplicateDistributeDocDataInjection
) -> HwpUnknownRecord {
    expectedTestUnknownRecord(
        tagId: HwpDocInfoTag.distributeDocData.rawValue,
        level: 0,
        payload: injected.duplicatePayload,
        children: [
            expectedTestRecord(
                tagId: 0x318,
                level: 1,
                payload: injected.duplicateChildPayload
            ),
        ]
    )
}

private func expectedDuplicateLayoutCompatibilityUnknownRecord(
    _ injected: DuplicateLayoutCompatibilityInjection
) -> HwpUnknownRecord {
    expectedTestUnknownRecord(
        tagId: HwpDocInfoTag.layoutCompatibility.rawValue,
        level: 0,
        payload: injected.duplicatePayload,
        children: [
            expectedTestRecord(
                tagId: 0x31A,
                level: 1,
                payload: injected.duplicateChildPayload
            ),
        ]
    )
}

private func duplicateDocInfoLayoutPayload(
    _ char: UInt32,
    _ paragraph: UInt32,
    _ section: UInt32,
    _ object: UInt32,
    _ field: UInt32
) -> Data {
    concatenatedData(
        duplicateDocInfoLittleEndianData(char),
        duplicateDocInfoLittleEndianData(paragraph),
        duplicateDocInfoLittleEndianData(section),
        duplicateDocInfoLittleEndianData(object),
        duplicateDocInfoLittleEndianData(field)
    )
}

private func duplicateDocInfoRecordData(_ tag: HwpDocInfoTag, payload: Data) -> Data {
    duplicateDocInfoRecordData(tagId: tag.rawValue, level: 0, payload: payload)
}

private func duplicateDocInfoRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = duplicateDocInfoLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func duplicateDocInfoLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
