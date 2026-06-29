import CoreHwp
import Foundation
import Nimble

extension FixtureAssertions {
    static func assertOptionalStreams(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertSummary(expectations, hwp)
        assertPreviewText(expectations, hwp)
        assertPreviewImage(expectations, hwp)
        assertBinaryData(expectations, hwp)
        assertBinaryDataStorageReferences(hwp)
    }
}

private extension FixtureAssertions {
    static func assertSummary(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        if let summaryLength = expectations.summaryLength {
            expect(hwp.summary.rawPayload.count) == summaryLength
        }
        if let summaryPrefixBytes = expectations.summaryPrefixBytes {
            let actualPrefix = Array(hwp.summary.rawPayload.prefix(summaryPrefixBytes.count))
            expect(actualPrefix) == summaryPrefixBytes
        }
        if let summarySuffixBytes = expectations.summarySuffixBytes {
            let actualSuffix = Array(hwp.summary.rawPayload.suffix(summarySuffixBytes.count))
            expect(actualSuffix) == summarySuffixBytes
        }
    }

    static func assertPreviewText(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        let rawPayload = hwp.previewText.rawPayload
        if let previewTextRawPayloadLength = expectations.previewTextRawPayloadLength {
            expect(rawPayload.count) == previewTextRawPayloadLength
        }
        if let previewTextPrefixBytes = expectations.previewTextPrefixBytes {
            let actualPrefix = Array(rawPayload.prefix(previewTextPrefixBytes.count))
            expect(actualPrefix) == previewTextPrefixBytes
        }
        if let previewTextSuffixBytes = expectations.previewTextSuffixBytes {
            let actualSuffix = Array(rawPayload.suffix(previewTextSuffixBytes.count))
            expect(actualSuffix) == previewTextSuffixBytes
        }
        if let previewTextContains = expectations.previewTextContains {
            for expectedText in previewTextContains {
                expect(hwp.previewText.text).to(contain(expectedText))
            }
        }
    }

    static func assertPreviewImage(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        let image = hwp.previewImage.image
        if let previewImageLength = expectations.previewImageLength {
            expect(image.count) == previewImageLength
        }
        if let previewImageFormat = expectations.previewImageFormat {
            expect(hwp.previewImage.format) == previewImageFormat
        }
        if let previewImagePrefixBytes = expectations.previewImagePrefixBytes {
            let actualPrefix = Array(image.prefix(previewImagePrefixBytes.count))
            expect(actualPrefix) == previewImagePrefixBytes
        }
        if let previewImageSuffixBytes = expectations.previewImageSuffixBytes {
            let actualSuffix = Array(image.suffix(previewImageSuffixBytes.count))
            expect(actualSuffix) == previewImageSuffixBytes
        }
    }

    static func assertBinaryData(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        if let binaryDataCount = expectations.binaryDataCount {
            expect(hwp.binaryDataArray.count) == binaryDataCount
        }
        if let binaryDataNames = expectations.binaryDataNames {
            expect(hwp.binaryDataArray.map(\.name)) == binaryDataNames
        }
        if let binaryDataEntryNames = expectations.binaryDataEntryNames {
            expect(hwp.binaryDataArray.map(\.name)) == binaryDataEntryNames
        }
        if let binaryDataStreamIds = expectations.binaryDataStreamIds {
            expect(hwp.binaryDataArray.map(\.streamId)) == binaryDataStreamIds
        }
        if let binaryDataExtensionNames = expectations.binaryDataExtensionNames {
            expect(hwp.binaryDataArray.map(\.extensionName)) == binaryDataExtensionNames
        }
        if let binaryDataPayloadLengths = expectations.binaryDataPayloadLengths {
            expect(hwp.binaryDataArray.map(\.data.count)) == binaryDataPayloadLengths
        }
        if let binaryDataPayloadPrefixBytes = expectations.binaryDataPayloadPrefixBytes {
            expect(binaryDataPayloadPrefixBytes.count) == hwp.binaryDataArray.count
            let actualPrefixes = zip(
                hwp.binaryDataArray,
                binaryDataPayloadPrefixBytes
            ).map { item, expectedPrefix in
                Array(item.data.prefix(expectedPrefix.count))
            }
            expect(actualPrefixes) == binaryDataPayloadPrefixBytes
        }
        if let binaryDataPayloadSuffixBytes = expectations.binaryDataPayloadSuffixBytes {
            expect(binaryDataPayloadSuffixBytes.count) == hwp.binaryDataArray.count
            let actualSuffixes = zip(
                hwp.binaryDataArray,
                binaryDataPayloadSuffixBytes
            ).map { item, expectedSuffix in
                Array(item.data.suffix(expectedSuffix.count))
            }
            expect(actualSuffixes) == binaryDataPayloadSuffixBytes
        }
        if let binaryDataTotalByteCount = expectations.binaryDataTotalByteCount {
            expect(hwp.binaryDataArray.reduce(0) { $0 + $1.data.count }) == binaryDataTotalByteCount
        }
    }

    static func assertBinaryDataStorageReferences(_ hwp: HwpFile) {
        let actualStorageNames = hwp.binaryDataArray.map(\.name).sorted()
        let docInfoStorageNames = hwp.docInfo.idMappings.binDataArray
            .compactMap(binaryDataStorageName)
            .sorted()
        expect(actualStorageNames) == docInfoStorageNames

        let actualStorageIds = Set(hwp.docInfo.idMappings.binDataArray.compactMap(\.streamId))
        expect(Set(hwp.binaryDataArray.compactMap(\.streamId))) == actualStorageIds
        let pictureBinaryDataIds = FixtureDerivedValues.allGenShapeObjects(from: hwp)
            .flatMap(\.shapeComponentArray)
            .flatMap(\.pictureArray)
            .compactMap(\.binaryDataId)
        expect(Set(pictureBinaryDataIds).isSubset(of: actualStorageIds)) == true
        let oleBinaryDataIds = FixtureDerivedValues.allGenShapeObjects(from: hwp)
            .flatMap(\.shapeComponentArray)
            .flatMap(\.oleArray)
            .compactMap(\.binaryDataId)
        let outOfRangeOleBinaryDataIds = oleBinaryDataIds.filter { $0 > UInt16.max }
        expect(outOfRangeOleBinaryDataIds).to(beEmpty())
        let normalizedOleBinaryDataIds = oleBinaryDataIds.compactMap(UInt16.init(exactly:))
        expect(Set(normalizedOleBinaryDataIds).isSubset(of: actualStorageIds)) == true
    }

    static func binaryDataStorageName(_ binData: HwpBinData) -> String? {
        guard binData.property.type == .embedding || binData.property.type == .storage,
              let streamId = binData.streamId,
              let extensionName = binData.extensionName
        else {
            return nil
        }
        return String(format: "BIN%04d.%@", streamId, extensionName)
    }
}
