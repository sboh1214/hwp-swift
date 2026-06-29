// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFilePreservedControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyExtractsInjectedPreservedControlsThroughCodableRoundTrip()
        throws
    {
        let streams = try preservedControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedPreservedControls(
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

        expectInjectedPreservedControls(in: hwp, match: injected)
        expectInjectedPreservedControls(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesOtherControlFallbacksThroughCodableRoundTrip()
        throws
    {
        let streams = try preservedControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedOtherControlFallbacks(
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

        expectOtherControlFallbacks(in: hwp, match: injected)
        expectOtherControlFallbacks(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesTruncatedUnknownControlThroughCodableRoundTrip()
        throws
    {
        let streams = try preservedControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedTruncatedUnknownControl(
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

        expectTruncatedUnknownControl(in: hwp, match: injected)
        expectTruncatedUnknownControl(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }

    func testActualFixtureAssemblyPreservesMalformedHyperlinkAsFieldThroughCodableRoundTrip()
        throws
    {
        let streams = try preservedControlAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedFieldControlFallback(
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

        expectFieldControlFallback(in: hwp, match: injected)
        expectFieldControlFallback(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct InjectedPreservedControls {
    let sectionData: Data
    let unknownControlId: UInt32
    let unknownControlPayload: Data
    let unknownChildPayload: Data
    let unknownGrandchildPayload: Data
    let tableControlPayload: Data
    let tablePayload: Data
    let tableChildPayload: Data
    let tableSiblingPayload: Data

    init(baseSectionData: Data) {
        unknownControlId = 0x1234_5678
        unknownControlPayload = concatenatedData(
            preservedControlLittleEndianData(unknownControlId),
            Data([0x9A, 0xBC])
        )
        unknownChildPayload = Data([0xE1, 0xE2])
        unknownGrandchildPayload = Data([0xF3])
        tableControlPayload = preservedControlLittleEndianData(HwpCommonCtrlId.table.rawValue)
        tablePayload = Data([0xA1])
        tableChildPayload = Data([0xA2])
        tableSiblingPayload = Data([0xB2, 0xC3])

        sectionData = concatenatedData(
            baseSectionData,
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: unknownControlPayload
            ),
            preservedControlRecordData(
                tagId: 0x2FC,
                level: 2,
                payload: unknownChildPayload
            ),
            preservedControlRecordData(
                tagId: 0x2FB,
                level: 3,
                payload: unknownGrandchildPayload
            ),
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: tableControlPayload
            ),
            preservedControlRecordData(
                tagId: HwpSectionTag.table.rawValue,
                level: 2,
                payload: tablePayload
            ),
            preservedControlRecordData(
                tagId: 0x2FA,
                level: 3,
                payload: tableChildPayload
            ),
            preservedControlRecordData(
                tagId: 0x2FD,
                level: 2,
                payload: tableSiblingPayload
            )
        )
    }
}

private struct PreservedControlAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedTruncatedUnknownControl {
    let sectionData: Data
    let controlPayloads: [Data]
    let childTagIds: [UInt32]
    let childPayloads: [Data]
    let grandchildTagIds: [UInt32]
    let grandchildPayloads: [Data]

    init(baseSectionData: Data) {
        controlPayloads = [
            Data(),
            Data([0x01, 0x02, 0x03]),
        ]
        childTagIds = [0x2FA, 0x2F8]
        childPayloads = [
            Data([0xD1, 0xD2]),
            Data([0xE1, 0xE2]),
        ]
        grandchildTagIds = [0x2F9, 0x2F7]
        grandchildPayloads = [
            Data([0xD3]),
            Data([0xE3]),
        ]

        var data = baseSectionData
        for index in controlPayloads.indices {
            data.append(preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: controlPayloads[index]
            ))
            data.append(preservedControlRecordData(
                tagId: childTagIds[index],
                level: 2,
                payload: childPayloads[index]
            ))
            data.append(preservedControlRecordData(
                tagId: grandchildTagIds[index],
                level: 3,
                payload: grandchildPayloads[index]
            ))
        }
        sectionData = data
    }
}

private struct InjectedOtherControlFallbacks {
    let sectionData: Data
    let columnPayload: Data
    let columnChildPayload: Data
    let pageNumberPayload: Data
    let pageNumberChildPayload: Data
    let listPayload: Data
    let listHeaderPayload: Data
    let listUnknownPayload: Data

    init(baseSectionData: Data) {
        columnPayload = concatenatedData(
            preservedControlLittleEndianData(HwpOtherCtrlId.column.rawValue),
            Data([0xAA])
        )
        columnChildPayload = Data([0xC0])
        pageNumberPayload = concatenatedData(
            preservedControlLittleEndianData(HwpOtherCtrlId.pageNumberPosition.rawValue),
            preservedControlLittleEndianData(UInt32(0x0102_0304)),
            preservedControlLittleEndianData(WCHAR(0)),
            preservedControlLittleEndianData(WCHAR(45)),
            preservedControlLittleEndianData(WCHAR(45))
        )
        pageNumberChildPayload = Data([0xD0])
        listPayload = preservedControlLittleEndianData(HwpOtherCtrlId.header.rawValue)
        listHeaderPayload = Data([0xE0])
        listUnknownPayload = Data([0xE1, 0xE2])

        sectionData = concatenatedData(
            baseSectionData,
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: columnPayload
            ),
            preservedControlRecordData(tagId: 0x2FA, level: 2, payload: columnChildPayload),
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: pageNumberPayload
            ),
            preservedControlRecordData(tagId: 0x2FB, level: 2, payload: pageNumberChildPayload),
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: listPayload
            ),
            preservedControlRecordData(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: listHeaderPayload
            ),
            preservedControlRecordData(tagId: 0x2FC, level: 2, payload: listUnknownPayload)
        )
    }
}

private struct InjectedFieldControlFallback {
    let sectionData: Data
    let hyperlinkPayload: Data
    let hyperlinkChildPayload: Data
    let hyperlinkGrandchildPayload: Data
    let rawTrailing: Data

    init(baseSectionData: Data) {
        rawTrailing = concatenatedData(
            preservedControlLittleEndianData(UInt32(0)),
            preservedControlLittleEndianData(BYTE(0xFF)),
            preservedControlLittleEndianData(WORD(1)),
            preservedControlLittleEndianData(WCHAR(0xD83D)),
            Data([0xF1, 0xF2])
        )
        hyperlinkPayload = concatenatedData(
            preservedControlLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue),
            rawTrailing
        )
        hyperlinkChildPayload = Data([0xA0, 0xA1])
        hyperlinkGrandchildPayload = Data([0xA2])

        sectionData = concatenatedData(
            baseSectionData,
            preservedControlRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: hyperlinkPayload
            ),
            preservedControlRecordData(
                tagId: 0x2FA,
                level: 2,
                payload: hyperlinkChildPayload
            ),
            preservedControlRecordData(
                tagId: 0x2F9,
                level: 3,
                payload: hyperlinkGrandchildPayload
            )
        )
    }
}

private func preservedControlAssemblyStreams(
    fromFixture id: String
) throws -> PreservedControlAssemblyStreams {
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

    return PreservedControlAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectInjectedPreservedControls(
    in hwp: HwpFile,
    match injected: InjectedPreservedControls
) {
    let controls = FixtureDerivedValues.preservedControls(from: hwp)

    expect(controls.map(\.kind)) == ["unknown", "notImplemented"]
    expect(controls.map(\.header.ctrlId)) == [
        injected.unknownControlId,
        HwpCommonCtrlId.table.rawValue,
    ]

    let unknownHeader = controls.first?.header
    expect(unknownHeader?.rawPayload) == injected.unknownControlPayload
    expect(unknownHeader?.unknownChildren ?? []) == [
        preservedExpectedUnknownRecord(
            tagId: 0x2FC,
            level: 2,
            payload: injected.unknownChildPayload,
            children: [
                preservedExpectedRecord(
                    tagId: 0x2FB,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]

    let tableHeader = controls.last?.header
    expect(tableHeader?.rawPayload) == injected.tableControlPayload
    expect(tableHeader?.unknownChildren ?? []) == [
        preservedExpectedUnknownRecord(
            tagId: HwpSectionTag.table.rawValue,
            level: 2,
            payload: injected.tablePayload,
            children: [
                preservedExpectedRecord(
                    tagId: 0x2FA,
                    level: 3,
                    payload: injected.tableChildPayload
                ),
            ]
        ),
        preservedExpectedUnknownRecord(
            tagId: 0x2FD,
            level: 2,
            payload: injected.tableSiblingPayload
        ),
    ]
}

private func expectTruncatedUnknownControl(
    in hwp: HwpFile,
    match injected: InjectedTruncatedUnknownControl
) {
    let controls = Array(allControls(from: hwp).suffix(injected.controlPayloads.count))
    let headers = controls.compactMap { control -> HwpCtrlHeader? in
        guard case let .unknown(header) = control else {
            return nil
        }
        return header
    }

    expect(headers.count) == injected.controlPayloads.count
    expect(headers.map(\.ctrlId)) == Array(repeating: 0, count: injected.controlPayloads.count)
    expect(headers.map(\.rawPayload)) == injected.controlPayloads
    expect(headers.map(\.unknownChildren)) == injected.controlPayloads.indices.map { index in
        [
            preservedExpectedUnknownRecord(
                tagId: injected.childTagIds[index],
                level: 2,
                payload: injected.childPayloads[index],
                children: [
                    preservedExpectedRecord(
                        tagId: injected.grandchildTagIds[index],
                        level: 3,
                        payload: injected.grandchildPayloads[index]
                    ),
                ]
            ),
        ]
    }
}

private func expectOtherControlFallbacks(
    in hwp: HwpFile,
    match injected: InjectedOtherControlFallbacks
) {
    let controls = FixtureDerivedValues.otherControls(from: hwp)
    let fallbackControls = Array(controls.suffix(3))

    expect(fallbackControls.map(\.ctrlId)) == [
        .column,
        .pageNumberPosition,
        .header,
    ]
    expect(fallbackControls.map(\.rawPayload)) == [
        injected.columnPayload,
        injected.pageNumberPayload,
        injected.listPayload,
    ]
    expect(fallbackControls.map(\.rawTrailing)) == [
        Data([0xAA]),
        Data(injected.pageNumberPayload.dropFirst(MemoryLayout<UInt32>.size)),
        Data(),
    ]
    expect(fallbackControls.map(\.unknownChildren)) == [
        [
            preservedExpectedUnknownRecord(
                tagId: 0x2FA,
                level: 2,
                payload: injected.columnChildPayload
            ),
        ],
        [
            preservedExpectedUnknownRecord(
                tagId: 0x2FB,
                level: 2,
                payload: injected.pageNumberChildPayload
            ),
        ],
        [
            preservedExpectedUnknownRecord(
                tagId: HwpSectionTag.listHeader.rawValue,
                level: 2,
                payload: injected.listHeaderPayload
            ),
            preservedExpectedUnknownRecord(
                tagId: 0x2FC,
                level: 2,
                payload: injected.listUnknownPayload
            ),
        ],
    ]
}

private func expectFieldControlFallback(
    in hwp: HwpFile,
    match injected: InjectedFieldControlFallback
) {
    let fields = fieldControls(from: hwp)
    let fallback = fields.last

    expect(fallback?.ctrlId) == .hyperLink
    expect(fallback?.semanticKind) == .field
    expect(fallback?.rawPayload) == injected.hyperlinkPayload
    expect(fallback?.rawTrailing) == injected.rawTrailing
    expect(fallback?.fieldParameter).to(beNil())
    expect(fallback?.fieldParameterRawTrailing).to(beNil())
    expect(fallback?.unknownChildren ?? []) == [
        preservedExpectedUnknownRecord(
            tagId: 0x2FA,
            level: 2,
            payload: injected.hyperlinkChildPayload,
            children: [
                preservedExpectedRecord(
                    tagId: 0x2F9,
                    level: 3,
                    payload: injected.hyperlinkGrandchildPayload
                ),
            ]
        ),
    ]
}

private func allControls(from hwp: HwpFile) -> [HwpCtrlId] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        paragraph.ctrlHeaderArray ?? []
    }
}

private func fieldControls(from hwp: HwpFile) -> [HwpFieldControl] {
    allControls(from: hwp).compactMap { control in
        guard case let .field(field) = control else {
            return nil
        }
        return field
    }
}

private func preservedControlRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = preservedControlLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func preservedExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        preservedExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func preservedExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func preservedControlLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
