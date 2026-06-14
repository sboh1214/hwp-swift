import CoreHwp
import Nimble
import XCTest

final class ColumnTests: XCTestCase {
    func testColumn() throws {
        let hwp = try openHwp(#file, "Column")
        let paragraphArray = hwp.sectionArray[0].paragraph

        let columnArray: [HwpColumn] = paragraphArray.map {
            $0.ctrlHeaderArray!.compactMap {
                switch $0 {
                case let .column(hwpColumn):
                    hwpColumn
                default:
                    nil
                }
            }[0]
        }

        expect(columnArray[0].property.count) == 1
        expect(columnArray[1].property.count) == 2
        expect(columnArray[2].property.count) == 3
        expect(columnArray[3].property.count) == 2
        expect(columnArray[4].property.count) == 2

        expect(columnArray[0].property.isSameWidth) == true
        expect(columnArray[1].property.isSameWidth) == true
        expect(columnArray[2].property.isSameWidth) == true
        expect(columnArray[3].property.isSameWidth) == false
        expect(columnArray[4].property.isSameWidth) == false

        expect(columnArray[0].property.direction) == .left

        expect(columnArray[0].widthArray).to(beNil())
        expect(columnArray[1].widthArray).to(beNil())
        expect(columnArray[2].widthArray).to(beNil())

        expect(columnArray[3].widthArray?[0]) == 0
        expect(columnArray[3].widthArray?[1]) == 10339
        expect(columnArray[4].widthArray?[0]) == 0
        expect(columnArray[4].widthArray?[1]) == 20680
    }
}
