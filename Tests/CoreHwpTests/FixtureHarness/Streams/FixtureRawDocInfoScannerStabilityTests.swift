@testable import CoreHwp
import Nimble
import XCTest

final class FixtureRawDocInfoScannerStabilityTests: XCTestCase {
    func testFixtureScannerReportsNestedDocInfoTagLevelsSeparately() throws {
        let fixture = try FixtureLoader.load(id: "noori")
        let topLevelTags = try FixtureRawDocInfoScanner.topLevelTagIds(in: fixture)
        let recordTags = try FixtureRawDocInfoScanner.recordTags(in: fixture)

        expect(topLevelTags).to(contain(HwpDocInfoTag.compatibleDocument.rawValue))
        expect(topLevelTags).notTo(contain(HwpDocInfoTag.trackChange.rawValue))
        expect(recordTags).to(contain(FixtureRawDocInfoScanner.RecordTag(
            tagId: HwpDocInfoTag.compatibleDocument.rawValue,
            level: 0
        )))
        expect(recordTags).to(contain(FixtureRawDocInfoScanner.RecordTag(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            level: 1
        )))
    }

    func testFixtureScannerRejectsDuplicateRootEntriesWithTypedError() throws {
        let url = try temporaryDirectoryEntryHwp(
            basedOnFixture: "plain-text-minimal",
            renamingEntry: "PrvText",
            to: "DocInfo",
            entryType: directoryEntryOleStreamType
        )
        defer { removeTemporaryDirectoryEntryFile(url) }

        let fixture = try loadedFixture(id: "plain-text-minimal", documentURL: url)

        for expression in [
            { try FixtureRawDocInfoScanner.topLevelStreamNames(in: fixture) },
            { try Set(FixtureRawDocInfoScanner.topLevelTagIds(in: fixture).map(String.init)) },
            {
                try Set(FixtureRawDocInfoScanner.recordTags(in: fixture)
                    .map(\.tagId)
                    .map(String.init))
            },
        ] {
            expect {
                _ = try expression()
            }.to(throwError { error in
                guard case let HwpError.invalidOLEFile(reason) = error else {
                    return fail("Expected invalidOLEFile, got \(error)")
                }
                expect(reason).to(contain("Duplicate root directory entry names"))
                expect(reason).to(contain("DocInfo"))
            })
        }
    }
}

private func loadedFixture(id: String, documentURL: URL) throws -> LoadedFixture {
    let fixture = try FixtureLoader.load(id: id)
    return LoadedFixture(
        manifest: fixture.manifest,
        fixtureURL: fixture.fixtureURL,
        documentURL: documentURL,
        readmeURL: fixture.readmeURL
    )
}
