// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FixtureKnownMissingGoalTests: XCTestCase {
    func testFixtureSuiteCoversCurrentGoalFeatures() throws {
        let fixtures = try FixtureLoader.loadAll()
        let readableFeatures = fixtures
            .filter { $0.manifest.expectedError == nil }
            .reduce(into: Set<String>()) { result, fixture in
                result.formUnion(fixture.manifest.features)
            }
        let expectedErrorCodes = Set(fixtures.compactMap(\.manifest.expectedError?.code))

        let missingReadableFeatures = requiredReadableGoalFeatureTags
            .subtracting(readableFeatures)
        expect(missingReadableFeatures.sorted()).to(beEmpty())
        expect(expectedErrorCodes).to(contain("unsupportedFeature.encryptedDocument"))
        expect(expectedErrorCodes).to(contain("unsupportedFeature.deploymentDocument"))
        expect(expectedErrorCodes).to(contain("unsupportedFeature.drmDocument"))
    }

    func testReadableGoalFeaturesAreCoveredByActualFixtureProvenance() throws {
        let fixtures = try FixtureLoader.loadAll()
        let actualReadableFeatures = try actualReadableFeatureSet(from: fixtures)

        let missingActualFeatures = requiredReadableGoalFeatureTags
            .subtracting(actualReadableFeatures)
        expect(missingActualFeatures.sorted()).to(beEmpty())
    }

    // swiftlint:disable:next function_body_length
    func testFixtureSuiteDoesNotClaimKnownMissingGoalFixtures() throws {
        let fixtures = try FixtureLoader.loadAll()
        let coveredFeatures = fixtures
            .reduce(into: Set<String>()) { result, fixture in
                result.formUnion(fixture.manifest.features)
            }

        for feature in [
            "distribute-doc-data",
            "missing-preview-image",
            "top-level-track-change-records",
        ] {
            expect(coveredFeatures).notTo(contain(feature))
        }

        for fixture in fixtures {
            let fileHeader = try HwpFileHeader.load(fromPath: fixture.documentURL.path)
            let topLevelStreamNames = try FixtureRawDocInfoScanner.topLevelStreamNames(in: fixture)
            if fixture.manifest.features.contains("derived-drm") {
                expect(fileHeader.fileProperty.isDRMDocument) == true
                expect(fileHeader.fileProperty.unsupportedFeature) == .drmDocument
            } else {
                expect(fileHeader.fileProperty.isDRMDocument) == false
                expect(fileHeader.fileProperty.isAccreditedCertificateDRMDocument) == false
                expect(fileHeader.fileProperty.unsupportedFeature == .drmDocument) == false
            }
            if !fileHeader.fileProperty.isEncrypted {
                let rawDocInfoTagIds = try FixtureRawDocInfoScanner.topLevelTagIds(in: fixture)
                let rawDocInfoRecordTags = try FixtureRawDocInfoScanner.recordTags(in: fixture)
                let topLevelRecordTagIds = Set(
                    rawDocInfoRecordTags.filter { $0.level == 0 }.map(\.tagId)
                )
                expect(rawDocInfoTagIds).notTo(contain(HwpDocInfoTag.distributeDocData.rawValue))
                expect(rawDocInfoTagIds).notTo(contain(HwpDocInfoTag.trackChange.rawValue))
                expect(topLevelRecordTagIds).notTo(
                    contain(HwpDocInfoTag.distributeDocData.rawValue)
                )
                expect(topLevelRecordTagIds).notTo(contain(HwpDocInfoTag.trackChange.rawValue))
            }

            guard fixture.manifest.expectedError == nil else {
                continue
            }

            let hwp = try HwpFile(fromPath: fixture.documentURL.path)
            expect(hwp.docInfo.distributeDocData).to(beNil())
            if fixture.manifest.features.contains("track-change-records") {
                let compatibleTrackChanges = hwp.docInfo.compatibleDocument?.trackChangeArray ?? []
                expect(hwp.docInfo.trackChangeArray + compatibleTrackChanges).notTo(beEmpty())
            } else {
                expect(hwp.docInfo.trackChangeArray).to(beEmpty())
            }
            assertOptionalPreviewStreamsForKnownMissingGoalFixture(
                fixture,
                topLevelStreamNames,
                hwp
            )
        }
    }

    func testKnownMissingGoalFixturesStayDocumented() throws {
        let readerSupport = try String(contentsOf: readerSupportURL(), encoding: .utf8)
        let fixtureGuide = try String(
            contentsOf: FixtureLoader.root.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        expect(readerSupport).to(contain("DISTRIBUTE_DOC_DATA"))
        expect(readerSupport).to(contain("top-level `TRACK_CHANGE`"))
        expect(readerSupport).to(contain("DRM"))
        expect(fixtureGuide).to(contain("DISTRIBUTE_DOC_DATA"))
        expect(fixtureGuide).to(contain("top-level `TRACK_CHANGE`"))
        expect(fixtureGuide).to(contain("missing-preview-image"))
        expect(fixtureGuide).to(contain("DRM"))

        expect(fixtureGuide).to(contain("별도 확보 필요"))
        expect(fixtureGuide).to(contain("아직 필요한 fixture"))
        expect(fixtureGuide).to(contain("drm-unsupported-derived"))
        expect(fixtureGuide).to(contain("missing-preview-text-derived"))
        expect(fixtureGuide).to(contain("missing-summary-derived"))
        expect(fixtureGuide).to(contain("실제 DRM fixture를 추가하려면"))
        expect(fixtureGuide).to(contain("사용자 한컴오피스 설정을 변경하므로 별도 승인"))
        expect(fixtureGuide).to(contain("DRM 저장 기능이 노출되는 한컴오피스 설치본"))
        expect(fixtureGuide).to(contain("failedToCreateImageDestination"))
        expect(fixtureGuide).to(contain("sdef` error -10827"))
        expect(fixtureGuide).to(contain("error -192"))
        expect(fixtureGuide).to(contain("hwp` URL scheme"))
        expect(fixtureGuide).to(contain("automatic_action"))
        assertLocalScanHistoryIsDocumented(fixtureGuide, fixtureGuide)
        assertCoverageHistoryIsDocumented(readerSupport, fixtureGuide)
    }

    func testDerivedFixturesAreExplicitlyMarkedAndDoNotSatisfyActualFixtureGaps() throws {
        let fixtures = try FixtureLoader.loadAll()
        let derivedFixtures = try fixtures.filter(fixtureHasDerivedProvenance)

        expect(derivedFixtures.map(\.manifest.id).sorted()) == [
            "drm-unsupported-derived",
            "missing-preview-image-derived",
            "missing-preview-text-derived",
            "missing-summary-derived",
        ]

        for fixture in derivedFixtures {
            let manifest = fixture.manifest
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)

            expect(manifest.id).to(contain("derived"))
            expect(manifest.source.lowercased()).to(contain("derived"))
            expect(readme).to(contain("파생 fixture"))
            expect(readme).to(contain("대체하지"))
            expect(readme).to(contain("별도"))

            if manifest.features.contains("derived-drm") {
                expect(manifest.features).to(contain("drm"))
                expect(manifest.features).to(contain("unsupported"))
                expect(manifest.expectedError?.code) == "unsupportedFeature.drmDocument"
            }

            if manifest.features.contains("derived-missing-preview-image") {
                expect(manifest.features).notTo(contain("missing-preview-image"))
                expect(manifest.expectedError).to(beNil())
                expect(manifest.expectations.previewImageLength) == 0
                expect(manifest.expectations.previewImageFormat) == HwpPreviewImageFormat.none
            }

            if manifest.features.contains("derived-missing-preview-text") {
                expect(manifest.features).notTo(contain("missing-preview-text"))
                expect(manifest.expectedError).to(beNil())
                expect(manifest.expectations.previewTextLength) == 1
                expect(manifest.expectations.previewTextRawPayloadLength) == 4
            }

            if manifest.features.contains("derived-missing-summary") {
                expect(manifest.features).notTo(contain("missing-summary"))
                expect(manifest.expectedError).to(beNil())
                expect(manifest.expectations.summaryLength) == 0
                expect(manifest.expectations.summaryPrefixBytes).to(beEmpty())
                expect(manifest.expectations.summarySuffixBytes).to(beEmpty())
            }
        }
    }

    func testDerivedDrmFixtureDoesNotSatisfyActualDrmFixtureGap() throws {
        let fixtures = try FixtureLoader.loadAll()
        let drmFixtures = fixtures.filter { fixture in
            fixture.manifest.features.contains("drm")
        }
        let nonDerivedDrmFixtureIds = drmFixtures
            .filter { fixture in
                !fixture.manifest.features.contains("derived-drm")
            }
            .map(\.manifest.id)

        expect(nonDerivedDrmFixtureIds).to(beEmpty())
        expect(drmFixtures.map(\.manifest.id).sorted()) == ["drm-unsupported-derived"]

        let fixture = try XCTUnwrap(drmFixtures.first)
        let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)

        expect(fixture.manifest.expectedError?.code) == "unsupportedFeature.drmDocument"
        expect(fixture.manifest.features).to(contain("derived-drm"))
        expect(readme).to(contain("실제 DRM 보호 문서를 대체하지 않는다"))
        expect(readme).to(contain("DRM 저장 기능이 노출되는"))
    }
}

private func readerSupportURL() -> URL {
    FixtureLoader.root
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")
        .appendingPathComponent("CoreHwp")
        .appendingPathComponent("AGENTS.md")
}

private func actualReadableFeatureSet(from fixtures: [LoadedFixture]) throws -> Set<String> {
    var features = Set<String>()
    for fixture in fixtures {
        guard fixture.manifest.expectedError == nil else {
            continue
        }
        guard try !fixtureHasDerivedProvenance(fixture) else {
            continue
        }
        features.formUnion(fixture.manifest.features)
    }
    return features
}

private func assertOptionalPreviewStreamsForKnownMissingGoalFixture(
    _ fixture: LoadedFixture,
    _ topLevelStreamNames: Set<String>,
    _ hwp: HwpFile
) {
    if fixture.manifest.features.contains("derived-missing-preview-image") {
        expect(topLevelStreamNames).notTo(contain(HwpStreamName.previewImage.rawValue))
        expect(topLevelStreamNames).to(contain("XrvImage"))
        expect(hwp.previewImage.image).to(beEmpty())
        expect(hwp.previewImage.format) == HwpPreviewImageFormat.none
    } else {
        expect(topLevelStreamNames).to(contain(HwpStreamName.previewImage.rawValue))
        expect(hwp.previewImage.image).notTo(beEmpty())
    }

    if fixture.manifest.features.contains("derived-missing-preview-text") {
        expect(topLevelStreamNames).notTo(contain(HwpStreamName.previewText.rawValue))
        expect(topLevelStreamNames).to(contain("XrvText"))
        expect(hwp.previewText.text) == "\r\n"
        expect(hwp.previewText.rawPayload) == Data([0x0D, 0x00, 0x0A, 0x00])
    }

    if fixture.manifest.features.contains("derived-missing-summary") {
        expect(topLevelStreamNames).notTo(contain(HwpStreamName.summary.rawValue))
        expect(topLevelStreamNames).to(contain("\u{5}XwpSummaryInformation"))
        expect(hwp.summary.rawPayload).to(beEmpty())
    }
}

private func fixtureHasDerivedProvenance(_ fixture: LoadedFixture) throws -> Bool {
    let manifest = fixture.manifest
    let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)
    let searchableMetadata = [
        manifest.id,
        manifest.generationTool,
        manifest.source,
    ].joined(separator: "\n").lowercased()

    return manifest.features.contains { $0.hasPrefix("derived-") }
        || searchableMetadata.contains("derived")
        || readme.contains("파생 fixture")
}

private func assertLocalScanHistoryIsDocumented(_ projectReadme: String, _ fixtureGuide: String) {
    expect(fixtureGuide).to(contain("2026-06-19"))
    expect(fixtureGuide).to(contain("현재 HWP 후보 17개"))
    expect(fixtureGuide).to(contain("raw OLE scanner"))
    expect(fixtureGuide).to(contain("361개"))
    expect(fixtureGuide).to(contain("2026-06-20"))
    expect(fixtureGuide).to(contain("임시 Swift scanner"))
    expect(fixtureGuide).to(contain("352개"))
    expect(fixtureGuide).to(contain("readable인 파일은"))
    expect(fixtureGuide).to(contain("348개"))
    expect(fixtureGuide).to(contain("unreadable 4개"))
    expect(fixtureGuide).to(contain("2026-06-21"))
    expect(fixtureGuide).to(contain("scanned 352개"))
    expect(fixtureGuide).to(contain("header-readable 352개"))
    expect(fixtureGuide).to(contain("readable-docinfo 348개"))
    expect(fixtureGuide).to(contain("unsupported 4개"))
    expect(fixtureGuide).to(contain("invalid 0개"))
    expect(fixtureGuide).to(contain("missing-preview-image-derived` 1개"))
    expect(fixtureGuide).to(contain("track-changes` tracing"))
    expect(fixtureGuide).to(contain("drm-unsupported-derived` DRM unsupported 1개"))
    expect(projectReadme).to(contain("CloudStorage 후보 1,446개"))
    expect(projectReadme).to(contain("bounded OLE scan"))
    expect(fixtureGuide).to(contain("CloudStorage"))
    expect(fixtureGuide).to(contain("1,446개"))
    expect(fixtureGuide).to(contain("keyword가 있는 2개"))
    expect(fixtureGuide).to(contain("크기순 최소 100개"))
    expect(fixtureGuide).to(contain("encrypted unsupported"))
    expect(fixtureGuide).to(contain("repo fixture로 가져오지"))
    expect(fixtureGuide).to(contain("tracing-change flag"))
    expect(fixtureGuide).to(contain("CTRL_HEADER"))
    expect(fixtureGuide).to(contain("9,599개"))
    assertCurrentUserDocumentOleScanIsDocumented(projectReadme, fixtureGuide)
    assertCurrentOleScannerGapEvidenceIsDocumented(projectReadme, fixtureGuide)
    assertCurrentDownloadsTrackChangeCandidateIsDocumented(projectReadme, fixtureGuide)
    assertCurrentHancomAutomationSurfaceIsDocumented(projectReadme, fixtureGuide)
    assertCurrentHancomPlainTextPreviewEvidenceIsDocumented(projectReadme, fixtureGuide)
    assertPublicOpenSourceSampleScanIsDocumented(projectReadme, fixtureGuide)
}

private func assertCurrentUserDocumentOleScanIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    expect(projectReadme).to(contain("사용자 CloudStorage/Downloads/repo 후보 1,518개"))
    expect(projectReadme).to(contain("readable external 후보 384개"))
    expect(projectReadme).to(contain("개인 CloudStorage 문서 1개"))
    expect(projectReadme).to(contain("`PrvImage`와 `PrvText`가 모두 없는 compressed HWP"))
    expect(projectReadme).to(contain("동시에 없는 reader 경로"))
    expect(projectReadme).to(contain("별도 승인 없이 repository fixture로 편입하지 않음"))
    expect(fixtureGuide).to(contain("후보 1,518개"))
    expect(fixtureGuide).to(contain("repo 66개"))
    expect(fixtureGuide).to(contain("CloudStorage 1,446개"))
    expect(fixtureGuide).to(contain("Google Drive `.tmp` 경로 1개는 permission denied"))
    expect(fixtureGuide).to(contain("5MB 미만"))
    expect(fixtureGuide).to(contain("1,470개"))
    expect(fixtureGuide).to(contain("5MB 이상 48개"))
    expect(fixtureGuide).to(contain("총 scanned 453개"))
    expect(fixtureGuide).to(contain("readable external 후보는 384개"))
    expect(fixtureGuide).to(contain("`PrvImage`와 `PrvText` stream이"))
    expect(fixtureGuide).to(contain("private 문서라 별도 승인 없이 repository fixture로"))
    expect(fixtureGuide).to(contain("`missing-preview-image` 실제 fixture 후보로 승격"))
    expect(fixtureGuide).to(contain("두 preview stream"))
    expect(fixtureGuide).to(contain("동시 누락 reader 경로"))
}

private func assertCurrentOleScannerGapEvidenceIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    expect(projectReadme).to(contain("Downloads 잔여 HWP 5개"))
    expect(fixtureGuide).to(contain("Downloads에 남아 있는 HWP 후보 5개"))
    expect(projectReadme).to(contain("한컴오피스 앱 번들 HWP/HWT 후보 317개"))
    expect(fixtureGuide).to(contain("한컴오피스 앱 번들 HWP/HWT 후보 317개"))
    expect(fixtureGuide).to(contain("scanned=317"))
    expect(fixtureGuide).to(contain("errors=0"))
    expect(fixtureGuide).to(contain("missing_preview=0"))
    expect(fixtureGuide).to(contain("flat tag scan 기준 316개 앱 번들 템플릿/프리셋"))
    expect(fixtureGuide).to(contain("tree-aware 재확인 결과"))
    expect(fixtureGuide).to(contain("`COMPATIBLE_DOCUMENT = 30`의 level 1 child"))
    expect(fixtureGuide).to(contain("top-level DocInfo record는"))
    expect(projectReadme).to(contain("앱 번들의 top-level DocInfo tag 조합"))
    expect(fixtureGuide).to(contain("앱 번들의 top-level DocInfo tag 조합"))
    expect(projectReadme).to(contain("[16, 17, 30]` 289개"))
    expect(fixtureGuide).to(contain("[16, 17, 30]` 289개"))
    expect(projectReadme).to(contain("[16, 17, 27, 30]` 28개"))
    expect(fixtureGuide).to(contain("[16, 17, 27, 30]` 28개"))
    expect(fixtureGuide).to(contain("로컬 한컴오피스 앱 번들"))
    expect(fixtureGuide).to(contain("재배포 가능한 실제 HWP/HWT 샘플"))
    expect(fixtureGuide).to(contain("CoreHwp/임시"))
    expect(fixtureGuide).to(contain("scanner 기반 앱 번들"))
    expect(fixtureGuide).to(contain("top-level 오판을 함께 정정하는 근거"))
    expect(fixtureGuide).to(contain("DISTRIBUTE_DOC_DATA = 28"))
    expect(fixtureGuide).to(contain("TRACK_CHANGE = 32"))
    expect(fixtureGuide).to(contain("[16, 17, 27, 30]"))
    expect(fixtureGuide).to(contain("[16, 17, 27, 30]` 3개"))
    expect(fixtureGuide).to(contain("[16, 17, 30]` 1개"))
    expect(fixtureGuide).to(contain("Section0`~`Section40"))
    expect(fixtureGuide).to(contain("BIN0001.bmp"))
    expect(fixtureGuide).to(contain("DRM/certDRM bit가 없었습니다"))
    expect(fixtureGuide).to(contain("2026-06-22"))
    expect(fixtureGuide).to(contain("2026-06-26"))
}

private func assertPublicOpenSourceSampleScanIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    for document in [projectReadme, fixtureGuide] {
        expect(document).to(contain("mete0r/pyhwp"))
        expect(document).to(contain("indosaram/hwpers"))
        expect(document).to(contain("volexity/hwp-extract"))
        expect(document).to(contain("neolord0/hwplib"))
        expect(document).to(contain("HWP/HWT 샘플 84개"))
        expect(document).to(contain("missing-preview-image:26"))
        expect(document).to(contain("missing-preview-text:26"))
        expect(document).to(contain("edwardkim/rhwp"))
        expect(document).to(contain("123jimin/node-hwp"))
        expect(document).to(contain("markers={missing-preview-image:2, missing-preview-text:2}"))
        expect(document).to(contain("markers={deployment:3}"))
        expect(document).to(contain("postmelee/alhangeul-macos"))
        expect(document).to(contain("deployment:3"))
        expect(document).to(contain("HwpOtherCtrlId.form"))
        expect(document).to(contain("HwpCtrlId.form"))
        expect(document).to(contain("dgahn/hwplib-dsl"))
        expect(document).to(contain("hwplib"))
        expect(document).to(contain("실제 한컴오피스 저장본"))
        expect(document).to(contain("provenance"))
        expect(document).to(contain("gap을 대체하지"))
    }
    expect(fixtureGuide).to(contain("scanned=84"))
    expect(fixtureGuide).to(contain("errors=0"))
    expect(fixtureGuide).to(contain("Apache-2.0"))
    expect(fixtureGuide).to(contain("sample_hwp/basic/blank.hwp"))
    expect(fixtureGuide).to(contain("iyulab/unhwp"))
    expect(fixtureGuide).to(contain("DoHyun468/claw-hwp"))
    expect(fixtureGuide).to(contain("HWP/HWT 경로가 없었습니다"))
    expect(fixtureGuide).to(contain("scanned=59"))
    expect(fixtureGuide).to(contain("scanned=280"))
    expect(fixtureGuide).to(contain("errors=10"))
    expect(fixtureGuide).to(contain("raw id `1718579821`(`form`)"))
    expect(fixtureGuide).to(contain("unknown_control_rows=0"))
    expect(fixtureGuide).to(contain("track_top_level=0"))
    expect(fixtureGuide).to(contain("scanned=151"))
    expect(fixtureGuide).to(contain("nested_track_change=26"))
    expect(fixtureGuide).to(contain("unknown_docinfo_rows=0"))
    expect(fixtureGuide).to(contain("unknown_section_rows=0"))
    expect(fixtureGuide).to(contain("missing_preview_image_ok=0"))
    expect(fixtureGuide).to(contain("re-*-hancom.hwp"))
    expect(fixtureGuide).to(contain("disjukr/hwpkit"))
    expect(fixtureGuide).to(contain("treesoop/hwp-mcp"))
    expect(fixtureGuide).to(contain("reallygood83/master-of-hwp"))
    expect(fixtureGuide).to(contain("hallazzang/ole-py"))
    expect(fixtureGuide).to(contain(
        "markers={deployment:6, missing-preview-image:19, missing-preview-text:19}"
    ))
    expect(fixtureGuide).to(contain("nested_track_change=73"))
    expect(fixtureGuide).to(contain("[16, 17, 30]` 80개"))
}

private func assertCurrentHancomAutomationSurfaceIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    expect(projectReadme).to(contain("CFBundleShortVersionString"))
    expect(fixtureGuide).to(contain("CFBundleIdentifier"))
    expect(fixtureGuide).to(contain("CFBundleVersion"))
    expect(projectReadme).to(contain("6382"))
    expect(fixtureGuide).to(contain("CFBundleURLSchemes"))
    expect(fixtureGuide).to(contain("CFBundleURLTypes"))
    expect(fixtureGuide).to(contain("2026-06-24"))
    expect(fixtureGuide).to(contain("2026-06-25"))
    expect(projectReadme).to(contain("id of application id"))
    expect(fixtureGuide).to(contain("id of application id"))
    expect(fixtureGuide).to(contain("tell application \"Hancom Office HWP\" to get name"))
    expect(projectReadme).to(contain("app path 재확인"))
    expect(fixtureGuide).to(contain("PlistBuddy"))
    expect(fixtureGuide).to(contain("sdef '/Applications/Hancom Office HWP.app'"))
    expect(projectReadme).to(contain("command -v hwp"))
    expect(fixtureGuide).to(contain("command -v hwp5txt"))
    expect(fixtureGuide).to(contain("command -v hwp5proc"))
    expect(fixtureGuide).to(contain("error -10827"))
    expect(fixtureGuide).to(contain("error -192"))
    expect(fixtureGuide).to(contain("Resources/Help/file/options/options(edit).htm"))
    expect(fixtureGuide).to(contain("24KB라고 설명"))
}

private func assertCurrentHancomPlainTextPreviewEvidenceIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    for document in [projectReadme, fixtureGuide] {
        expect(document).to(contain("plain-text-hancom-mac2026"))
        expect(document).to(contain("previewImageBytes=22690"))
        expect(document).to(contain("BinData"))
    }

    expect(fixtureGuide).to(contain("저장 권한 팝업은 나타나지 않았고"))
    expect(fixtureGuide).to(contain("현재 기본"))
    expect(fixtureGuide).to(contain("macOS 저장 경로"))
}

private func assertCurrentDownloadsTrackChangeCandidateIsDocumented(
    _ projectReadme: String,
    _ fixtureGuide: String
) {
    expect(projectReadme).to(contain("2026-06-25 현재 Downloads HWP 5개"))
    expect(projectReadme).to(contain("재배포 가능한 top-level `TRACK_CHANGE` 후보가 없었고"))
    expect(projectReadme).to(contain("앱 번들 HWP/HWT 후보 317개 중 316개"))
    expect(projectReadme).to(contain("tree 기준 `COMPATIBLE_DOCUMENT` child"))
    expect(projectReadme).to(contain("top-level record도 아니고 로컬 앱 resource"))
    expect(fixtureGuide).to(contain("2026-06-25"))
    expect(fixtureGuide).to(contain("2026-06-26"))
    expect(fixtureGuide).to(contain("현재 Downloads에 남아 있는 HWP 후보 5개"))
    expect(fixtureGuide).to(contain("top-level `TRACK_CHANGE = 32`"))
    expect(fixtureGuide).to(contain("level 1 `TRACK_CHANGE = 32`"))
    expect(fixtureGuide).to(contain("compatible document child record"))
    expect(projectReadme).to(contain("level 1 compatible document child `TRACK_CHANGE`"))
    expect(fixtureGuide).to(contain("top-level `TRACK_CHANGE` 실제 fixture를 확보하지"))
}

private func assertCoverageHistoryIsDocumented(_ projectReadme: String, _ fixtureGuide: String) {
    for document in [projectReadme, fixtureGuide] {
        expect(document).to(contain("swift test --enable-code-coverage"))
        expect(document).to(contain(".build/out/Products/Debug/codecov/Hwp-Swift.json"))
        expect(document).notTo(contain("개 XCTest"))
        expect(document).to(contain("Sources/CoreHwp"))
        expect(document).to(contain("5481/5559"))
        expect(document).to(contain("2483/2545"))
    }

    assertCoverage(
        in: projectReadme,
        lineMarker: "line coverage는",
        regionMarker: "region coverage는"
    )
    assertCoverage(
        in: fixtureGuide,
        lineMarker: "총 line coverage는",
        regionMarker: "region coverage는"
    )
}

private func assertCoverage(in document: String, lineMarker: String, regionMarker: String) {
    guard let lineCoverage = coveragePercentage(after: lineMarker, in: document),
          let regionCoverage = coveragePercentage(after: regionMarker, in: document)
    else {
        return fail("Expected documented line and region coverage percentages")
    }

    expect(lineCoverage >= 95.0) == true
    expect(regionCoverage >= 95.0) == true
}

private func coveragePercentage(after marker: String, in text: String) -> Double? {
    guard let markerRange = text.range(of: marker) else {
        return nil
    }
    let suffix = text[markerRange.upperBound...]
    guard let percentageRange = suffix.range(
        of: #"[0-9]+(\.[0-9]+)?%"#,
        options: .regularExpression
    ) else {
        return nil
    }
    return Double(suffix[percentageRange].dropLast())
}
