@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpFileBinaryDataAssemblyTests: XCTestCase {
    func testActualBinaryDataStreamsLoadNamesIdsExtensionsAndPayloads() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)

        expect(hwp.binaryDataArray.count) == 3
        expect(hwp.binaryDataArray.map(\.name)) == [
            "BIN0001.png",
            "BIN0002.jpeg",
            "BIN0003.gif",
        ]
        expect(hwp.binaryDataArray.map(\.streamId)) == [1, 2, 3]
        expect(hwp.binaryDataArray.map(\.extensionName)) == ["png", "jpeg", "gif"]
        expect(hwp.binaryDataArray.map(\.data.count)) == [62875, 51551, 20462]
        expect(hwp.docInfo.idMappings.binDataArray.map(\.streamId)) == [1, 2, 3]
        expect(hwp.docInfo.idMappings.binDataArray.map(\.extensionName)) == [
            "png",
            "jpeg",
            "gif",
        ]
    }

    func testActualImageBinaryDataReferencesMatchDocInfoAndPictures() throws {
        let hwp = try HwpFile(fromPath: hwpURL(#file, "BinData").path)

        let actualStreamIds = Set(hwp.binaryDataArray.compactMap(\.streamId))
        let docInfoStreamIds = Set(hwp.docInfo.idMappings.binDataArray.compactMap(\.streamId))
        let pictureIds = pictureBinaryDataIds(from: hwp)

        expect(actualStreamIds) == Set([1, 2, 3])
        expect(docInfoStreamIds) == actualStreamIds
        expect(Set(pictureIds)) == actualStreamIds
        expect(pictureIds) == [1, 2, 3]
    }

    func testBinaryDataCompressionMapSkipsUnnumberedStreamsAndHonorsAlwaysCompress() throws {
        let docInfo = try docInfoWithBinData([
            linkBinDataPayload(),
            storageBinDataPayload(streamId: 7, compressType: .always, extensionName: "ole"),
        ])

        let compressionByStreamId = HwpFile.binaryDataCompressionByStreamId(
            docInfo: docInfo,
            storageIsCompressed: false
        )

        expect(compressionByStreamId) == [7: true]
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

    func testUnrecognizedBinaryDataStreamNameIsPreservedOnLoad() throws {
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

        expect(hwp.binaryDataArray.map(\.name)) == [
            "BIN0001.png",
            "BIN0003.gif",
            "bin0002.jpeg",
        ]
        guard let renamed = hwp.binaryDataArray.first(
            where: { $0.name == "bin0002.jpeg" }
        ) else {
            return fail("Expected renamed BinData stream to be preserved on load")
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
    expect(Set(pictureBinaryDataIds(from: actual))) ==
        Set(actual.binaryDataArray.compactMap(\.streamId))
    expect(pictureBinaryDataIds(from: actual)) ==
        pictureBinaryDataIds(from: expected)
}

private func pictureBinaryDataIds(from hwp: HwpFile) -> [UInt16] {
    FixtureDerivedValues.allGenShapeObjects(from: hwp)
        .flatMap(\.shapeComponentArray)
        .flatMap(\.pictureArray)
        .compactMap(\.binaryDataId)
}

private func docInfoWithBinData(_ binDataPayloadArray: [Data]) throws -> HwpDocInfo {
    var docInfoData = concatenatedData(
        SectionRecordBuilder.record(
            tagId: HwpDocInfoTag.documentProperties.rawValue,
            level: 0,
            payload: concatenatedData(
                binaryDataAssemblyLittleEndianData(UInt16(1)),
                Data(repeating: 0, count: 24)
            )
        ),
        SectionRecordBuilder.record(
            tagId: HwpDocInfoTag.idMappings.rawValue,
            level: 0,
            payload: binaryDataAssemblyIdMappingsPayload(
                binaryDataCount: Int32(binDataPayloadArray.count)
            )
        )
    )
    for payload in binDataPayloadArray {
        docInfoData.append(SectionRecordBuilder.record(
            tagId: HwpDocInfoTag.binData.rawValue,
            level: 1,
            payload: payload
        ))
    }
    return try HwpDocInfo.load(docInfoData, HwpFileHeader().version)
}

private func binaryDataAssemblyIdMappingsPayload(binaryDataCount: Int32) -> Data {
    var counts = [Int32](repeating: 0, count: 18)
    counts[0] = binaryDataCount
    return counts.reduce(into: Data()) { data, count in
        data.append(binaryDataAssemblyLittleEndianData(count))
    }
}

private func linkBinDataPayload() -> Data {
    concatenatedData(
        binaryDataAssemblyLittleEndianData(UInt16(HwpBinDataType.link.rawValue)),
        binaryDataAssemblyLittleEndianData(WORD(0)),
        binaryDataAssemblyLittleEndianData(WORD(0))
    )
}

private func storageBinDataPayload(
    streamId: UInt16,
    compressType: HwpBinDataCompressType,
    extensionName: String
) -> Data {
    let property = UInt16(HwpBinDataType.storage.rawValue)
        | UInt16(compressType.rawValue << 4)
        | UInt16(HwpBinDataState.never.rawValue << 6)
    return concatenatedData(
        binaryDataAssemblyLittleEndianData(property),
        binaryDataAssemblyLittleEndianData(streamId),
        binaryDataAssemblyUTF16LengthPrefixedString(extensionName)
    )
}

private func binaryDataAssemblyUTF16LengthPrefixedString(_ string: String) -> Data {
    var data = binaryDataAssemblyLittleEndianData(UInt16(string.utf16.count))
    for codeUnit in string.utf16 {
        data.append(binaryDataAssemblyLittleEndianData(UInt16(codeUnit)))
    }
    return data
}

private func binaryDataAssemblyLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
