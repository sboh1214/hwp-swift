@testable import CoreHwp
import Nimble
import XCTest

final class TableCellPropertyRealFixtureTests: XCTestCase {
    func testNooriFixtureDecodesCellPropertyForEveryTableCell() throws {
        let hwp = try openHwp(#file, "noori")
        let cells = FixtureDerivedValues.tables(from: hwp).flatMap(\.cellArray)

        expect(cells).notTo(beEmpty())
        expect(cells.allSatisfy { $0.header.cellProperty != nil }) == true
    }

    func testNooriFirstTableDecodesMergedCellAndRowCellCounts() throws {
        let hwp = try openHwp(#file, "noori")
        guard let table = FixtureDerivedValues.tables(from: hwp).first else {
            fail("Expected noori fixture to contain a table control")
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
        }

        let columnSpans = table.cellArray.compactMap { $0.header.cellProperty?.columnSpan }
        expect(columnSpans).to(contain(3)) // 알려진 병합 셀

        let rowCellCounts = table.tableProperty.rowCellCounts
        expect(rowCellCounts) == [2, 4, 4]
        expect(rowCellCounts.map(Int.init).reduce(0, +)) == table.cellArray.count
    }
}
