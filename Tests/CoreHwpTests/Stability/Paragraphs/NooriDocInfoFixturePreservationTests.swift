@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class NooriDocInfoFixturePreservationTests: XCTestCase {
    func testNooriDocInfoRecordsSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "noori")
        let original = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(
            HwpFile.self,
            from: JSONEncoder().encode(original)
        )

        assertNooriManifestCoversDocInfoFeatures(fixture.manifest)
        FixtureAssertions.assertDocInfoRawRecords(fixture.manifest.expectations, decoded)
        FixtureAssertions.assertCompatibleDocument(fixture.manifest.expectations, decoded)
        try assertDocDataPreserved(decoded.docInfo, original.docInfo)
        try assertCompatibleDocumentPreserved(decoded.docInfo, original.docInfo)
        expect(decoded.docInfo.rawPayload) == original.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) ==
            original.sectionArray.map(\.rawPayload)
    }
}

private func assertNooriManifestCoversDocInfoFeatures(_ manifest: FixtureManifest) {
    for feature in [
        "doc-data",
        "forbidden-char",
        "layout-compatibility",
        "track-change-records",
        "compatible-track-change-records",
    ] {
        expect(manifest.features).to(contain(feature))
    }
}

private func assertDocDataPreserved(
    _ decoded: HwpDocInfo,
    _ original: HwpDocInfo
) throws {
    let decodedDocData = try XCTUnwrap(decoded.docData)
    let originalDocData = try XCTUnwrap(original.docData)

    expect(decodedDocData.rawPayload) == originalDocData.rawPayload
    expect(decodedDocData.forbiddenCharArray.map(\.rawPayload)) ==
        originalDocData.forbiddenCharArray.map(\.rawPayload)
    expect(decodedDocData.forbiddenCharArray.map(\.unknownChildren)) ==
        originalDocData.forbiddenCharArray.map(\.unknownChildren)
    expect(decodedDocData.forbiddenCharArray.count) == 1
    expect(decodedDocData.unknownChildren) == originalDocData.unknownChildren
}

private func assertCompatibleDocumentPreserved(
    _ decoded: HwpDocInfo,
    _ original: HwpDocInfo
) throws {
    let decodedCompatible = try XCTUnwrap(decoded.compatibleDocument)
    let originalCompatible = try XCTUnwrap(original.compatibleDocument)

    expect(decoded.trackChangeArray).to(beEmpty())
    expect(decodedCompatible.rawPayload) == originalCompatible.rawPayload
    expect(decodedCompatible.targetDocument) == originalCompatible.targetDocument
    expect(decodedCompatible.targetDocumentRawPayload) ==
        originalCompatible.targetDocumentRawPayload
    expect(decodedCompatible.unknownChildren) == originalCompatible.unknownChildren
    expect(decodedCompatible.layoutCompatibility?.rawPayload) ==
        originalCompatible.layoutCompatibility?.rawPayload
    expect(decodedCompatible.layoutCompatibility?.fixedFieldsRawPayload) ==
        originalCompatible.layoutCompatibility?.fixedFieldsRawPayload
    expect(decodedCompatible.layoutCompatibility?.unknownChildren) ==
        originalCompatible.layoutCompatibility?.unknownChildren
    expect(decodedCompatible.layoutCompatibility?.char) ==
        originalCompatible.layoutCompatibility?.char
    expect(decodedCompatible.layoutCompatibility?.paragraph) ==
        originalCompatible.layoutCompatibility?.paragraph
    expect(decodedCompatible.layoutCompatibility?.section) ==
        originalCompatible.layoutCompatibility?.section
    expect(decodedCompatible.layoutCompatibility?.object) ==
        originalCompatible.layoutCompatibility?.object
    expect(decodedCompatible.layoutCompatibility?.field) ==
        originalCompatible.layoutCompatibility?.field
    expect(decodedCompatible.trackChangeArray.map(\.rawPayload)) ==
        originalCompatible.trackChangeArray.map(\.rawPayload)
    expect(decodedCompatible.trackChangeArray.map(\.unknownChildren)) ==
        originalCompatible.trackChangeArray.map(\.unknownChildren)
    expect(decodedCompatible.trackChangeArray.count) == 1
    expect(decodedCompatible.trackChangeArray.flatMap(\.unknownChildren)).to(beEmpty())
}
