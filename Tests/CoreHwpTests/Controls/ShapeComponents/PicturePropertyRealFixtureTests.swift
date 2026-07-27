@testable import CoreHwp
import Nimble
import XCTest

final class PicturePropertyRealFixtureTests: XCTestCase {
    func testBinDataFixtureLinksPictureComponentsToBinaryDataStreams() throws {
        let hwp = try openHwp(#file, "BinData")

        let streamIds = hwp.binaryDataArray.compactMap(\.streamId)
        expect(streamIds).to(contain(1, 2, 3))

        let components = FixtureDerivedValues.allGenShapeObjects(from: hwp)
            .flatMap(\.shapeComponentArray)
            + FixtureDerivedValues.shapeControls(from: hwp).flatMap(\.shapeComponentArray)
        let pictures = components.flatMap(\.pictureArray)
        expect(pictures).notTo(beEmpty())

        let binItemIds = pictures.compactMap { $0.pictureProperty?.binItemId }
        expect(binItemIds.count) == pictures.count
        expect(Set(binItemIds).isSubset(of: [1, 2, 3])) == true

        for picture in pictures {
            expect(picture.pictureProperty?.binItemId) == picture.binaryDataId
        }
    }
}
