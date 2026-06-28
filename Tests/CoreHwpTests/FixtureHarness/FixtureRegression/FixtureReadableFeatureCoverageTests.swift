import Foundation
import Nimble
import XCTest

final class FixtureReadableFeatureCoverageTests: XCTestCase {
    func testReadableGoalFeatureTagsAreKnownCanonicalFeatureTags() {
        for feature in readableReaderGoalFeatureTags {
            expect(isCanonicalFeatureTag(feature)) == true
            expect(knownFixtureFeatureTags).to(
                contain(feature),
                description: "\(feature) is a goal feature but is not in the manifest vocabulary"
            )
        }
    }

    func testReadableFixtureSuiteCoversCurrentReaderGoalFeatureTags() throws {
        let coveredFeatures = try FixtureLoader.loadAll()
            .filter { $0.manifest.expectedError == nil }
            .reduce(into: Set<String>()) { result, fixture in
                result.formUnion(fixture.manifest.features)
            }

        for feature in readableReaderGoalFeatureTags {
            expect(coveredFeatures).to(contain(feature))
        }
    }

    func testReadableGoalFeatureTagsHaveFeatureSpecificExpectationGates() throws {
        let featureGateSource = try fixtureFeatureGateSource()

        for feature in readableReaderGoalFeatureTags {
            expect(featureGateSource).to(
                contain("features.contains(\"\(feature)\")"),
                description: "\(feature) is covered by fixtures but has no expectation gate"
            )
        }
    }
}

private func fixtureFeatureGateSource() throws -> String {
    let testsRoot = testsRoot(from: #file)
    let sourceFileNames = [
        "FixtureManifestTests.swift",
        "FixtureDocInfoFeatureAssertions.swift",
        "FixtureManifestObjectFeatureAssertions.swift",
    ]
    let sources = try sourceFileNames.map { fileName in
        try String(
            contentsOf: testsRoot.appendingPathComponent(fileName),
            encoding: .utf8
        )
    }
    return sources.joined(separator: "\n")
}
