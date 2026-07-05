@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TablePropertyDerivedValuesTests: XCTestCase {
    func testLoadDecodesPageBreakHeaderRepeatAndRowCellCounts() throws {
        let payload = tablePropertyPayload(property: 0b101, rowCellCounts: [2, 4, 4])

        let tableProperty = try HwpTableProperty.load(payload, HwpVersion(5, 0, 3, 0))

        expect(tableProperty.rowCount) == 3
        expect(tableProperty.columnCount) == 4
        expect(tableProperty.pageBreakMode) == .byCell
        expect(tableProperty.repeatsHeaderRow) == true
        expect(tableProperty.rowCellCounts) == [2, 4, 4]
        expect(tableProperty.borderFillId) == 1
        expect(tableProperty.validZoneInfoSize) == 0
    }

    func testPageBreakModeCoversAllPropertyBitPatterns() {
        var tableProperty = HwpTableProperty()

        tableProperty.property = 0
        expect(tableProperty.pageBreakMode) == HwpTableProperty.HwpTablePageBreakMode.none
        tableProperty.property = 1
        expect(tableProperty.pageBreakMode) == .byCell
        tableProperty.property = 2
        expect(tableProperty.pageBreakMode) == .split
        // 표 76에 정의되지 않은 bit 조합(3)은 none으로 fallback한다.
        tableProperty.property = 3
        expect(tableProperty.pageBreakMode) == HwpTableProperty.HwpTablePageBreakMode.none
    }

    func testRepeatsHeaderRowReadsOnlyBitTwo() {
        var tableProperty = HwpTableProperty()

        tableProperty.property = 0b100
        expect(tableProperty.repeatsHeaderRow) == true
        tableProperty.property = 0b011
        expect(tableProperty.repeatsHeaderRow) == false
    }

    func testRowCellCountsReturnsEmptyForMisalignedRowSize() {
        var tableProperty = HwpTableProperty()
        tableProperty.rowSize = [2, 0, 4]

        expect(tableProperty.rowCellCounts) == []
    }
}

private func tablePropertyPayload(property: UInt32, rowCellCounts: [UInt16]) -> Data {
    var data = Data()
    data.append(littleEndianData(property))
    data.append(littleEndianData(UInt16(rowCellCounts.count))) // row count
    data.append(littleEndianData(UInt16(4))) // column count
    for _ in 0 ..< 5 { // cell spacing + 4방향 여백
        data.append(littleEndianData(Int16(0)))
    }
    for cellCount in rowCellCounts {
        data.append(littleEndianData(cellCount))
    }
    data.append(littleEndianData(UInt16(1))) // border fill id
    data.append(littleEndianData(UInt16(0))) // zone info size (5.0.1.0 이상)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
