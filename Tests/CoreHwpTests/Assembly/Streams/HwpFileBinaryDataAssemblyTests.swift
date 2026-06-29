@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileBinaryDataAssemblyTests: XCTestCase {
    func testActualBinaryDataStreamsSurviveCodableRoundTrip() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)

        let encoded = try JSONEncoder().encode(hwp)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

        expect(decoded.binaryDataArray.count) == 3
        expect(decoded.binaryDataArray.map(\.name)) == [
            "BIN0001.png",
            "BIN0002.jpeg",
            "BIN0003.gif",
        ]
        expect(decoded.binaryDataArray.map(\.streamId)) == [1, 2, 3]
        expect(decoded.binaryDataArray.map(\.extensionName)) == ["png", "jpeg", "gif"]
        expect(decoded.binaryDataArray.map(\.data)) == hwp.binaryDataArray.map(\.data)
        expect(decoded.binaryDataArray.map(\.data.count)) == [62875, 51551, 20462]
        expect(decoded.docInfo.idMappings.binDataArray.map(\.streamId)) == [1, 2, 3]
        expect(decoded.docInfo.idMappings.binDataArray.map(\.extensionName)) == [
            "png",
            "jpeg",
            "gif",
        ]
    }

    func testActualImageBinaryDataReferencesSurviveCodableRoundTrip() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))

        let actualStreamIds = Set(decoded.binaryDataArray.compactMap(\.streamId))
        let docInfoStreamIds = Set(decoded.docInfo.idMappings.binDataArray.compactMap(\.streamId))
        let pictureBinaryDataIds = decodedPictureBinaryDataIds(from: decoded)

        expect(actualStreamIds) == Set([1, 2, 3])
        expect(docInfoStreamIds) == actualStreamIds
        expect(Set(pictureBinaryDataIds)) == actualStreamIds
        expect(pictureBinaryDataIds) == [1, 2, 3]
        expect(decoded.binaryDataArray.map(\.data)) == hwp.binaryDataArray.map(\.data)
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        func testActualBinaryDataStreamsLoadEquivalentlyThroughDataAndFileWrapper() throws {
            let url = hwpURL(#file, "BinData")
            let pathHwp = try HwpFile(fromPath: url.path)
            let dataHwp = try HwpFile(fromData: Data(contentsOf: url))
            let wrapperHwp = try HwpFile(fromWrapper: FileWrapper(url: url, options: []))

            assertBinaryDataEntrypointMatches(pathHwp, dataHwp)
            assertBinaryDataEntrypointMatches(pathHwp, wrapperHwp)
        }
    #endif

    func testUnrecognizedBinaryDataStreamNameSurvivesCodableRoundTrip() throws {
        let originalHwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)
        guard let originalPayload = originalHwp.binaryDataArray
            .first(where: { $0.name == "BIN0002.jpeg" })?.data
        else {
            return fail("Expected BIN0002.jpeg in BinData fixture")
        }
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "BinData",
            renamingEntry: "BIN0002.jpeg",
            to: "bin0002.jpeg",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }
        let hwp = try HwpFile(fromPath: url.path)

        let encoded = try JSONEncoder().encode(hwp)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: encoded)

        expect(decoded.binaryDataArray.map(\.name)) == [
            "BIN0001.png",
            "BIN0003.gif",
            "bin0002.jpeg",
        ]
        guard let renamed = decoded.binaryDataArray.first(
            where: { $0.name == "bin0002.jpeg" }
        ) else {
            return fail("Expected renamed BinData stream to survive Codable round-trip")
        }
        expect(renamed.streamId).to(beNil())
        expect(renamed.extensionName).to(beNil())
        expect(renamed.data) == originalPayload
    }
}

private func assertBinaryDataEntrypointMatches(_ expected: HwpFile, _ actual: HwpFile) {
    expect(actual.fileHeader.rawPayload) == expected.fileHeader.rawPayload
    expect(actual.docInfo.rawPayload) == expected.docInfo.rawPayload
    expect(actual.sectionArray.map(\.rawPayload)) == expected.sectionArray.map(\.rawPayload)
    expect(actual.summary.rawPayload) == expected.summary.rawPayload
    expect(actual.previewText.rawPayload) == expected.previewText.rawPayload
    expect(actual.previewImage.rawPayload) == expected.previewImage.rawPayload

    expect(actual.binaryDataArray.count) == 3
    expect(actual.binaryDataArray.map(\.name)) == expected.binaryDataArray.map(\.name)
    expect(actual.binaryDataArray.map(\.streamId)) == expected.binaryDataArray.map(\.streamId)
    expect(actual.binaryDataArray.map(\.extensionName)) ==
        expected.binaryDataArray.map(\.extensionName)
    expect(actual.binaryDataArray.map(\.data)) == expected.binaryDataArray.map(\.data)
    expect(actual.binaryDataArray.map(\.data.count)) == [62875, 51551, 20462]

    expect(actual.docInfo.idMappings.binDataArray.map(\.streamId)) ==
        expected.docInfo.idMappings.binDataArray.map(\.streamId)
    expect(actual.docInfo.idMappings.binDataArray.map(\.extensionName)) ==
        expected.docInfo.idMappings.binDataArray.map(\.extensionName)
    expect(Set(decodedPictureBinaryDataIds(from: actual))) ==
        Set(actual.binaryDataArray.compactMap(\.streamId))
    expect(decodedPictureBinaryDataIds(from: actual)) ==
        decodedPictureBinaryDataIds(from: expected)
}

private func decodedPictureBinaryDataIds(from hwp: HwpFile) -> [UInt16] {
    FixtureDerivedValues.allGenShapeObjects(from: hwp)
        .flatMap(\.shapeComponentArray)
        .flatMap(\.pictureArray)
        .compactMap(\.binaryDataId)
}
