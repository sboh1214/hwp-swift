@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileOptionalStreamAssemblyTests: XCTestCase {
    func testActualFixtureAssemblyPreservesUnknownPreviewImageThroughCodableRoundTrip()
        throws
    {
        let streams = try optionalStreamAssemblyStreams(fromFixture: "chart")
        let unknownPreviewImageData = Data([0x00, 0x01, 0x02, 0x03, 0x04])

        let hwp = try HwpFile(
            fileHeader: streams.fileHeader,
            docInfoData: streams.docInfoData,
            sectionDataArray: streams.sectionDataArray,
            summaryData: streams.summaryData,
            previewTextData: streams.previewTextData,
            previewImageData: unknownPreviewImageData,
            binaryData: streams.binaryData
        )
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(hwp)
        )

        expect(hwp.previewImage.rawPayload) == unknownPreviewImageData
        expect(hwp.previewImage.image) == unknownPreviewImageData
        expect(hwp.previewImage.format) == .unknown
        expect(decoded.previewImage.rawPayload) == unknownPreviewImageData
        expect(decoded.previewImage.image) == unknownPreviewImageData
        expect(decoded.previewImage.format) == .unknown
        expect(decoded.docInfo.rawPayload) == streams.docInfoData
        expect(decoded.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
        expect(decoded.summary.rawPayload) == hwp.summary.rawPayload
        expect(decoded.previewText.rawPayload) == hwp.previewText.rawPayload
        expect(decoded.binaryDataArray.map(\.name)) == streams.binaryData.map(\.name)
        expect(decoded.binaryDataArray.map(\.data)) == streams.binaryData.map(\.data)
    }

    func testActualFixtureAssemblyRejectsMalformedPreviewTextWithTypedError() throws {
        let streams = try optionalStreamAssemblyStreams(fromFixture: "plain-text-minimal")
        let invalidPreviewTextData = Data([0x00, 0xD8])

        expect {
            _ = try HwpFile(
                fileHeader: streams.fileHeader,
                docInfoData: streams.docInfoData,
                sectionDataArray: streams.sectionDataArray,
                summaryData: streams.summaryData,
                previewTextData: invalidPreviewTextData,
                previewImageData: streams.previewImageData,
                binaryData: streams.binaryData
            )
        }.to(throwError { error in
            guard case let HwpError.invalidDataForString(data, name) = error else {
                return fail("Expected invalidDataForString, got \(error)")
            }
            expect(data) == invalidPreviewTextData
            expect(name) == "PreviewText"
        })
    }
}

private struct OptionalStreamAssemblyStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
    let summaryData: Data?
    let previewTextData: Data?
    let previewImageData: Data?
    let binaryData: [(name: String, data: Data)]
}

private func optionalStreamAssemblyStreams(
    fromFixture id: String
) throws -> OptionalStreamAssemblyStreams {
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

    return try OptionalStreamAssemblyStreams(
        fileHeader: fileHeader,
        docInfoData: docInfoData,
        sectionDataArray: sectionDataArray,
        summaryData: reader.getOptionalDataFromStream(.summary, false),
        previewTextData: reader.getOptionalDataFromStream(.previewText, false),
        previewImageData: reader.getOptionalDataFromStream(.previewImage, false),
        binaryData: readBinaryDataStreams(
            reader,
            docInfo: docInfo,
            storageIsCompressed: fileHeader.fileProperty.isCompressed
        )
    )
}
