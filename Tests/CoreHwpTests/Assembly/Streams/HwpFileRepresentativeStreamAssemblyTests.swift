@testable import CoreHwp
import Foundation
import Nimble
import OLEKit
import XCTest

final class HwpFileRepresentativeStreamAssemblyTests: XCTestCase {
    func testRepresentativeActualStreamsAssembleSameAsPathEntrypoint() throws {
        for fixtureId in representativeStreamAssemblyFixtureIds {
            let fixture = try FixtureLoader.load(id: fixtureId)
            let streams = try representativeReadableStreams(fromFixture: fixtureId)
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

            assertRepresentativeAssembly(assembled, matches: fromPath, streams: streams)

            #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
                let fromData = try HwpFile(fromData: Data(contentsOf: fixture.documentURL))
                let fromWrapper = try HwpFile(
                    fromWrapper: FileWrapper(url: fixture.documentURL, options: [])
                )

                assertRepresentativeAssembly(assembled, matches: fromData, streams: streams)
                assertRepresentativeAssembly(assembled, matches: fromWrapper, streams: streams)
            #endif
        }
    }

    func testRepresentativeStreamAssemblyFixturesCoverOptionalStreamCases() throws {
        let fixtures = try representativeStreamAssemblyFixtureIds.map(FixtureLoader.load(id:))
        let fixtureIds = Set(fixtures.map(\.manifest.id))
        let features = fixtures.reduce(into: Set<String>()) { result, fixture in
            result.formUnion(fixture.manifest.features)
        }

        expect(fixtureIds).to(contain("plain-text-hancom-mac2026"))
        expect(fixtureIds).to(contain("missing-summary-derived"))
        expect(fixtureIds).to(contain("missing-preview-text-derived"))
        expect(fixtureIds).to(contain("missing-preview-image-derived"))
        expect(fixtureIds).to(contain("multi-section"))
        expect(fixtureIds).to(contain("BinData"))
        expect(features).to(contain("preview-text"))
        expect(features).to(contain("preview-image"))
        expect(features).to(contain("derived-missing-summary"))
        expect(features).to(contain("derived-missing-preview-text"))
        expect(features).to(contain("derived-missing-preview-image"))
        expect(features).to(contain("bin-data"))
        expect(features).to(contain("embedded-image-reference"))
        expect(features).to(contain("chart"))
        expect(features).to(contain("header-footer"))
        expect(features).to(contain("text-box"))
        expect(features).to(contain("multi-section"))
    }

    func testRepresentativeStreamAssemblyIncludesMissingOptionalDefaults() throws {
        let missingSummary = try representativeReadableStreams(
            fromFixture: "missing-summary-derived"
        )
        let missingPreviewText = try representativeReadableStreams(
            fromFixture: "missing-preview-text-derived"
        )
        let missingPreviewImage = try representativeReadableStreams(
            fromFixture: "missing-preview-image-derived"
        )

        expect(missingSummary.summaryData).to(beNil())
        expect(missingPreviewText.previewTextData).to(beNil())
        expect(missingPreviewImage.previewImageData).to(beNil())
    }
}

private let representativeStreamAssemblyFixtureIds = [
    "plain-text-hancom-mac2026",
    "missing-summary-derived",
    "missing-preview-text-derived",
    "missing-preview-image-derived",
    "multi-section",
    "BinData",
    "chart",
    "header-footer",
    "text-box",
]

private struct RepresentativeReadableStreams {
    let fileHeader: HwpFileHeader
    let docInfoData: Data
    let sectionDataArray: [Data]
    let summaryData: Data?
    let previewTextData: Data?
    let previewImageData: Data?
    let binaryData: [(name: String, data: Data)]
}

private func assertRepresentativeAssembly(
    _ assembled: HwpFile,
    matches entrypoint: HwpFile,
    streams: RepresentativeReadableStreams
) {
    expect(assembled) == entrypoint
    expect(assembled.fileHeader.rawPayload) == entrypoint.fileHeader.rawPayload
    expect(assembled.docInfo.rawPayload) == streams.docInfoData
    expect(assembled.sectionArray.map(\.rawPayload)) == streams.sectionDataArray
    expect(assembled.summary.rawPayload) == entrypoint.summary.rawPayload
    expect(assembled.previewText.rawPayload) == entrypoint.previewText.rawPayload
    expect(assembled.previewImage.rawPayload) == entrypoint.previewImage.rawPayload
    expect(assembled.binaryDataArray.map(\.name)) == streams.binaryData.map(\.name)
    expect(assembled.binaryDataArray.map(\.streamId)) == entrypoint.binaryDataArray.map(\.streamId)
    expect(assembled.binaryDataArray.map(\.extensionName)) ==
        entrypoint.binaryDataArray.map(\.extensionName)
    expect(assembled.binaryDataArray.map(\.data)) == streams.binaryData.map(\.data)
}

private func representativeReadableStreams(
    fromFixture id: String
) throws -> RepresentativeReadableStreams {
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

    return try RepresentativeReadableStreams(
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
