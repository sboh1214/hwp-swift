import CoreHwp
import Foundation
import Nimble
import XCTest

final class ColumnTests: XCTestCase {
    func testColumn() throws {
        let hwp = try openHwp(#file, "Column")
        let columnArray = columns(in: hwp)

        guard columnArray.count >= 5 else {
            return fail("Expected at least 5 column controls, got \(columnArray.count)")
        }

        expect(columnArray[0].property.count) == 1
        expect(columnArray[1].property.count) == 2
        expect(columnArray[2].property.count) == 3
        expect(columnArray[3].property.count) == 2
        expect(columnArray[4].property.count) == 2
        expect(columnArray.map(\.property.rawValue)) == [4100, 4104, 4108, 8, 8, 4100]

        expect(columnArray[0].property.isSameWidth) == true
        expect(columnArray[1].property.isSameWidth) == true
        expect(columnArray[2].property.isSameWidth) == true
        expect(columnArray[3].property.isSameWidth) == false
        expect(columnArray[4].property.isSameWidth) == false

        expect(columnArray[0].property.direction) == .left

        expect(columnArray[0].widthArray).to(beNil())
        expect(columnArray[1].widthArray).to(beNil())
        expect(columnArray[2].widthArray).to(beNil())

        expect(columnArray[3].property2) == 0
        expect(columnArray[4].property2) == 0
        expect(columnArray[3].widthArray) == [10339, 20682]
        expect(columnArray[4].widthArray) == [20680, 10341]
        expect(columnArray[3].gapArray) == [1747, 0]
        expect(columnArray[4].gapArray) == [1747, 0]
        expect(columnArray[3].dividerType) == 0
        expect(columnArray[4].dividerType) == 0
        expect(columnArray[3].rawTrailing).to(beEmpty())
        expect(columnArray[4].rawTrailing).to(beEmpty())
    }

    func testColumnFixtureSurvivesHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "Column")
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let expectedColumns = try columnManifestExpectations()

        FixtureAssertions.assertColumns(expectedColumns, columns(in: decoded))
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
        expect(decoded.previewText.rawPayload) == hwp.previewText.rawPayload
        expect(decoded.previewImage.rawPayload) == hwp.previewImage.rawPayload
    }
}

private func columns(in hwp: HwpFile) -> [HwpColumn] {
    FixtureDerivedValues.columns(from: hwp)
}

private func columnManifestExpectations() throws -> [FixtureColumnExpectations] {
    guard let columns = try FixtureLoader.load(id: "Column").manifest.expectations.columns else {
        fail("Expected Column fixture manifest to declare column expectations")
        return []
    }

    return columns
}
