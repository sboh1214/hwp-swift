// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

// swiftlint:disable:next type_body_length
final class HwpFileDocInfoRawRecordAssemblyTests: XCTestCase {
    func testActualFixtureBasedAssemblyMatchesEntrypointForReadableStreams() throws {
        for fixtureId in ["plain-text-minimal", "multi-section", "BinData"] {
            let fixture = try FixtureLoader.load(id: fixtureId)
            let streams = try actualReadableHwpStreams(fromFixture: fixtureId)
            let assembled = try HwpFile(
                fileHeader: streams.fileHeader,
                docInfoData: streams.docInfoData,
                sectionDataArray: streams.sectionDataArray,
                summaryData: streams.summaryData,
                previewTextData: streams.previewTextData,
                previewImageData: streams.previewImageData,
                binaryData: streams.binaryData
            )
            let fromPath = try HwpFile(fromPath: fixture.documentURL.path)

            expect(assembled) == fromPath
            expect(assembled.docInfo.rawPayload) == streams.docInfoData
            expect(assembled.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
            expect(assembled.binaryDataArray.map(\.data)) == streams.binaryData.map(\.data)
        }
    }

    func testActualFixtureBasedAssemblyPreservesInjectedTopLevelRawDocInfoRecords() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.distributeDocData).to(beNil())
        expect(baseDocInfo.trackChangeArray).to(beEmpty())

        let injected = InjectedTopLevelRawDocInfoRecords(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )

        expectTopLevelRawDocInfoRecords(in: hwp.docInfo, match: injected)
        expect(hwp.docInfo.unknownRecords).to(beEmpty())
        expect(hwp.sectionArray.count) == Int(baseDocInfo.documentProperties.sectionSize)
    }

    func testActualFixtureBasedTopLevelRawDocInfoRecordsSurviveCodableRoundTrip() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedTopLevelRawDocInfoRecords(baseDocInfoData: streams.docInfoData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectTopLevelRawDocInfoRecords(in: decoded.docInfo, match: injected)
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }

    func testActualFixtureBasedMemoShapeAndForbiddenCharSurviveCodableRoundTrip()
        throws
    {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        expect(baseDocInfo.memoShapeArray).to(beEmpty())
        expect(baseDocInfo.topLevelForbiddenCharArray).to(beEmpty())

        let injected = InjectedMemoForbiddenRecords(
            baseDocInfoData: streams.docInfoData
        )
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: streams.sectionDataArray
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectMemoShapeAndForbiddenCharRecords(in: hwp.docInfo, match: injected)
        expectMemoShapeAndForbiddenCharRecords(in: decoded.docInfo, match: injected)
        expectIdMappingRawRecords(in: hwp.docInfo, match: baseDocInfo)
        expectIdMappingRawRecords(in: decoded.docInfo, match: baseDocInfo)
        expect(hwp.docInfo.unknownRecords) == baseDocInfo.unknownRecords
        expect(decoded.docInfo.rawPayload) == injected.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    }

    func testActualFixtureBasedAssemblyPreservesInjectedUnknownDocInfoRecordTree() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        let baseDocInfo = try HwpDocInfo.load(streams.docInfoData, streams.fileHeader.version)
        let baseUnknownRecordCount = baseDocInfo.unknownRecords.count

        let unknownPayload = Data([0xA9, 0xB8, 0xC7])
        let childPayload = Data([0xD6, 0xE5])
        let grandchildPayload = Data([0xF4])
        let docInfoData = streams.docInfoData
            + rawRecordData(tagId: 0x2EE, level: 0, payload: unknownPayload)
            + rawRecordData(tagId: 0x2EF, level: 1, payload: childPayload)
            + rawRecordData(tagId: 0x2F0, level: 2, payload: grandchildPayload)

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: docInfoData,
            sectionDataArray: streams.sectionDataArray
        )

        expect(hwp.docInfo.rawPayload) == docInfoData
        expect(hwp.docInfo.unknownRecords.count) == baseUnknownRecordCount + 1
        let unknownRecord = try XCTUnwrap(hwp.docInfo.unknownRecords.last)
        expect(unknownRecord) == assemblyExpectedUnknownRecord(
            tagId: 0x2EE,
            level: 0,
            payload: unknownPayload,
            children: [
                assemblyExpectedRecord(
                    tagId: 0x2EF,
                    level: 1,
                    payload: childPayload,
                    children: [
                        assemblyExpectedRecord(
                            tagId: 0x2F0,
                            level: 2,
                            payload: grandchildPayload
                        ),
                    ]
                ),
            ]
        )
        expect(hwp.sectionArray.count) == Int(baseDocInfo.documentProperties.sectionSize)
    }

    func testActualFixtureBasedAssemblyRejectsTruncatedInjectedDocInfoRecord() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        let docInfoData = streams.docInfoData + truncatedExtendedRawRecordData(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            declaredPayloadSize: 5,
            actualPayload: Data([0xAA, 0xBB])
        )

        expect {
            _ = try HwpFile(
                fileHeader: streams.fileHeader,
                docInfoData: docInfoData,
                sectionDataArray: streams.sectionDataArray
            )
        }.to(throwError { error in
            assertTruncatedDataError(error, expected: 5, actual: 2)
        })
    }

    func testActualFixtureBasedAssemblyRejectsTruncatedInjectedSectionRecord() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let sectionData = firstSectionData + truncatedExtendedRawRecordData(
            tagId: 0x2FE,
            declaredPayloadSize: 6,
            actualPayload: Data([0xCC])
        )

        expect {
            _ = try HwpFile(
                fileHeader: streams.fileHeader,
                docInfoData: streams.docInfoData,
                sectionDataArray: [sectionData]
            )
        }.to(throwError { error in
            assertTruncatedDataError(error, expected: 6, actual: 1)
        })
    }

    func testActualFixtureBasedAssemblyPreservesInjectedSectionUnknownRecord() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let unknownPayload = Data([0x5E, 0xC7])
        let unknownChildPayload = Data([0xC1])
        let sectionData = firstSectionData
            + rawRecordData(tagId: 0x2FE, level: 0, payload: unknownPayload)
            + rawRecordData(tagId: 0x2FD, level: 1, payload: unknownChildPayload)

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: [sectionData]
        )

        expect(hwp.sectionArray.count) == 1
        let section = try XCTUnwrap(hwp.sectionArray.first)
        expect(section.rawPayload) == sectionData
        let unknownRecord = try XCTUnwrap(section.unknownRecords.last)
        expect(unknownRecord) == assemblyExpectedUnknownRecord(
            tagId: 0x2FE,
            level: 0,
            payload: unknownPayload,
            children: [
                assemblyExpectedRecord(
                    tagId: 0x2FD,
                    level: 1,
                    payload: unknownChildPayload
                ),
            ]
        )
    }

    func testActualFixtureBasedAssemblyPreservesInjectedUnknownControl() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let ctrlId: UInt32 = 0x1234_5678
        let controlPayload = littleEndianRecordHeader(ctrlId) + Data([0x9A, 0xBC])
        let controlChildPayload = Data([0xE1, 0xE2])
        let controlGrandchildPayload = Data([0xF3])
        let sectionData = firstSectionData
            + rawRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + rawRecordData(tagId: 0x2FC, level: 2, payload: controlChildPayload)
            + rawRecordData(tagId: 0x2FB, level: 3, payload: controlGrandchildPayload)

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: [sectionData]
        )

        let controls = hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
            paragraph.ctrlHeaderArray ?? []
        }
        guard case let .unknown(header) = controls.last else {
            return fail("Expected injected unknown control to be preserved")
        }

        expect(header.ctrlId) == ctrlId
        expect(header.rawPayload) == controlPayload
        expect(header.unknownChildren) == [
            assemblyExpectedUnknownRecord(
                tagId: 0x2FC,
                level: 2,
                payload: controlChildPayload,
                children: [
                    assemblyExpectedRecord(
                        tagId: 0x2FB,
                        level: 3,
                        payload: controlGrandchildPayload
                    ),
                ]
            ),
        ]
    }

    func testActualFixtureBasedAssemblyPreservesInjectedTruncatedControlHeader()
        throws
    {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let controlPayload = Data([0x01, 0x02, 0x03])
        let controlChildPayload = Data([0xE4, 0xE5])
        let sectionData = firstSectionData
            + rawRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + rawRecordData(tagId: 0x2FA, level: 2, payload: controlChildPayload)

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: [sectionData]
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        expectLastUnknownControl(
            in: hwp,
            payload: controlPayload,
            childPayload: controlChildPayload
        )
        expectLastUnknownControl(
            in: decoded,
            payload: controlPayload,
            childPayload: controlChildPayload
        )
        expect(decoded.sectionArray.map(\.rawPayload)) == [sectionData]
    }

    func testActualFixtureBasedRawRecordsSurviveCodableRoundTrip() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let injected = InjectedCodableRawRecords(
            baseDocInfoData: streams.docInfoData,
            baseSectionData: firstSectionData
        )
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: injected.docInfoData,
            sectionDataArray: [injected.sectionData]
        )

        let encoded = try JSONEncoder().encode(hwp)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

        try expectDecodedRawRecords(decoded, match: injected)
    }

    func testActualFixtureBasedAssemblyPreservesInjectedMalformedKnownControl() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let injected = InjectedMalformedTableControl(baseSectionData: firstSectionData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: [injected.sectionData]
        )

        guard let header = lastNotImplementedHeader(in: hwp) else {
            return fail("Expected injected malformed table control to be raw-preserved")
        }

        expectMalformedTableControl(header, match: injected)
    }

    func testActualFixtureBasedMalformedKnownControlSurvivesCodableRoundTrip() throws {
        let streams = try actualReadableHwpStreams(fromFixture: "plain-text-minimal")
        guard let firstSectionData = streams.sectionDataArray.first else {
            return fail("Expected actual fixture to include Section0")
        }

        let injected = InjectedMalformedTableControl(baseSectionData: firstSectionData)
        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: [injected.sectionData]
        )
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        guard let header = lastNotImplementedHeader(in: decoded) else {
            return fail("Expected decoded malformed table control to be raw-preserved")
        }

        expectMalformedTableControl(header, match: injected)
        expect(decoded.sectionArray.map(\.rawPayload)) == [injected.sectionData]
    }
}

private struct InjectedTopLevelRawDocInfoRecords {
    let docInfoData: Data
    let distributePayload: Data
    let distributeChildPayload: Data
    let firstTrackChangePayload: Data
    let firstTrackChangeChildPayload: Data
    let secondTrackChangePayload: Data

    init(baseDocInfoData: Data) {
        distributePayload = Data([0xD1, 0x57, 0x00, 0x01])
        distributeChildPayload = Data([0xD1, 0xC1])
        firstTrackChangePayload = Data([0x71, 0x72, 0x73])
        firstTrackChangeChildPayload = Data([0x7A])
        secondTrackChangePayload = Data([0x81, 0x82])
        docInfoData = baseDocInfoData
            + rawRecordData(.distributeDocData, payload: distributePayload)
            + rawRecordData(tagId: 0x315, level: 1, payload: distributeChildPayload)
            + rawRecordData(.trackChange, payload: firstTrackChangePayload)
            + rawRecordData(tagId: 0x316, level: 1, payload: firstTrackChangeChildPayload)
            + rawRecordData(.trackChange, payload: secondTrackChangePayload)
    }
}

private struct InjectedMemoForbiddenRecords {
    let docInfoData: Data
    let memoShapePayload: Data
    let memoShapeRawTrailing: Data
    let memoShapeChildPayload: Data
    let memoShapeGrandchildPayload: Data
    let forbiddenCharPayload: Data
    let forbiddenCharChildPayload: Data
    let forbiddenCharGrandchildPayload: Data

    init(baseDocInfoData: Data) {
        memoShapeRawTrailing = Data([0xAA, 0xBB, 0xCC, 0xDD])
        memoShapePayload = injectedMemoShapePayload(rawTrailing: memoShapeRawTrailing)
        memoShapeChildPayload = Data([0xB1, 0xB2])
        memoShapeGrandchildPayload = Data([0xB3])
        forbiddenCharPayload = Data([0xF0, 0xF1, 0xF2])
        forbiddenCharChildPayload = Data([0xC1, 0xC2])
        forbiddenCharGrandchildPayload = Data([0xC3])
        docInfoData = baseDocInfoData
            + rawRecordData(.memoShape, payload: memoShapePayload)
            + rawRecordData(tagId: 0x324, level: 1, payload: memoShapeChildPayload)
            + rawRecordData(tagId: 0x325, level: 2, payload: memoShapeGrandchildPayload)
            + rawRecordData(.forbiddenChar, payload: forbiddenCharPayload)
            + rawRecordData(tagId: 0x326, level: 1, payload: forbiddenCharChildPayload)
            + rawRecordData(tagId: 0x327, level: 2, payload: forbiddenCharGrandchildPayload)
    }
}

private struct InjectedCodableRawRecords {
    let docInfoData: Data
    let sectionData: Data
    let ctrlId: UInt32
    let docInfoPayload: Data
    let docInfoChildPayload: Data
    let controlPayload: Data
    let controlChildPayload: Data
    let sectionUnknownPayload: Data
    let sectionUnknownChildPayload: Data

    init(baseDocInfoData: Data, baseSectionData: Data) {
        docInfoPayload = Data([0xA1, 0xA2, 0xA3])
        docInfoChildPayload = Data([0xB1, 0xB2])
        docInfoData = baseDocInfoData
            + rawRecordData(tagId: 0x2EE, level: 0, payload: docInfoPayload)
            + rawRecordData(tagId: 0x2EF, level: 1, payload: docInfoChildPayload)
        ctrlId = 0x1234_5678
        controlPayload = littleEndianRecordHeader(ctrlId) + Data([0xC1, 0xC2])
        controlChildPayload = Data([0xD1])
        sectionUnknownPayload = Data([0xE1, 0xE2])
        sectionUnknownChildPayload = Data([0xE3])
        sectionData = baseSectionData
            + rawRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + rawRecordData(tagId: 0x2FC, level: 2, payload: controlChildPayload)
            + rawRecordData(tagId: 0x2FD, level: 0, payload: sectionUnknownPayload)
            + rawRecordData(tagId: 0x2FE, level: 1, payload: sectionUnknownChildPayload)
    }
}

private func expectTopLevelRawDocInfoRecords(
    in docInfo: HwpDocInfo,
    match injected: InjectedTopLevelRawDocInfoRecords
) {
    expect(docInfo.rawPayload) == injected.docInfoData
    expect(docInfo.distributeDocData?.rawPayload) == injected.distributePayload
    expect(docInfo.distributeDocData?.distributeDocDataInfo?.values) == [0x0100_57D1]
    expect(docInfo.distributeDocData?.distributeDocDataInfo?.valuesRawPayload) ==
        injected.distributePayload
    expect(docInfo.distributeDocData?.distributeDocDataInfo?.rawTrailing).to(beEmpty())
    expect(docInfo.distributeDocData?.unknownChildren ?? []) == [
        assemblyExpectedUnknownRecord(
            tagId: 0x315,
            level: 1,
            payload: injected.distributeChildPayload
        ),
    ]
    expect(docInfo.topLevelTrackChangeArray.map(\.rawPayload)) == [
        injected.firstTrackChangePayload,
        injected.secondTrackChangePayload,
    ]
    expect(docInfo.topLevelTrackChangeArray.map(\.unknownChildren)) == [
        [
            assemblyExpectedUnknownRecord(
                tagId: 0x316,
                level: 1,
                payload: injected.firstTrackChangeChildPayload
            ),
        ],
        [],
    ]
}

private func expectMemoShapeAndForbiddenCharRecords(
    in docInfo: HwpDocInfo,
    match injected: InjectedMemoForbiddenRecords
) {
    expect(docInfo.rawPayload) == injected.docInfoData
    expect(docInfo.idMappings.memoShapeArray).to(beEmpty())
    expectMemoShapeRecord(in: docInfo, match: injected)
    expectForbiddenCharRecord(in: docInfo, match: injected)
}

private func expectIdMappingRawRecords(in docInfo: HwpDocInfo, match baseDocInfo: HwpDocInfo) {
    expect(docInfo.idMappings.memoShapeArray.map(\.rawPayload)) ==
        baseDocInfo.idMappings.memoShapeArray.map(\.rawPayload)
    expect(docInfo.idMappings.forbiddenCharArray.map(\.rawPayload)) ==
        baseDocInfo.idMappings.forbiddenCharArray.map(\.rawPayload)
}

private func expectMemoShapeRecord(
    in docInfo: HwpDocInfo,
    match injected: InjectedMemoForbiddenRecords
) {
    expect(docInfo.memoShapeArray.map(\.rawPayload)) == [injected.memoShapePayload]
    let memoShape = docInfo.memoShapeArray.first
    expect(memoShape?.shapeInfo?.width) == 24000
    expect(memoShape?.shapeInfo?.lineType) == 3
    expect(memoShape?.shapeInfo?.lineWidth) == 4
    expect(memoShape?.shapeInfo?.lineColor) == HwpColor(0x33, 0x22, 0x11)
    expect(memoShape?.shapeInfo?.fillColor) == HwpColor(0x66, 0x55, 0x44)
    expect(memoShape?.shapeInfo?.activeColor) == HwpColor(0x99, 0x88, 0x77)
    expect(memoShape?.shapeInfo?.rawTrailing) == injected.memoShapeRawTrailing
    expect(memoShape?.unknownChildren ?? []) == [
        assemblyExpectedUnknownRecord(
            tagId: 0x324,
            level: 1,
            payload: injected.memoShapeChildPayload,
            children: [
                assemblyExpectedRecord(
                    tagId: 0x325,
                    level: 2,
                    payload: injected.memoShapeGrandchildPayload
                ),
            ]
        ),
    ]
}

private func expectForbiddenCharRecord(
    in docInfo: HwpDocInfo,
    match injected: InjectedMemoForbiddenRecords
) {
    expect(docInfo.topLevelForbiddenCharArray.map(\.rawPayload)) == [
        injected.forbiddenCharPayload,
    ]
    expect(docInfo.topLevelForbiddenCharArray.map(\.data)) == [
        injected.forbiddenCharPayload,
    ]
    expect(docInfo.topLevelForbiddenCharArray.map(\.unknownChildren)) == [
        [
            assemblyExpectedUnknownRecord(
                tagId: 0x326,
                level: 1,
                payload: injected.forbiddenCharChildPayload,
                children: [
                    assemblyExpectedRecord(
                        tagId: 0x327,
                        level: 2,
                        payload: injected.forbiddenCharGrandchildPayload
                    ),
                ]
            ),
        ],
    ]
}

private func expectDecodedRawRecords(
    _ decoded: HwpFile,
    match injected: InjectedCodableRawRecords
) throws {
    expect(decoded.docInfo.rawPayload) == injected.docInfoData
    let docInfoUnknownRecord = try XCTUnwrap(decoded.docInfo.unknownRecords.last)
    expect(docInfoUnknownRecord) == assemblyExpectedUnknownRecord(
        tagId: 0x2EE,
        level: 0,
        payload: injected.docInfoPayload,
        children: [
            assemblyExpectedRecord(tagId: 0x2EF, level: 1, payload: injected.docInfoChildPayload),
        ]
    )
    expect(decoded.sectionArray.map(\.rawPayload)) == [injected.sectionData]
    let section = try XCTUnwrap(decoded.sectionArray.first)
    let sectionUnknownRecord = try XCTUnwrap(section.unknownRecords.last)
    expect(sectionUnknownRecord) == assemblyExpectedUnknownRecord(
        tagId: 0x2FD,
        level: 0,
        payload: injected.sectionUnknownPayload,
        children: [
            assemblyExpectedRecord(
                tagId: 0x2FE,
                level: 1,
                payload: injected.sectionUnknownChildPayload
            ),
        ]
    )
    let controls = decoded.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        paragraph.ctrlHeaderArray ?? []
    }
    guard case let .unknown(header) = controls.last else {
        return fail("Expected decoded unknown control to be preserved")
    }

    expect(header.ctrlId) == injected.ctrlId
    expect(header.rawPayload) == injected.controlPayload
    expect(header.unknownChildren) == [
        assemblyExpectedUnknownRecord(
            tagId: 0x2FC,
            level: 2,
            payload: injected.controlChildPayload
        ),
    ]
}

private func expectLastUnknownControl(
    in hwp: HwpFile,
    payload: Data,
    childPayload: Data
) {
    let controls = hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        paragraph.ctrlHeaderArray ?? []
    }
    guard case let .unknown(header) = controls.last else {
        return fail("Expected last control to be preserved as unknown")
    }

    expect(header.ctrlId) == 0
    expect(header.rawPayload) == payload
    expect(header.unknownChildren) == [
        assemblyExpectedUnknownRecord(
            tagId: 0x2FA,
            level: 2,
            payload: childPayload
        ),
    ]
}

private struct InjectedMalformedTableControl {
    let sectionData: Data
    let controlPayload: Data
    let tablePropertyPayload: Data
    let tablePropertyChildPayload: Data
    let controlChildPayload: Data

    init(baseSectionData: Data) {
        controlPayload = littleEndianRecordHeader(HwpCommonCtrlId.table.rawValue)
        tablePropertyPayload = Data([0xA1])
        tablePropertyChildPayload = Data([0xA2])
        controlChildPayload = Data([0xB2, 0xC3])
        sectionData = baseSectionData
            + rawRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayload
            )
            + rawRecordData(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePropertyPayload
            )
            + rawRecordData(tagId: 0x2FB, level: 3, payload: tablePropertyChildPayload)
            + rawRecordData(tagId: 0x2FC, level: 2, payload: controlChildPayload)
    }
}

private func lastNotImplementedHeader(in hwp: HwpFile) -> HwpCtrlHeader? {
    let controls = hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        paragraph.ctrlHeaderArray ?? []
    }
    guard case let .notImplemented(header) = controls.last else {
        return nil
    }
    return header
}

private func expectMalformedTableControl(
    _ header: HwpCtrlHeader,
    match injected: InjectedMalformedTableControl
) {
    expect(header.ctrlId) == HwpCommonCtrlId.table.rawValue
    expect(header.rawPayload) == injected.controlPayload
    expect(header.unknownChildren) == [
        assemblyExpectedUnknownRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: injected.tablePropertyPayload,
            children: [
                assemblyExpectedRecord(
                    tagId: 0x2FB,
                    level: 3,
                    payload: injected.tablePropertyChildPayload
                ),
            ]
        ),
        assemblyExpectedUnknownRecord(
            tagId: 0x2FC,
            level: 2,
            payload: injected.controlChildPayload
        ),
    ]
}

private struct ActualReadableHwpStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
    let summaryData: Data?
    let previewTextData: Data?
    let previewImageData: Data?
    let binaryData: [(name: String, data: Data)]
}

private func actualReadableHwpStreams(fromFixture id: String) throws -> ActualReadableHwpStreams {
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
    let summaryData = try reader.getOptionalDataFromStream(.summary, false)
    let previewTextData = try reader.getOptionalDataFromStream(.previewText, false)
    let previewImageData = try reader.getOptionalDataFromStream(.previewImage, false)
    let binaryData = try readBinaryDataStreams(
        reader,
        docInfo: docInfo,
        storageIsCompressed: fileHeader.fileProperty.isCompressed
    )

    return ActualReadableHwpStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray,
        summaryData: summaryData,
        previewTextData: previewTextData,
        previewImageData: previewImageData,
        binaryData: binaryData
    )
}

private func rawRecordData(_ tag: HwpDocInfoTag, payload: Data) -> Data {
    rawRecordData(tagId: tag.rawValue, level: 0, payload: payload)
}

private func injectedMemoShapePayload(rawTrailing: Data) -> Data {
    var data = Data()
    data.append(littleEndianRecordHeader(24000))
    data.append(contentsOf: [0x03, 0x04])
    data.append(littleEndianRecordHeader(0x0011_2233))
    data.append(littleEndianRecordHeader(0x0044_5566))
    data.append(littleEndianRecordHeader(0x0077_8899))
    data.append(rawTrailing)
    return data
}

private func assemblyExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        assemblyExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func assemblyExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func rawRecordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
    var data = littleEndianRecordHeader(tagId | (level << 10) | (UInt32(payload.count) << 20))
    data.append(payload)
    return data
}

private func truncatedExtendedRawRecordData(
    tagId: UInt32,
    declaredPayloadSize: UInt32,
    actualPayload: Data
) -> Data {
    var data = littleEndianRecordHeader(tagId | (0xFFF << 20))
    data.append(littleEndianRecordHeader(declaredPayloadSize))
    data.append(actualPayload)
    return data
}

private func assertTruncatedDataError(_ error: Error, expected: Int, actual: Int) {
    guard case let HwpError.truncatedData(actualExpected, actualBytes) = error else {
        return fail("Expected truncatedData, got \(error)")
    }
    expect(actualExpected) == expected
    expect(actualBytes) == actual
}

private func littleEndianRecordHeader(_ value: UInt32) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
