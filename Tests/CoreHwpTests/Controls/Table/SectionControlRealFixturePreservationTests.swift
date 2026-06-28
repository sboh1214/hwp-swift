@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class SectionControlFixtureTests: XCTestCase {
    func testNooriTableAndPageNumberControlsSurviveHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "noori")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let tables = try nooriTableExpectations(fixture)
        let pageNumberPositions = try nooriPageNumberPositionExpectations(fixture)
        let originalTables = FixtureDerivedValues.tables(from: hwp)
        let decodedTables = FixtureDerivedValues.tables(from: decoded)
        let originalPositions = FixtureDerivedValues.pageNumberPositions(from: hwp)
        let decodedPositions = FixtureDerivedValues.pageNumberPositions(from: decoded)

        FixtureAssertions.assertTables(tables, decodedTables)
        FixtureAssertions.assertPageNumberPositions(pageNumberPositions, decodedPositions)
        assertTablePayloadsMatch(decodedTables, originalTables)
        assertPageNumberPositionPayloadsMatch(decodedPositions, originalPositions)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func nooriTableExpectations(_ fixture: LoadedFixture) throws -> [FixtureTableExpectations] {
    guard let tables = fixture.manifest.expectations.tables else {
        fail("Expected noori fixture manifest to declare table expectations")
        return []
    }

    return tables
}

private func nooriPageNumberPositionExpectations(
    _ fixture: LoadedFixture
) throws -> [FixturePageNumberPositionExpectations] {
    guard let positions = fixture.manifest.expectations.pageNumberPositions else {
        fail("Expected noori fixture manifest to declare page-number expectations")
        return []
    }

    return positions
}

private func assertTablePayloadsMatch(_ decoded: [HwpTable], _ original: [HwpTable]) {
    expect(decoded.map(\.commonCtrlProperty.rawPayload)) ==
        original.map(\.commonCtrlProperty.rawPayload)
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map(\.tableProperty.rawPayload)) == original.map(\.tableProperty.rawPayload)
    expect(decoded.map(\.tableProperty.rawTrailing)) == original.map(\.tableProperty.rawTrailing)
    expect(decoded.map(\.tableProperty.zonePropertyArray)) ==
        original.map(\.tableProperty.zonePropertyArray)
    expect(decoded.map { $0.cellArray.map(\.header.rawPayload) }) ==
        original.map { $0.cellArray.map(\.header.rawPayload) }
    expect(decoded.map { $0.cellArray.map(\.header.rawTrailing) }) ==
        original.map { $0.cellArray.map(\.header.rawTrailing) }
    expect(decoded.map { $0.cellArray.map(\.header.unknownChildren) }) ==
        original.map { $0.cellArray.map(\.header.unknownChildren) }
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
    assertTableCellParagraphPayloadsMatch(decoded, original)
}

private func assertPageNumberPositionPayloadsMatch(
    _ decoded: [HwpPageNumberPosition],
    _ original: [HwpPageNumberPosition]
) {
    expect(decoded.map(\.rawPayload)) == original.map(\.rawPayload)
    expect(decoded.map(\.rawTrailing)) == original.map(\.rawTrailing)
    expect(decoded.map(\.unknownChildren)) == original.map(\.unknownChildren)
}

private func assertTableCellParagraphPayloadsMatch(
    _ decoded: [HwpTable],
    _ original: [HwpTable]
) {
    let decodedParagraphs = decoded.flatMap(\.cellArray).map(\.paragraphArray)
    let originalParagraphs = original.flatMap(\.cellArray).map(\.paragraphArray)

    expect(decodedParagraphs.count) == originalParagraphs.count
    let pairedParagraphs = zip(decodedParagraphs, originalParagraphs)
    for (decodedCellParagraphs, originalCellParagraphs) in pairedParagraphs {
        expect(decodedCellParagraphs.map(\.paraHeader.rawPayload)) ==
            originalCellParagraphs.map(\.paraHeader.rawPayload)
        expect(decodedCellParagraphs.map { $0.paraText?.rawPayload }) ==
            originalCellParagraphs.map { $0.paraText?.rawPayload }
        expect(decodedCellParagraphs.map(\.paraCharShape.rawPayload)) ==
            originalCellParagraphs.map(\.paraCharShape.rawPayload)
        expect(decodedCellParagraphs.map(\.paraLineSeg.rawPayload)) ==
            originalCellParagraphs.map(\.paraLineSeg.rawPayload)
        expect(decodedCellParagraphs.map { $0.paraRangeTagArray?.map(\.rawPayload) }) ==
            originalCellParagraphs.map { $0.paraRangeTagArray?.map(\.rawPayload) }
        expect(decodedCellParagraphs.map(\.ctrlHeaderArray)) ==
            originalCellParagraphs.map(\.ctrlHeaderArray)
        expect(decodedCellParagraphs.map(\.unknownChildren)) ==
            originalCellParagraphs.map(\.unknownChildren)
    }
}
