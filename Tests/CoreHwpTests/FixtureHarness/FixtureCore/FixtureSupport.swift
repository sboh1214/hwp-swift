@testable import CoreHwp
import Foundation
import Nimble

enum FixtureAssertions {
    static func assert(_ fixture: LoadedFixture) throws {
        assertLayout(fixture)

        if let expectedError = fixture.manifest.expectedError {
            try assertUnsupportedFixtureHeader(fixture, expectedError)
            assertError(expectedError, fixture.documentURL)
            return
        }

        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        try assertTopLevelOptionalStreams(fixture.manifest.expectations, fixture)
        try assertReadableFixture(fixture, hwp)
    }

    static func assertReadableFixture(_ fixture: LoadedFixture, _ hwp: HwpFile) throws {
        try assertVersion(fixture.manifest.hwpVersion, hwp)
        assertFileHeader(fixture.manifest.expectations, hwp)
        assertDocumentShape(fixture.manifest.expectations, hwp)
        assertParaTextPayloads(fixture.manifest.expectations, hwp)
        assertOptionalStreams(fixture.manifest.expectations, hwp)
        assertDocInfo(fixture.manifest.expectations, hwp)
        assertDocumentProperties(fixture.manifest.expectations, hwp)
        assertCompatibleDocument(fixture.manifest.expectations, hwp)
        assertLayoutCompatibility(fixture.manifest.expectations, hwp)
        assertDocInfoIdMappings(fixture.manifest.expectations, hwp)
        assertDocInfoRawRecords(fixture.manifest.expectations, hwp)
        assertDocInfoBinData(fixture.manifest.expectations, hwp)
        assertDocInfoStyles(fixture.manifest.expectations, hwp)
        assertDocInfoNumberings(fixture.manifest.expectations, hwp)
        assertDocInfoBullets(fixture.manifest.expectations, hwp)
        assertControls(fixture.manifest.expectations, hwp)
        assertVisibleText(fixture.manifest.expectations, hwp)
    }

    static func assertSectionDefinitions(
        _ expectations: [FixtureSectionExpectations],
        _ actualSections: [HwpSectionDef]
    ) {
        assertSections(expectations, actualSections)
    }
}

private extension FixtureAssertions {
    static func assertLayout(_ fixture: LoadedFixture) {
        expect(fixture.manifest.id) == fixture.fixtureURL.lastPathComponent
        expect(FileManager.default.fileExists(atPath: fixture.documentURL.path)) == true
        expect(FileManager.default.fileExists(atPath: fixture.readmeURL.path)) == true
    }

    static func assertVersion(_ version: String, _ hwp: HwpFile) throws {
        let expectedVersion = try FixtureVersionParser.parse(version)
        expect(hwp.fileHeader.version) == expectedVersion
    }

    static func assertVersion(_ version: String, _ fileHeader: HwpFileHeader) throws {
        let expectedVersion = try FixtureVersionParser.parse(version)
        expect(fileHeader.version) == expectedVersion
    }

    static func assertUnsupportedFixtureHeader(
        _ fixture: LoadedFixture,
        _ expectedError: FixtureExpectedError
    ) throws {
        let fileHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)
        try assertVersion(fixture.manifest.hwpVersion, fileHeader)
        assertFileHeader(fixture.manifest.expectations, fileHeader)
        assertUnsupportedFeatureBit(expectedError, fileHeader.fileProperty)
        #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
            let wrapper = try FileWrapper(url: fixture.documentURL, options: [])
            let wrapperHeader = try HwpFileHeader.load(fromWrapper: wrapper)
            try assertVersion(fixture.manifest.hwpVersion, wrapperHeader)
            assertFileHeader(fixture.manifest.expectations, wrapperHeader)
            assertUnsupportedFeatureBit(expectedError, wrapperHeader.fileProperty)
        #endif
        try assertUnsupportedDocInfoRawRecords(
            fixture.manifest.expectations,
            fixture.documentURL,
            fileHeader
        )
    }

    static func assertTopLevelOptionalStreams(
        _ expectations: FixtureExpectations,
        _ fixture: LoadedFixture
    ) throws {
        let streamNames = try FixtureRawDocInfoScanner.topLevelStreamNames(in: fixture)
        let features = Set(fixture.manifest.features)

        assertRequiredTopLevelEntries(streamNames)
        assertFeatureTopLevelEntries(features, streamNames)
        if let topLevelEntryNames = expectations.topLevelEntryNames {
            expect(streamNames.sorted()) == topLevelEntryNames
        }
        let bodyTextSectionNames = try FixtureRawDocInfoScanner.storageChildNames(
            in: fixture,
            streamName: .bodyText
        )
        if let bodyTextSectionEntryNames = expectations.bodyTextSectionEntryNames {
            expect(bodyTextSectionNames) == bodyTextSectionEntryNames
        } else if let sectionCount = expectations.sectionCount {
            expect(bodyTextSectionNames) == (0 ..< sectionCount).map { "Section\($0)" }
        }
        if let binaryDataEntryNames = expectations.binaryDataEntryNames {
            let actual = try FixtureRawDocInfoScanner.storageChildNames(
                in: fixture,
                streamName: .binData
            )
            expect(actual) == binaryDataEntryNames
        }

        guard let previewImageLength = expectations.previewImageLength else {
            return
        }
        if previewImageLength == 0,
           expectations.previewImageFormat == HwpPreviewImageFormat.none
        {
            expect(streamNames).notTo(contain(HwpStreamName.previewImage.rawValue))
        } else {
            expect(streamNames).to(contain(HwpStreamName.previewImage.rawValue))
        }
    }

    static func assertRequiredTopLevelEntries(_ streamNames: Set<String>) {
        for streamName in HwpStreamName.requiredTopLevelEntries {
            expect(streamNames).to(contain(streamName.rawValue))
        }
    }

    static func assertFeatureTopLevelEntries(
        _ features: Set<String>,
        _ streamNames: Set<String>
    ) {
        if features.contains("preview-text") {
            expect(streamNames).to(contain(HwpStreamName.previewText.rawValue))
        }
        if features.contains("derived-missing-summary") {
            expect(streamNames).notTo(contain(HwpStreamName.summary.rawValue))
            expect(streamNames).to(contain("\u{5}XwpSummaryInformation"))
        }
        if features.contains("derived-missing-preview-text") {
            expect(streamNames).notTo(contain(HwpStreamName.previewText.rawValue))
            expect(streamNames).to(contain("XrvText"))
        }
        if features.contains("preview-image") {
            expect(streamNames).to(contain(HwpStreamName.previewImage.rawValue))
        }
        if features.contains("bin-data") {
            expect(streamNames).to(contain(HwpStreamName.binData.rawValue))
        }
        if features.contains("missing-bin-data") {
            expect(streamNames).notTo(contain(HwpStreamName.binData.rawValue))
        }
    }
}

private extension FixtureAssertions {
    static func assertDocumentShape(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        expect(hwp.sectionArray.count) == Int(hwp.docInfo.documentProperties.sectionSize)
        if let sectionCount = expectations.sectionCount {
            expect(hwp.sectionArray.count) == sectionCount
        }
        let sectionRawPayloads = FixtureDerivedValues.sectionRawPayloads(from: hwp)
        if let sectionRawPayloadCount = expectations.sectionRawPayloadCount {
            expect(sectionRawPayloads.count) == sectionRawPayloadCount
        }
        if let sectionRawPayloadTotalByteCount = expectations.sectionRawPayloadTotalByteCount {
            expect(sectionRawPayloads.reduce(0) { $0 + $1.count }) ==
                sectionRawPayloadTotalByteCount
        }
        assertPayloadSamples(
            sectionRawPayloads,
            lengths: nil,
            prefixes: expectations.sectionRawPayloadPrefixBytes,
            suffixes: expectations.sectionRawPayloadSuffixBytes
        )
        if let sectionParagraphCounts = expectations.sectionParagraphCounts {
            expect(hwp.sectionArray.map(\.paragraph.count)) == sectionParagraphCounts
        }
        if let sectionVisibleTexts = expectations.sectionVisibleTexts {
            expect(FixtureDerivedValues.visibleTextsBySection(from: hwp)) == sectionVisibleTexts
        }
        if let paragraphCount = expectations.paragraphCount {
            expect(hwp.sectionArray.flatMap(\.paragraph).count) == paragraphCount
        }
        if let allParagraphCount = expectations.allParagraphCount {
            expect(FixtureDerivedValues.allParagraphs(from: hwp).count) == allParagraphCount
        }
        assertSectionUnknownRecords(expectations, hwp.sectionArray)
        if let previewTextLength = expectations.previewTextLength {
            expect(hwp.previewText.text.count) == previewTextLength
        }
    }
}

private extension FixtureAssertions {
    static func assertControls(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        assertControlCounts(expectations, hwp)
        assertDocumentObjectControls(expectations, hwp)
        assertDocumentMetadataControls(expectations, hwp)
    }

    static func assertDocumentObjectControls(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        if let hyperlinks = expectations.hyperlinks {
            assertHyperlinks(hyperlinks, hwp)
        }
        if let genShapeObjects = expectations.genShapeObjects {
            assertGenShapeObjects(genShapeObjects, hwp)
        }
        if let shapeControls = expectations.shapeControls {
            assertShapeControls(shapeControls, hwp)
        }
        if let tables = expectations.tables {
            assertTables(tables, hwp)
        }
        if let columns = expectations.columns {
            assertColumns(columns, hwp)
        }
        if let listControls = expectations.listControls {
            assertListControls(listControls, hwp)
        }
    }

    static func assertDocumentMetadataControls(
        _ expectations: FixtureExpectations,
        _ hwp: HwpFile
    ) {
        if let pageNumberPositions = expectations.pageNumberPositions {
            assertPageNumberPositions(pageNumberPositions, hwp)
        }
        if let sections = expectations.sections {
            assertSections(sections, hwp)
        }
        if let preservedControls = expectations.preservedControls {
            assertPreservedControls(preservedControls, hwp)
        } else if expectations.preservedControlSamples == nil {
            expect(FixtureDerivedValues.preservedControls(from: hwp)).to(beEmpty())
        }
        if let preservedControlSamples = expectations.preservedControlSamples {
            assertPreservedControlSamples(preservedControlSamples, hwp)
        }
        if let fieldControls = expectations.fieldControls {
            assertFieldControls(fieldControls, hwp)
        }
        if let otherControls = expectations.otherControls {
            assertOtherControls(otherControls, hwp)
        }
        if let otherControlSamples = expectations.otherControlSamples {
            assertOtherControlSamples(otherControlSamples, hwp)
        }
    }

    static func assertControlCounts(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        if let controlCount = expectations.controlCount {
            let actual = hwp.sectionArray
                .flatMap(\.paragraph)
                .compactMap(\.ctrlHeaderArray)
                .reduce(0) { $0 + $1.count }
            expect(actual) == controlCount
        }
        if let allControlCount = expectations.allControlCount {
            expect(FixtureDerivedValues.allControls(from: hwp).count) == allControlCount
        }
        if let controlTypeCounts = expectations.controlTypeCounts {
            expect(FixtureDerivedValues.controlCounts(from: hwp)) == controlTypeCounts
        }
        if let allControlTypeCounts = expectations.allControlTypeCounts {
            expect(FixtureDerivedValues.allControlCounts(from: hwp)) == allControlTypeCounts
        }
    }

    static func assertTables(_ expectations: [FixtureTableExpectations], _ hwp: HwpFile) {
        let actualTables = FixtureDerivedValues.tables(from: hwp)
        assertTables(expectations, actualTables)
    }

    static func assertColumns(_ expectations: [FixtureColumnExpectations], _ hwp: HwpFile) {
        let actualColumns = FixtureDerivedValues.columns(from: hwp)
        assertColumns(expectations, actualColumns)
    }

    static func assertPageNumberPositions(
        _ expectations: [FixturePageNumberPositionExpectations],
        _ hwp: HwpFile
    ) {
        let actualPositions = FixtureDerivedValues.pageNumberPositions(from: hwp)
        assertPageNumberPositions(expectations, actualPositions)
    }

    static func assertSections(_ expectations: [FixtureSectionExpectations], _ hwp: HwpFile) {
        let actualSections = FixtureDerivedValues.sectionDefinitions(from: hwp)
        assertSections(expectations, actualSections)
    }

    static func assertSections(
        _ expectations: [FixtureSectionExpectations],
        _ actualSections: [HwpSectionDef]
    ) {
        expect(actualSections.count) == expectations.count

        for (actual, expected) in zip(actualSections, expectations) {
            if let rawPayloadLength = expected.rawPayloadLength {
                expect(actual.rawPayload.count) == rawPayloadLength
            }
            if let propertyRawValue = expected.propertyRawValue {
                expect(actual.property) == propertyRawValue
            }
            assertPageDef(actual.pageDef, expected)
            assertFootnoteShapes(actual, expected)
            assertPageBorderFills(actual, expected)
            assertSectionDefUnknownChildren(actual, expected)
        }
    }

    static func assertPageDef(
        _ actual: HwpPageDef,
        _ expected: FixtureSectionExpectations
    ) {
        if let pageDefPropertyRawValue = expected.pageDefPropertyRawValue {
            expect(actual.property) == pageDefPropertyRawValue
        }
        assertPayloadSample(
            actual.rawPayload,
            length: expected.pageDefRawPayloadLength,
            prefix: expected.pageDefRawPayloadPrefixBytes,
            suffix: expected.pageDefRawPayloadSuffixBytes
        )
        assertPayloadSample(
            actual.rawTrailing,
            length: expected.pageDefRawTrailingLength,
            prefix: expected.pageDefRawTrailingPrefixBytes,
            suffix: expected.pageDefRawTrailingSuffixBytes
        )
    }

    static func assertFootnoteShapes(
        _ actual: HwpSectionDef,
        _ expected: FixtureSectionExpectations
    ) {
        if let footNoteShapePropertyRawValue = expected.footNoteShapePropertyRawValue {
            expect(actual.footNoteShape.property) == footNoteShapePropertyRawValue
        }
        assertPayloadSample(
            actual.footNoteShape.rawPayload,
            length: expected.footNoteShapeRawPayloadLength,
            prefix: expected.footNoteShapeRawPayloadPrefixBytes,
            suffix: expected.footNoteShapeRawPayloadSuffixBytes
        )
        assertPayloadSample(
            actual.footNoteShape.rawTrailing,
            length: expected.footNoteShapeRawTrailingLength,
            prefix: expected.footNoteShapeRawTrailingPrefixBytes,
            suffix: expected.footNoteShapeRawTrailingSuffixBytes
        )
        assertFootnoteShapeSymbolRawFields(
            actual.footNoteShape,
            rawValues: expected.footNoteShapeSymbolRawValues,
            payloadLengths: expected.footNoteShapeSymbolRawPayloadLengths,
            payloadPrefixes: expected.footNoteShapeSymbolRawPayloadPrefixBytes,
            payloadSuffixes: expected.footNoteShapeSymbolRawPayloadSuffixBytes
        )
        if let endNoteShapePropertyRawValue = expected.endNoteShapePropertyRawValue {
            expect(actual.endNoteShape.property) == endNoteShapePropertyRawValue
        }
        assertPayloadSample(
            actual.endNoteShape.rawPayload,
            length: expected.endNoteShapeRawPayloadLength,
            prefix: expected.endNoteShapeRawPayloadPrefixBytes,
            suffix: expected.endNoteShapeRawPayloadSuffixBytes
        )
        assertPayloadSample(
            actual.endNoteShape.rawTrailing,
            length: expected.endNoteShapeRawTrailingLength,
            prefix: expected.endNoteShapeRawTrailingPrefixBytes,
            suffix: expected.endNoteShapeRawTrailingSuffixBytes
        )
        assertFootnoteShapeSymbolRawFields(
            actual.endNoteShape,
            rawValues: expected.endNoteShapeSymbolRawValues,
            payloadLengths: expected.endNoteShapeSymbolRawPayloadLengths,
            payloadPrefixes: expected.endNoteShapeSymbolRawPayloadPrefixBytes,
            payloadSuffixes: expected.endNoteShapeSymbolRawPayloadSuffixBytes
        )
    }

    static func assertFootnoteShapeSymbolRawFields(
        _ actual: HwpFootnoteShape,
        rawValues: [UInt16]?,
        payloadLengths: [Int]?,
        payloadPrefixes: [[UInt8]]?,
        payloadSuffixes: [[UInt8]]?
    ) {
        let actualPayloads = [
            actual.userSymbolRawPayload,
            actual.decorationHeadRawPayload,
            actual.decorationTailRawPayload,
        ]
        if let rawValues {
            expect([
                actual.userSymbolRawValue,
                actual.decorationHeadRawValue,
                actual.decorationTailRawValue,
            ]) == rawValues
        }
        assertPayloadSamples(
            actualPayloads,
            lengths: payloadLengths,
            prefixes: payloadPrefixes,
            suffixes: payloadSuffixes
        )
    }

    static func assertPageBorderFills(
        _ actual: HwpSectionDef,
        _ expected: FixtureSectionExpectations
    ) {
        let payloads = [
            actual.pageBorderFillBoth.rawPayload,
            actual.pageBorderFillEven.rawPayload,
            actual.pageBorderFillOdd.rawPayload,
        ]
        let trailingPayloads = [
            actual.pageBorderFillBoth.rawTrailing,
            actual.pageBorderFillEven.rawTrailing,
            actual.pageBorderFillOdd.rawTrailing,
        ]
        if let pageBorderFillPropertyRawValues = expected.pageBorderFillPropertyRawValues {
            expect([
                actual.pageBorderFillBoth.property,
                actual.pageBorderFillEven.property,
                actual.pageBorderFillOdd.property,
            ]) == pageBorderFillPropertyRawValues
        }
        assertPayloadSamples(
            payloads,
            lengths: expected.pageBorderFillRawPayloadLengths,
            prefixes: expected.pageBorderFillRawPayloadPrefixBytes,
            suffixes: expected.pageBorderFillRawPayloadSuffixBytes
        )
        assertPayloadSamples(
            trailingPayloads,
            lengths: expected.pageBorderFillRawTrailingLengths,
            prefixes: expected.pageBorderFillRawTrailingPrefixBytes,
            suffixes: expected.pageBorderFillRawTrailingSuffixBytes
        )
    }

    static func assertSectionDefUnknownChildren(
        _ actual: HwpSectionDef,
        _ expected: FixtureSectionExpectations
    ) {
        if let unknownChildCount = expected.unknownChildCount {
            expect(actual.unknownChildren.count) == unknownChildCount
        }
        assertUnknownRecordSamples(
            actual.unknownChildren,
            rootLevel: 2,
            expectations: FixtureUnknownRecordSampleExpectations(
                tagIds: expected.unknownChildTagIds,
                payloadLengths: expected.unknownChildPayloadLengths,
                payloadPrefixes: expected.unknownChildPayloadPrefixBytes,
                payloadSuffixes: expected.unknownChildPayloadSuffixBytes,
                childTagIds: expected.unknownChildChildTagIds,
                childPayloadLengths: expected.unknownChildChildPayloadLengths,
                childPayloadPrefixes: expected.unknownChildChildPayloadPrefixBytes,
                childPayloadSuffixes: expected.unknownChildChildPayloadSuffixBytes
            )
        )
    }
}

private extension FixtureAssertions {
    static func assertVisibleText(_ expectations: FixtureExpectations, _ hwp: HwpFile) {
        if let visibleTextContains = expectations.visibleTextContains {
            let actual = FixtureDerivedValues.visibleText(from: hwp)
            for expected in visibleTextContains {
                expect(actual).to(contain(expected))
            }
        }
    }
}
