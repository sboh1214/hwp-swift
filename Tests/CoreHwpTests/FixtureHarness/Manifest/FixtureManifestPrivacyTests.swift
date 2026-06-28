import Nimble
import XCTest

final class FixtureManifestPrivacyTests: XCTestCase {
    func testCommittedFixtureManifestsAreNotSynthetic() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let searchableMetadata = [
                fixture.manifest.generationTool,
                fixture.manifest.source,
            ].joined(separator: "\n").lowercased()

            expect(searchableMetadata).notTo(
                contain("synthetic"),
                description: "\(fixture.manifest.id) fixture metadata must not be synthetic"
            )
        }
    }

    func testFixtureMetadataDoesNotImportPrivateCloudStorageSources() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let searchableMetadata = [
                fixture.manifest.generationTool,
                fixture.manifest.source,
            ].joined(separator: "\n")

            for fragment in forbiddenPrivateSourceFragments {
                expect(searchableMetadata).notTo(
                    contain(fragment),
                    description: "\(fixture.manifest.id) fixture metadata leaks \(fragment)"
                )
            }
        }
    }

    func testFixtureReadmesDoNotImportPrivateLocalSourcePaths() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)

            for fragment in forbiddenPrivateSourceFragments {
                expect(readme).notTo(
                    contain(fragment),
                    description: "\(fixture.manifest.id) README leaks \(fragment)"
                )
            }
        }
    }

    func testDerivedFixtureProvenanceIsExplicitAndIsolated() throws {
        let fixtures = try FixtureLoader.loadAll()

        for fixture in fixtures {
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)
            let manifest = fixture.manifest
            let hasDerivedFeature = manifest.features.contains { $0.hasPrefix("derived-") }
            let searchableMetadata = [
                manifest.id,
                manifest.generationTool,
                manifest.source,
            ].joined(separator: "\n").lowercased()

            if hasDerivedFeature {
                expect(manifest.id).to(
                    contain("derived"),
                    description: "\(manifest.id) derived fixture id must be explicit"
                )
                expect(searchableMetadata).to(
                    contain("derived"),
                    description: "\(manifest.id) derived fixture metadata must be explicit"
                )
                expect(readme).to(
                    contain("파생 fixture"),
                    description: "\(manifest.id) README must mark derived provenance"
                )
            } else {
                expect(searchableMetadata).notTo(
                    contain("derived"),
                    description: "\(manifest.id) non-derived fixture metadata is ambiguous"
                )
                expect(readme).notTo(
                    contain("파생 fixture"),
                    description: "\(manifest.id) non-derived README is ambiguous"
                )
            }
        }
    }

    func testHancomGeneratedGoalFixturesKeepDirectSaveProvenance() throws {
        let fixturesById = try FixtureLoader.loadAll()
            .reduce(into: [String: LoadedFixture]()) { result, fixture in
                result[fixture.manifest.id] = fixture
            }

        for fixtureId in hancomGeneratedGoalFixtureIds {
            guard let fixture = fixturesById[fixtureId] else {
                return fail("Missing Hancom-generated goal fixture: \(fixtureId)")
            }

            let manifest = fixture.manifest
            let readme = try String(contentsOf: fixture.readmeURL, encoding: .utf8)

            expect(manifest.expectedError).to(
                beNil(),
                description: "\(fixtureId) should be a readable Hancom-saved fixture"
            )
            expect(manifest.features.contains { $0.hasPrefix("derived-") }) == false
            expect(manifest.generationTool) == hancomGenerationTool
            expect(manifest.source).to(contain("Generated locally"))
            expect(manifest.source).to(contain("Hancom Office HWP"))
            expect(readme).to(contain("재생성"))
            expect(readme.contains("Hancom Office HWP") || readme.contains("한컴오피스")) == true
        }
    }
}

private let forbiddenPrivateSourceFragments = [
    "/Users/",
    "/private/tmp/",
    "CloudStorage",
    "GoogleDrive",
    "Google Drive",
    "개인 문서",
]

private let hancomGenerationTool = "Hancom Office HWP for macOS 12.30.0 (build 6382)"

private let hancomGeneratedGoalFixtureIds = [
    "bookmark",
    "chart",
    "equation",
    "footnote-endnote",
    "header-footer",
    "memo",
    "multi-section",
    "plain-text-hancom-mac2026",
    "plain-text-minimal",
    "text-box",
    "track-changes",
]
