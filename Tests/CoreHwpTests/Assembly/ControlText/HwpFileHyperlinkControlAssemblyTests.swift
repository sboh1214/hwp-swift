@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileHyperlinkControlAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesHyperlinkThroughCodableRoundTrip()
        throws
    {
        let streams = try hyperlinkAssemblyStreams(fromFixture: "plain-text-minimal")
        let injected = InjectedHyperlinkControl(
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

        expectHyperlink(in: hwp, match: injected)
        expectHyperlink(in: decoded, match: injected)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == sectionDataArray
    }
}

private struct HyperlinkAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
}

private struct InjectedHyperlinkControl {
    let sectionData: Data
    let property: UInt32
    let unknownPrefix: BYTE
    let url: String
    let urlLengthRawPayload: Data
    let urlRawPayload: Data
    let rawTrailing: Data
    let hyperlinkPayload: Data
    let unknownChildPayload: Data
    let unknownGrandchildPayload: Data

    init(baseSectionData: Data) {
        property = 0x0102_0304
        unknownPrefix = 0x05
        url = "https://example.test/CoreHwp"
        urlLengthRawPayload = hyperlinkLittleEndianData(WORD(url.utf16.count))
        urlRawPayload = hyperlinkUTF16Payload(url)
        rawTrailing = Data([0xBA, 0xAD, 0xF0, 0x0D])
        hyperlinkPayload = Self.payload(
            property: property,
            unknownPrefix: unknownPrefix,
            url: url,
            rawTrailing: rawTrailing
        )
        unknownChildPayload = Data([0xD4, 0xD5])
        unknownGrandchildPayload = Data([0xD6])

        sectionData = baseSectionData
            + hyperlinkRecordData(
                tagId: HwpSectionTag.ctrlHeader.rawValue,
                level: 1,
                payload: hyperlinkPayload
            )
            + hyperlinkRecordData(
                tagId: 0x2EF,
                level: 2,
                payload: unknownChildPayload
            )
            + hyperlinkRecordData(
                tagId: 0x2EE,
                level: 3,
                payload: unknownGrandchildPayload
            )
    }

    private static func payload(
        property: UInt32,
        unknownPrefix: BYTE,
        url: String,
        rawTrailing: Data
    ) -> Data {
        var payload = Data()
        payload.append(hyperlinkLittleEndianData(HwpFieldCtrlId.hyperLink.rawValue))
        payload.append(hyperlinkLittleEndianData(property))
        payload.append(hyperlinkLittleEndianData(unknownPrefix))
        payload.append(hyperlinkLittleEndianData(WORD(url.utf16.count)))
        payload.append(hyperlinkUTF16Payload(url))
        payload.append(rawTrailing)
        return payload
    }
}

private func hyperlinkAssemblyStreams(
    fromFixture id: String
) throws -> HyperlinkAssemblyStreams {
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

    return HyperlinkAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray
    )
}

private func expectHyperlink(
    in hwp: HwpFile,
    match injected: InjectedHyperlinkControl
) {
    let hyperlink = hyperlinks(from: hwp).last

    expect(hyperlink?.ctrlId) == HwpFieldCtrlId.hyperLink.rawValue
    expect(hyperlink?.property) == injected.property
    expect(hyperlink?.unknownPrefix) == injected.unknownPrefix
    expect(hyperlink?.urlLength) == WORD(injected.url.utf16.count)
    expect(hyperlink?.urlLengthRawPayload) == injected.urlLengthRawPayload
    expect(hyperlink?.url) == injected.url
    expect(hyperlink?.urlRawPayload) == injected.urlRawPayload
    expect(hyperlink?.rawPayload) == injected.hyperlinkPayload
    expect(hyperlink?.rawTrailing) == injected.rawTrailing
    expect(hyperlink?.unknownChildren ?? []) == [
        hyperlinkExpectedUnknownRecord(
            tagId: 0x2EF,
            level: 2,
            payload: injected.unknownChildPayload,
            children: [
                hyperlinkExpectedRecord(
                    tagId: 0x2EE,
                    level: 3,
                    payload: injected.unknownGrandchildPayload
                ),
            ]
        ),
    ]
}

private func hyperlinks(from hwp: HwpFile) -> [HwpHyperlink] {
    hwp.sectionArray.flatMap(\.paragraph).flatMap { paragraph in
        (paragraph.ctrlHeaderArray ?? []).compactMap { control in
            guard case let .hyperLink(hyperlink) = control else {
                return nil
            }
            return hyperlink
        }
    }
}

private func hyperlinkRecordData(
    tagId: UInt32,
    level: UInt32,
    payload: Data
) -> Data {
    var data = hyperlinkLittleEndianData(
        tagId | (level << 10) | (UInt32(payload.count) << 20)
    )
    data.append(payload)
    return data
}

private func hyperlinkExpectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(
        hyperlinkExpectedRecord(tagId: tagId, level: level, payload: payload, children: children)
    )
}

private func hyperlinkExpectedRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

private func hyperlinkUTF16Payload(_ value: String) -> Data {
    value.utf16.reduce(into: Data()) { data, codeUnit in
        data.append(hyperlinkLittleEndianData(WCHAR(codeUnit)))
    }
}

private func hyperlinkLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
