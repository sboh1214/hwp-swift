@testable import CoreHwp
import Foundation
import Nimble
import XCTest

#if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
    final class FixtureFileWrapperEntrypointTests: XCTestCase {
        func testReadableFixturesLoadThroughFileWrapperEntrypoint() throws {
            let fixtures = try FixtureLoader.loadAll()
                .filter { $0.manifest.expectedError == nil }

            expect(fixtures).notTo(beEmpty())
            for fixture in fixtures {
                let wrapper = try FileWrapper(url: fixture.documentURL, options: [])
                let hwp = try HwpFile(fromWrapper: wrapper)
                let pathHwp = try HwpFile(fromPath: fixture.documentURL.path)

                expect(hwp) == pathHwp
                assertFileWrapperRawPayloads(hwp, pathHwp)
                try FixtureAssertions.assertReadableFixture(fixture, hwp)
                try assertFileWrapperEntrypoint(fixture, hwp)
            }
        }
    }

    private func assertFileWrapperRawPayloads(_ hwp: HwpFile, _ pathHwp: HwpFile) {
        expect(hwp.fileHeader.rawPayload) == pathHwp.fileHeader.rawPayload
        expect(hwp.fileHeader.reserved) == pathHwp.fileHeader.reserved
        expect(hwp.docInfo.rawPayload) == pathHwp.docInfo.rawPayload
        expect(hwp.sectionArray.map(\.rawPayload)) == pathHwp.sectionArray.map(\.rawPayload)
        expect(hwp.summary.rawPayload) == pathHwp.summary.rawPayload
        expect(hwp.previewText.rawPayload) == pathHwp.previewText.rawPayload
        expect(hwp.previewImage.rawPayload) == pathHwp.previewImage.rawPayload
        expect(hwp.binaryDataArray.map(\.name)) == pathHwp.binaryDataArray.map(\.name)
        expect(hwp.binaryDataArray.map(\.streamId)) == pathHwp.binaryDataArray.map(\.streamId)
        expect(hwp.binaryDataArray.map(\.extensionName)) ==
            pathHwp.binaryDataArray.map(\.extensionName)
        expect(hwp.binaryDataArray.map(\.data)) == pathHwp.binaryDataArray.map(\.data)
    }

    private func assertFileWrapperEntrypoint(_ fixture: LoadedFixture, _ hwp: HwpFile) throws {
        let expectations = fixture.manifest.expectations
        let expectedVersion = try FixtureVersionParser.parse(fixture.manifest.hwpVersion)

        expect(hwp.fileHeader.version) == expectedVersion
        if let sectionCount = expectations.sectionCount {
            expect(hwp.sectionArray.count) == sectionCount
        }
        if let paragraphCount = expectations.paragraphCount {
            expect(hwp.sectionArray.flatMap(\.paragraph).count) == paragraphCount
        }
        if let allParagraphCount = expectations.allParagraphCount {
            expect(FixtureDerivedValues.allParagraphs(from: hwp).count) == allParagraphCount
        }
        if let controlCount = expectations.controlCount {
            let actualControlCount = FixtureDerivedValues.controlCounts(from: hwp)
                .values
                .reduce(0, +)
            expect(actualControlCount) == controlCount
        }
        if let allControlCount = expectations.allControlCount {
            expect(FixtureDerivedValues.allControls(from: hwp).count) == allControlCount
        }
        assertFileWrapperOptionalStreams(expectations, hwp)
        assertFileWrapperBinaryData(expectations, hwp)
        if let visibleTextContains = expectations.visibleTextContains {
            let visibleText = FixtureDerivedValues.visibleText(from: hwp)
            for text in visibleTextContains {
                expect(visibleText).to(contain(text))
            }
        }
    }

    private func assertFileWrapperOptionalStreams(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        FixtureAssertions.assertPayloadSample(
            hwp.summary.rawPayload,
            length: expectations.summaryLength,
            prefix: expectations.summaryPrefixBytes,
            suffix: expectations.summarySuffixBytes
        )
        if let previewTextLength = expectations.previewTextLength {
            expect(hwp.previewText.text.count) == previewTextLength
        }
        FixtureAssertions.assertPayloadSample(
            hwp.previewText.rawPayload,
            length: expectations.previewTextRawPayloadLength,
            prefix: expectations.previewTextPrefixBytes,
            suffix: expectations.previewTextSuffixBytes
        )
        if let previewImageLength = expectations.previewImageLength {
            expect(hwp.previewImage.image.count) == previewImageLength
        }
        if let previewImageFormat = expectations.previewImageFormat {
            expect(hwp.previewImage.format) == previewImageFormat
        }
        FixtureAssertions.assertPayloadSample(
            hwp.previewImage.rawPayload,
            length: expectations.previewImageLength,
            prefix: expectations.previewImagePrefixBytes,
            suffix: expectations.previewImageSuffixBytes
        )
    }

    private func assertFileWrapperBinaryData(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
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
        FixtureAssertions.assertPayloadSamples(
            hwp.binaryDataArray.map(\.data),
            lengths: expectations.binaryDataPayloadLengths,
            prefixes: expectations.binaryDataPayloadPrefixBytes,
            suffixes: expectations.binaryDataPayloadSuffixBytes
        )
        if let binaryDataTotalByteCount = expectations.binaryDataTotalByteCount {
            expect(hwp.binaryDataArray.reduce(0) { $0 + $1.data.count }) ==
                binaryDataTotalByteCount
        }
    }
#endif
