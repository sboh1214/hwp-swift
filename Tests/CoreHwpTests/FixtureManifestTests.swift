// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

// swiftlint:disable:next type_body_length
final class FixtureManifestTests: XCTestCase {
    func testReadmeDocumentsReaderSupportAndKnownGaps() throws {
        let readmeURL = FixtureLoader.root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        expect(readme).to(contain("## 지원 범위"))
        expect(readme).to(contain("`HwpError`"))
        expect(readme).to(contain("raw payload"))
        expect(readme).to(contain("payload prefix/suffix bytes"))
        expect(readme).to(contain("`DISTRIBUTE_DOC_DATA`"))
        expect(readme).to(contain("DocInfo `TRACK_CHANGE`는 `noori` fixture"))
        expect(readme).to(contain("DRM unsupported"))
        expect(readme).to(contain("## Fixture 기준"))
    }

    func testFixtureManifests() throws {
        let fixtures = try FixtureLoader.loadAll()

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            try FixtureAssertions.assert(fixture)
        }
    }

    func testFixtureArtifactsExistAndReadmesDescribeRegeneration() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            expect(fixture.manifest.id) == fixture.fixtureURL.lastPathComponent
            expect(FixtureVersionParser.isValid(fixture.manifest.hwpVersion)) == true

            for url in fixtureArtifactURLs(fixture) {
                try assertNonEmptyRegularFile(url)
            }
            try assertOleCompoundDocumentMagic(fixture.documentURL)

            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)
            expect(readme).to(contain("# \(fixture.manifest.id)"))
            expect(readme).to(contain("`document.hwp`"))
            expect(readme).to(contain("재생성"))
            expect(readmeDocumentsVerificationTarget(readme)).to(
                beTrue(),
                description:
                "\(fixture.manifest.id) README must mention manifest/error expectation updates"
            )
        }
    }

    func testUnsupportedFixtureReadmesDeclareExpectedErrorCodes() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError != nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            guard let expectedError = fixture.manifest.expectedError else {
                return fail("Expected unsupported fixture to declare expectedError")
            }
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)
            expect(readme).to(contain(expectedError.code))
        }
    }

    func testFixtureDirectoriesUseCanonicalArtifactLayout() throws {
        let fixtures = try FixtureLoader.loadAll()
        let expectedArtifactNames = Set(["document.hwp", "manifest.json", "README.md"])

        for fixture in fixtures {
            let artifactNames = try visibleDirectoryEntryNames(at: fixture.fixtureURL)
            expect(Set(artifactNames)) == expectedArtifactNames
        }
    }

    func testAllRepositoryHwpFilesAreUnderCanonicalFixtureDirectories() throws {
        let hwpURLs = try hwpFixtureURLsUnderProjectRoot()
        let fixturesRoot = FixtureLoader.root.standardizedFileURL.path + "/"

        expect(hwpURLs).notTo(beEmpty())
        for hwpURL in hwpURLs {
            let standardizedPath = hwpURL.standardizedFileURL.path
            expect(standardizedPath).to(
                beginWith(fixturesRoot),
                description: "\(standardizedPath) is outside Tests/CoreHwpTests/Fixtures"
            )
            expect(hwpURL.lastPathComponent) == "document.hwp"
            expect(hwpURL.deletingLastPathComponent().deletingLastPathComponent()) ==
                FixtureLoader.root
        }
    }

    func testFixtureMetadataIsCompleteAndConsistent() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            expect(fixture.manifest.generationTool).notTo(beEmpty())
            expect(fixture.manifest.source).notTo(beEmpty())
            expect(fixture.manifest.features).notTo(beEmpty())
            expect(fixture.manifest.expectations.fileProperty?.rawValue).notTo(beNil())
            expect(fixture.manifest.expectations.fileLicense?.rawValue).notTo(beNil())
            expect(fixture.manifest.expectations.fileHeaderVersionRawBytes).notTo(beNil())

            let features = Set(fixture.manifest.features)
            if let expectedError = fixture.manifest.expectedError {
                expect(features).to(contain("unsupported"))
                expect(expectedError.description).notTo(beEmpty())
                assertUnsupportedFeature(expectedError, isDeclaredIn: features)
                assertUnsupportedFileProperty(
                    expectedError,
                    fixture.manifest.expectations.fileProperty
                )
                assertFileHeaderPayloadSamples(fixture.manifest.expectations)
            } else {
                expect(features).notTo(contain("unsupported"))
                assertFileHeaderPayloadSamples(fixture.manifest.expectations)
                assertSupportedFixtureCorePayloadSamples(
                    fixture.manifest.expectations,
                    features
                )
                assertDocInfoRawRecordCountMatchesDetailedExpectations(
                    fixture.manifest.expectations
                )
                assertControlCountExpectationsAreInternallyConsistent(
                    fixture.manifest.expectations
                )
            }
        }
    }

    func testFixtureFeatureTagsAreUniqueAndCanonical() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let features = fixture.manifest.features
            expect(Set(features).count) == features.count
            for feature in features {
                expect(isCanonicalFeatureTag(feature)) == true
                let description = "\(fixture.manifest.id) uses unknown feature tag \(feature)"
                expect(knownFixtureFeatureTags).to(
                    contain(feature),
                    description: description
                )
            }
        }
    }

    func testFileHeaderFeatureSpecificExpectationsAreDeclared() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let features = Set(fixture.manifest.features)
            let expectations = fixture.manifest.expectations
            let fileProperty = expectations.fileProperty

            if features.contains("document-history") {
                expect(fileProperty?.doesHaveDocumentHistory) == true
            }
            if features.contains("track-changes") {
                expect(fileProperty?.isTracingChange) == true
            }
            if features.contains("track-changes-flag") {
                expect(fileProperty?.isTracingChange).notTo(beNil())
            }
            if features.contains("encrypted") {
                expect(
                    fileProperty?.isEncrypted == true ||
                        fileProperty?.doesEncryptAccreditedCertificate == true
                ) == true
            }
            if features.contains("deployment-document") {
                expect(fileProperty?.isDeploymentDocument) == true
            }
            if features.contains("drm") {
                expect(
                    fileProperty?.isDRMDocument == true ||
                        fileProperty?.isAccreditedCertificateDRMDocument == true
                ) == true
            }
            if features.contains("kogl") {
                assertKoglFeatureExpectations(expectations)
            }
            if features.contains("license") {
                assertLicenseFeatureExpectations(expectations)
            }
        }
    }

    func testStreamAndDocInfoFeatureSpecificExpectationsAreDeclared() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let features = Set(fixture.manifest.features)
            let expectations = fixture.manifest.expectations

            assertDocInfoFeatureExpectations(features, expectations)
            assertStreamFeatureExpectations(features, expectations)
        }
    }

    func testBodyFeatureSpecificExpectationsAreDeclared() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let features = Set(fixture.manifest.features)
            let expectations = fixture.manifest.expectations

            assertTextBodyFeatureExpectations(features, expectations)
            assertControlBodyFeatureExpectations(features, expectations)
            assertOtherControlBodyFeatureExpectations(features, expectations)
            assertObjectBodyFeatureExpectations(features, expectations)
            assertUnknownControlPreservationExpectations(expectations)
        }
    }

    func testReadableControlManifestsDeclareTypeCountsAndNestedCoverage() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        for fixture in fixtures {
            let expectations = fixture.manifest.expectations
            guard (expectations.controlCount ?? 0) > 0 else {
                continue
            }

            expect(expectations.controlTypeCounts).notTo(
                beNil(),
                description:
                "\(fixture.manifest.id) declares controlCount but omits controlTypeCounts"
            )

            guard expectations.allControlTypeCounts == nil else {
                continue
            }

            let hwp = try HwpFile(fromPath: fixture.documentURL.path)
            expect(FixtureDerivedValues.allControlCounts(from: hwp)).to(
                equal(FixtureDerivedValues.controlCounts(from: hwp)),
                description:
                "\(fixture.manifest.id) has nested controls but omits allControlTypeCounts"
            )
        }
    }

    func testReadableParagraphManifestsDeclareConsistentCounts() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        for fixture in fixtures {
            let expectations = fixture.manifest.expectations

            if let sectionCount = expectations.sectionCount,
               let sectionParagraphCounts = expectations.sectionParagraphCounts
            {
                expect(sectionParagraphCounts.count).to(
                    equal(sectionCount),
                    description:
                    "\(fixture.manifest.id) sectionParagraphCounts must match sectionCount"
                )
            }

            if let paragraphCount = expectations.paragraphCount,
               let sectionParagraphCounts = expectations.sectionParagraphCounts
            {
                expect(sectionParagraphCounts.reduce(0, +)).to(
                    equal(paragraphCount),
                    description:
                    "\(fixture.manifest.id) sectionParagraphCounts must sum to paragraphCount"
                )
            }

            if let allParagraphCount = expectations.allParagraphCount,
               let paragraphCount = expectations.paragraphCount
            {
                expect(allParagraphCount).to(
                    beGreaterThanOrEqualTo(paragraphCount),
                    description:
                    "\(fixture.manifest.id) allParagraphCount must include body paragraphs"
                )
            }

            assertParagraphPayloadCountsAreInternallyConsistent(
                expectations,
                fixture.manifest.id
            )
        }
    }

    func testReadableFixtureManifestsDeclareSemanticReaderExpectations() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        for fixture in fixtures {
            let expectations = fixture.manifest.expectations
            expect(expectations.sectionCount).notTo(
                beNil(),
                description: "\(fixture.manifest.id) must declare sectionCount"
            )
            expect(expectations.sectionCount ?? 0).to(
                beGreaterThan(0),
                description: "\(fixture.manifest.id) must include at least one section"
            )
            expect(expectations.paragraphCount ?? expectations.allParagraphCount).notTo(
                beNil(),
                description:
                "\(fixture.manifest.id) must declare paragraphCount or allParagraphCount"
            )
            expect(expectations.paragraphCount ?? expectations.allParagraphCount ?? 0).to(
                beGreaterThan(0),
                description: "\(fixture.manifest.id) must include paragraph expectations"
            )
            expect(expectations.controlCount ?? expectations.allControlCount).notTo(
                beNil(),
                description: "\(fixture.manifest.id) must declare controlCount or allControlCount"
            )
            expect(expectations.controlCount ?? expectations.allControlCount ?? 0).to(
                beGreaterThan(0),
                description: "\(fixture.manifest.id) must include control expectations"
            )
        }
    }

    func testUnsupportedFixtureManifestsDoNotDeclareReadableBodyExpectations() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError != nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let expectations = fixture.manifest.expectations
            expect(expectations.sectionCount).to(
                beNil(),
                description: "\(fixture.manifest.id) unsupported fixture must not be readable"
            )
            expect(expectations.paragraphCount ?? expectations.allParagraphCount).to(
                beNil(),
                description:
                "\(fixture.manifest.id) unsupported fixture must not declare paragraph coverage"
            )
            expect(expectations.controlCount ?? expectations.allControlCount).to(
                beNil(),
                description:
                "\(fixture.manifest.id) unsupported fixture must not declare control coverage"
            )
            expect(expectations.visibleTextContains).to(
                beNil(),
                description:
                "\(fixture.manifest.id) unsupported fixture must not declare visible text"
            )
        }
    }

    func testUnsupportedFixtureManifestsOnlyClaimUnsupportedFeatureTags() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError != nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            guard let expectedError = fixture.manifest.expectedError else {
                return fail("Expected unsupported fixture to declare expectedError")
            }

            let features = Set(fixture.manifest.features)
            let unsupportedFeature = unsupportedFeatureTag(for: expectedError.code)
            let allowedFeatures = allowedUnsupportedFeatureTags(for: unsupportedFeature)
            let unexpectedFeatures = features.subtracting(allowedFeatures)

            expect(features).to(
                contain("unsupported"),
                description: "\(fixture.manifest.id) must declare unsupported"
            )
            expect(features).to(
                contain(unsupportedFeature),
                description: "\(fixture.manifest.id) must declare \(unsupportedFeature)"
            )
            expect(unexpectedFeatures.sorted()).to(
                beEmpty(),
                description:
                "\(fixture.manifest.id) unsupported fixture must not claim readable features"
            )
        }
    }

    func testReadableFixtureManifestsDoNotClaimUnsupportedOnlyFeatureTags() throws {
        let fixtures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }

        expect(fixtures).notTo(beEmpty())
        for fixture in fixtures {
            let unsupportedOnlyFeatures = Set(fixture.manifest.features)
                .intersection(unsupportedOnlyFeatureTags)
            expect(unsupportedOnlyFeatures.sorted()).to(
                beEmpty(),
                description:
                "\(fixture.manifest.id) readable fixture must not claim unsupported-only features"
            )
        }
    }

    func testFixtureSuiteCoversCurrentReaderGoalFeatureTags() throws {
        let coveredFeatures = try FixtureLoader.loadAll()
            .reduce(into: Set<String>()) { result, fixture in
                result.formUnion(fixture.manifest.features)
            }

        for feature in currentReaderGoalFixtureFeatureTags {
            expect(coveredFeatures).to(contain(feature))
        }
    }

    func testFixtureVersionParserRejectsInvalidVersionsWithTypedError() {
        for version in [
            "1.2.3",
            "1.two.3.4",
            "1.2.bad.3.4",
            "1..2.3.4",
            ".1.2.3.4",
            "1.2.3.4.",
            "999.0.0.0",
            "-1.0.0.0",
        ] {
            expect {
                _ = try FixtureVersionParser.parse(version)
            }.to(throwError { error in
                guard case HwpError.invalidDataForString = error else {
                    return fail("Expected invalidDataForString, got \(error)")
                }
            })
        }
    }
}

private func visibleDirectoryEntryNames(at directoryURL: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    .map(\.lastPathComponent)
    .sorted()
}

private func readmeDocumentsVerificationTarget(_ readme: String) -> Bool {
    readme.contains("manifest.json") ||
        readme.contains("기대값") ||
        readme.contains("expectedError") ||
        readme.contains("검증")
}

private func hwpFixtureURLsUnderProjectRoot() throws -> [URL] {
    let projectRoot = testsRoot(from: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(
        at: projectRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    var urls = [URL]()

    while let url = enumerator?.nextObject() as? URL {
        let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
        if resourceValues.isRegularFile == true, url.pathExtension == "hwp" {
            urls.append(url)
        }
    }

    return urls.sorted { $0.path < $1.path }
}

private let unsupportedOnlyFeatureTags = Set([
    "deployment-document",
    "derived-drm",
    "drm",
    "encrypted",
])

private var currentReaderGoalFixtureFeatureTags: Set<String> {
    readableReaderGoalFeatureTags.union(unsupportedOnlyFeatureTags)
}

private func unsupportedFeatureTag(for expectedErrorCode: String) -> String {
    switch expectedErrorCode {
    case "unsupportedFeature.encryptedDocument":
        return "encrypted"
    case "unsupportedFeature.deploymentDocument":
        return "deployment-document"
    case "unsupportedFeature.drmDocument":
        return "drm"
    default:
        fail("Unknown unsupported fixture error code: \(expectedErrorCode)")
        return "unsupported"
    }
}

private func allowedUnsupportedFeatureTags(for unsupportedFeature: String) -> Set<String> {
    var allowedFeatures = Set(["unsupported", unsupportedFeature])
    if unsupportedFeature == "drm" {
        allowedFeatures.insert("derived-drm")
    }
    return allowedFeatures
}

private func assertUnsupportedFeature(
    _ expectedError: FixtureExpectedError,
    isDeclaredIn features: Set<String>
) {
    let expectedDescription: String
    switch expectedError.code {
    case "unsupportedFeature.encryptedDocument":
        expect(features).to(contain("encrypted"))
        expectedDescription = HwpError.unsupportedFeature(.encryptedDocument).description
    case "unsupportedFeature.deploymentDocument":
        expect(features).to(contain("deployment-document"))
        expectedDescription = HwpError.unsupportedFeature(.deploymentDocument).description
    case "unsupportedFeature.drmDocument":
        expect(features).to(contain("drm"))
        expectedDescription = HwpError.unsupportedFeature(.drmDocument).description
    default:
        fail("Unknown unsupported fixture error code: \(expectedError.code)")
        return
    }
    expect(expectedError.description) == expectedDescription
}

private func assertUnsupportedFileProperty(
    _ expectedError: FixtureExpectedError,
    _ fileProperty: FixtureFilePropertyExpectations?
) {
    guard let fileProperty else {
        return fail("Unsupported fixture expected fileProperty to be declared")
    }

    assertUnsupportedFilePropertySecurityBitsAreDeclared(fileProperty)
    let feature = unsupportedFeature(from: fileProperty)
    switch expectedError.code {
    case "unsupportedFeature.encryptedDocument":
        expect(feature) == .encryptedDocument
    case "unsupportedFeature.deploymentDocument":
        expect(feature) == .deploymentDocument
    case "unsupportedFeature.drmDocument":
        expect(feature) == .drmDocument
    default:
        fail("Unknown unsupported fixture error code: \(expectedError.code)")
    }
}

private func unsupportedFeature(
    from fileProperty: FixtureFilePropertyExpectations
) -> HwpUnsupportedFeature? {
    if fileProperty.isEncrypted == true ||
        fileProperty.doesEncryptAccreditedCertificate == true
    {
        return .encryptedDocument
    }
    if fileProperty.isDeploymentDocument == true {
        return .deploymentDocument
    }
    if fileProperty.isDRMDocument == true ||
        fileProperty.isAccreditedCertificateDRMDocument == true
    {
        return .drmDocument
    }
    return nil
}

private func assertUnsupportedFilePropertySecurityBitsAreDeclared(
    _ fileProperty: FixtureFilePropertyExpectations
) {
    expect(fileProperty.rawValue).notTo(beNil())
    expect(fileProperty.isCompressed).notTo(beNil())
    expect(fileProperty.isEncrypted).notTo(beNil())
    expect(fileProperty.isDeploymentDocument).notTo(beNil())
    expect(fileProperty.isDRMDocument).notTo(beNil())
    expect(fileProperty.doesEncryptAccreditedCertificate).notTo(beNil())
    expect(fileProperty.isAccreditedCertificateDRMDocument).notTo(beNil())
}

private func assertDocInfoRawRecordCountMatchesDetailedExpectations(
    _ expectations: FixtureExpectations
) {
    guard expectations.docInfoRawRecordCount != nil ||
        expectations.docInfoRawRecords != nil
    else {
        return
    }

    let expectedCount = docInfoRawRecordExpectationCount(expectations.docInfoRawRecords)
    expect(expectations.docInfoRawRecordCount) == Optional(expectedCount)
    if expectedCount > 0 {
        expect(docInfoRawRecordsHavePayloadSamples(expectations.docInfoRawRecords)) == true
    }
}

private func docInfoRawRecordExpectationCount(
    _ records: FixtureDocInfoRawRecordsExpectations?
) -> Int {
    guard let records else {
        return 0
    }

    var count = 0
    if records.docData != nil {
        count += 1
    }
    if records.distributeDocData != nil {
        count += 1
    }
    count += records.trackChanges?.count ?? 0
    count += records.memoShapes?.count ?? 0
    count += records.trackChangeContents?.count ?? 0
    count += records.trackChangeAuthors?.count ?? 0
    count += records.forbiddenChars?.count ?? 0
    return count
}

private func assertControlCountExpectationsAreInternallyConsistent(
    _ expectations: FixtureExpectations
) {
    if let controlTypeCounts = expectations.controlTypeCounts {
        expect(expectations.controlCount) == Optional(controlTypeCounts.values.reduce(0, +))
    }
    if let allControlTypeCounts = expectations.allControlTypeCounts {
        expect(expectations.allControlCount) == Optional(allControlTypeCounts.values.reduce(0, +))
    }
    if let controlCount = expectations.controlCount,
       let allControlCount = expectations.allControlCount
    {
        expect(allControlCount).to(beGreaterThanOrEqualTo(controlCount))
    }
    if let controlTypeCounts = expectations.controlTypeCounts,
       let allControlTypeCounts = expectations.allControlTypeCounts
    {
        for (controlType, count) in controlTypeCounts {
            expect(allControlTypeCounts[controlType] ?? 0).to(beGreaterThanOrEqualTo(count))
        }
    }
}

private func assertParagraphPayloadCountsAreInternallyConsistent(
    _ expectations: FixtureExpectations,
    _ fixtureId: String
) {
    assertPayloadBatchCount(
        count: expectations.paraTextRawPayloadCount,
        totalByteCount: expectations.paraTextRawPayloadTotalByteCount,
        prefixes: expectations.paraTextRawPayloadPrefixBytes,
        suffixes: expectations.paraTextRawPayloadSuffixBytes,
        context: "\(fixtureId) paraTextRawPayload"
    )
    assertPayloadBatchCount(
        count: expectations.paraTextPayloadCount,
        totalByteCount: expectations.paraTextPayloadTotalByteCount,
        prefixes: expectations.paraTextPayloadPrefixBytes,
        suffixes: expectations.paraTextPayloadSuffixBytes,
        context: "\(fixtureId) paraTextPayload"
    )
    assertPayloadBatchCount(
        count: expectations.paraHeaderPayloadCount,
        totalByteCount: expectations.paraHeaderPayloadTotalByteCount,
        prefixes: expectations.paraHeaderPayloadPrefixBytes,
        suffixes: expectations.paraHeaderPayloadSuffixBytes,
        context: "\(fixtureId) paraHeaderPayload"
    )
    assertPayloadBatchCount(
        count: expectations.paraCharShapePayloadCount,
        totalByteCount: expectations.paraCharShapePayloadTotalByteCount,
        prefixes: expectations.paraCharShapePayloadPrefixBytes,
        suffixes: expectations.paraCharShapePayloadSuffixBytes,
        context: "\(fixtureId) paraCharShapePayload"
    )
    assertPayloadBatchCount(
        count: expectations.paraLineSegPayloadCount,
        totalByteCount: expectations.paraLineSegPayloadTotalByteCount,
        prefixes: expectations.paraLineSegPayloadPrefixBytes,
        suffixes: expectations.paraLineSegPayloadSuffixBytes,
        context: "\(fixtureId) paraLineSegPayload"
    )
    assertParaRangeTagCount(expectations, fixtureId)
}

private func assertPayloadBatchCount(
    count: Int?,
    totalByteCount: Int?,
    prefixes: [[UInt8]]?,
    suffixes: [[UInt8]]?,
    context: String
) {
    guard count != nil || totalByteCount != nil || prefixes != nil || suffixes != nil else {
        return
    }

    expect(count).notTo(beNil(), description: "\(context) must declare count")
    expect(totalByteCount).notTo(
        beNil(),
        description: "\(context) must declare total byte count"
    )
    guard let count, let totalByteCount else {
        return
    }

    if count == 0 {
        expect(totalByteCount) == 0
        expect(prefixes ?? []).to(beEmpty())
        expect(suffixes ?? []).to(beEmpty())
        return
    }

    expect(totalByteCount).to(beGreaterThan(0))
    expect(prefixes?.count) == count
    expect(suffixes?.count) == count
}

private func assertParaRangeTagCount(_ expectations: FixtureExpectations, _ fixtureId: String) {
    guard expectations.paraRangeTagCount != nil ||
        expectations.paraRangeTagPayloadTotalByteCount != nil ||
        expectations.paraRangeTags != nil
    else {
        return
    }

    expect(expectations.paraRangeTagCount).notTo(
        beNil(),
        description: "\(fixtureId) paraRangeTag must declare count"
    )
    expect(expectations.paraRangeTagPayloadTotalByteCount).notTo(
        beNil(),
        description: "\(fixtureId) paraRangeTag must declare total byte count"
    )
    guard let count = expectations.paraRangeTagCount,
          let totalByteCount = expectations.paraRangeTagPayloadTotalByteCount
    else {
        return
    }

    if count == 0 {
        expect(totalByteCount) == 0
        expect(expectations.paraRangeTags ?? []).to(beEmpty())
    } else {
        expect(totalByteCount).to(beGreaterThan(0))
        expect(expectations.paraRangeTags?.count) == count
    }
}

private func assertStreamFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("bin-data") {
        assertBinaryDataFeatureExpectations(expectations)
    }
    if features.contains("missing-bin-data") {
        expect(expectations.binaryDataCount) == 0
        expect(expectations.binaryDataNames).to(beEmpty())
        expect(expectations.binaryDataStreamIds).to(beEmpty())
        expect(expectations.binaryDataExtensionNames).to(beEmpty())
        expect(expectations.binaryDataPayloadLengths).to(beEmpty())
        expect(expectations.binaryDataPayloadPrefixBytes).to(beEmpty())
        expect(expectations.binaryDataPayloadSuffixBytes).to(beEmpty())
        expect(expectations.binaryDataTotalByteCount) == 0
        expect(expectations.docInfoIdMappings?.binDataCount) == 0
    }
    if features.contains("preview-text") {
        expect(previewTextHasPayloadSamples(expectations)) == true
    }
    if features.contains("preview-image") {
        expect(previewImageHasFormatPayloadSamples(expectations)) == true
    }
    if features.contains("ignored-root-entries") {
        expect(expectations.topLevelEntryNames).to(contain("DocOptions"))
        expect(expectations.topLevelEntryNames).to(contain("Scripts"))
    }
    if features.contains("missing-preview-image") {
        expect(expectations.previewImageLength) == 0
        expect(expectations.previewImageFormat) == HwpPreviewImageFormat.none
    }
    if features.contains("derived-missing-preview-image") {
        expect(expectations.previewImageLength) == 0
        expect(expectations.previewImageFormat) == HwpPreviewImageFormat.none
        expect(expectations.previewImagePrefixBytes).to(beEmpty())
        expect(expectations.previewImageSuffixBytes).to(beEmpty())
    }
    if features.contains("derived-missing-preview-text") {
        expect(expectations.topLevelEntryNames).notTo(contain(HwpStreamName.previewText.rawValue))
        expect(expectations.topLevelEntryNames).to(contain("XrvText"))
        expect(expectations.previewTextLength) == 1
        expect(expectations.previewTextRawPayloadLength) == 4
        expect(expectations.previewTextPrefixBytes) == [0x0D, 0x00, 0x0A, 0x00]
        expect(expectations.previewTextSuffixBytes) == [0x0D, 0x00, 0x0A, 0x00]
    }
    if features.contains("derived-missing-summary") {
        expect(expectations.topLevelEntryNames).notTo(contain(HwpStreamName.summary.rawValue))
        expect(expectations.topLevelEntryNames).to(contain("\u{5}XwpSummaryInformation"))
        expect(expectations.summaryLength) == 0
        expect(expectations.summaryPrefixBytes).to(beEmpty())
        expect(expectations.summarySuffixBytes).to(beEmpty())
    }
}

private func assertTextBodyFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("blank") {
        expect(features).notTo(contain("paragraph-text"))
        expect(expectations.sectionCount) == 1
        expect(expectations.paragraphCount) == 1
        expect(expectations.visibleTextContains ?? []).to(beEmpty())
    }
    if features.contains("plain-text-minimal") {
        expect(features).to(contain("paragraph-text"))
        expect(expectations.sectionCount) == 1
        expect(expectations.paragraphCount) == 1
        expect(expectations.allParagraphCount ?? expectations.paragraphCount) ==
            expectations.paragraphCount
        expect(expectations.visibleTextContains).notTo(beEmpty())
    }
    if features.contains("large-document") {
        assertLargeDocumentFeatureExpectations(expectations)
    }
    if features.contains("paragraph-text") {
        assertParagraphTextFeatureExpectations(expectations)
    }
    if features.contains("multi-paragraph") {
        let paragraphCount = expectations.allParagraphCount ?? expectations.paragraphCount ?? 0
        expect(paragraphCount).to(beGreaterThan(1))
        expect(expectations.sectionParagraphCounts).notTo(beNil())
    }
    if features.contains("multi-section") {
        expect(expectations.sectionCount ?? 0).to(beGreaterThan(1))
        expect(expectations.sectionParagraphCounts?.count) == expectations.sectionCount
        if let sectionCount = expectations.sectionCount,
           expectations.bodyTextSectionEntryNames != nil
        {
            let expectedNames = (0 ..< sectionCount).map { "Section\($0)" }
            expect(expectations.bodyTextSectionEntryNames) == expectedNames
        }
    }
    if features.contains("track-changes") {
        assertTrackChangesBodyFeatureExpectations(expectations)
    }
}

private func assertControlBodyFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if let columns = expectations.columns {
        expect(columns.allSatisfy(columnHasTypedId)) == true
    }
    if features.contains("table") {
        assertTableFeatureExpectations(expectations)
    }
    if features.contains("columns") {
        assertColumnFeatureExpectations(expectations)
    }
    if features.contains("hyperlink") {
        expect(expectations.hyperlinks).notTo(beEmpty())
        expect(expectations.hyperlinks?.allSatisfy(hyperlinkHasPayloadSamples) ?? false) == true
    }
    if features.contains("page-number") {
        assertPageNumberFeatureExpectations(expectations)
    }
    if features.contains("header-footer") {
        expect(expectations.allControlTypeCounts?["header"] ?? 0).to(beGreaterThan(0))
        expect(expectations.allControlTypeCounts?["footer"] ?? 0).to(beGreaterThan(0))
        expect(expectations.listControls?.map(\.kind)).to(contain("header"))
        expect(expectations.listControls?.map(\.kind)).to(contain("footer"))
        expect(expectations.listControls?.allSatisfy(listControlHasPayloadSamples) ?? false) == true
        expect(expectations.visibleTextContains).notTo(beEmpty())
    }
    if features.contains("footnote-endnote") {
        assertFootnoteEndnoteFeatureExpectations(expectations)
    }
    if features.contains("equation") {
        expect(expectations.allControlTypeCounts?["equation"] ?? 0).to(beGreaterThan(0))
        expect(expectations.shapeControls).notTo(beEmpty())
        expect(expectations.shapeControls?.allSatisfy(shapeControlHasPayloadSamples) ?? false)
            == true
        expect(expectations.shapeControls?.flatMap { $0.eqEditTexts ?? [] }).notTo(beEmpty())
        expect(expectations.visibleTextContains).notTo(beEmpty())
    }
    if features.contains("memo") {
        assertMemoFeatureExpectations(expectations)
    }
    if features.contains("bookmark") {
        assertBookmarkFeatureExpectations(expectations)
    }
}

private func assertOtherControlBodyFeatureExpectations(
    _ features: Set<String>,
    _ expectations: FixtureExpectations
) {
    if features.contains("other-controls") {
        assertOtherKnownControlFeatureExpectations(expectations)
    }
    if features.contains("auto-number") {
        assertAutoNumberFeatureExpectations(expectations)
    }
    if features.contains("new-number") {
        assertNewNumberFeatureExpectations(expectations)
    }
    if features.contains("page-hide") {
        assertPageHideFeatureExpectations(expectations)
    }
    if features.contains("indexmark") {
        assertIndexmarkFeatureExpectations(expectations)
    }
    if features.contains("hidden-comment") {
        assertHiddenCommentFeatureExpectations(expectations)
    }
}
