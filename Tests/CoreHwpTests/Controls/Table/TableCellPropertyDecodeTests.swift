@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TableCellPropertyDecodeTests: XCTestCase {
    func testDecodeReadsAllFieldsFromTrailingPayload() {
        let payload = cellPropertyPayload(
            columnAddress: 2,
            rowAddress: 1,
            columnSpan: 3,
            rowSpan: 2,
            width: 8504,
            height: 1770,
            margins: [141, 141, 283, -100],
            borderFillId: 4
        )

        let property = HwpTableCellProperty.decode(from: payload)

        expect(property?.columnAddress) == 2
        expect(property?.rowAddress) == 1
        expect(property?.columnSpan) == 3
        expect(property?.rowSpan) == 2
        expect(property?.width) == 8504
        expect(property?.height) == 1770
        expect(property?.marginArray) == [141, 141, 283, -100]
        expect(property?.borderFillId) == 4
    }

    func testDecodeClampsZeroSpansToOne() {
        let payload = cellPropertyPayload(columnSpan: 0, rowSpan: 0)

        let property = HwpTableCellProperty.decode(from: payload)

        expect(property?.columnSpan) == 1
        expect(property?.rowSpan) == 1
    }

    func testDecodeReturnsNilForPayloadShorterThan26Bytes() {
        let payload = cellPropertyPayload()

        expect(HwpTableCellProperty.decode(from: Data(payload.dropLast()))).to(beNil())
        expect(HwpTableCellProperty.decode(from: Data())).to(beNil())
    }

    func testDecodeIgnoresExtraTrailingBytes() {
        var payload = cellPropertyPayload(columnAddress: 7)
        payload.append(contentsOf: [0xCA, 0xFE, 0xBA, 0xBE])

        let property = HwpTableCellProperty.decode(from: payload)

        expect(property?.columnAddress) == 7
        expect(property?.borderFillId) == 1
    }
}

private func cellPropertyPayload(
    columnAddress: UInt16 = 0,
    rowAddress: UInt16 = 0,
    columnSpan: UInt16 = 1,
    rowSpan: UInt16 = 1,
    width: UInt32 = 100,
    height: UInt32 = 100,
    margins: [Int16] = [0, 0, 0, 0],
    borderFillId: UInt16 = 1
) -> Data {
    var data = Data()
    data.append(littleEndianData(columnAddress))
    data.append(littleEndianData(rowAddress))
    data.append(littleEndianData(columnSpan))
    data.append(littleEndianData(rowSpan))
    data.append(littleEndianData(width))
    data.append(littleEndianData(height))
    for margin in margins {
        data.append(littleEndianData(margin))
    }
    data.append(littleEndianData(borderFillId))
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
