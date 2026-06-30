@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TableCellHeaderPropertyRealFixtureTests: XCTestCase {
    func testNooriFixtureDecodesTableCellListHeaderHighBits() throws {
        let headers = try nooriTableCellHeaders()
        let propertyValues = Set(headers.map(\.property))

        expect(propertyValues).to(contain(0x0020_0000))
        expect(propertyValues).to(contain(0x0040_0000))

        let centerHeaders = headers.filter { $0.property == 0x0020_0000 }
        let bottomHeaders = headers.filter { $0.property == 0x0040_0000 }

        expect(centerHeaders).notTo(beEmpty())
        expect(bottomHeaders).notTo(beEmpty())
        expect(centerHeaders.allSatisfy { $0.propertyInfo.verticalAlignment == .center }) == true
        expect(centerHeaders.allSatisfy { $0.propertyInfo.verticalAlignmentRawValue == 1 }) == true
        expect(bottomHeaders.allSatisfy { $0.propertyInfo.verticalAlignment == .bottom }) == true
        expect(bottomHeaders.allSatisfy { $0.propertyInfo.verticalAlignmentRawValue == 2 }) == true
        expect(headers.allSatisfy { $0.propertyInfo.textDirectionRawValue == 0 }) == true
        expect(headers.allSatisfy { $0.propertyInfo.textWrapRawValue == 0 }) == true
    }

    func testNooriFixturePreservesCellHeaderWidthRefSeparatelyFromListAttr() throws {
        let headers = try nooriTableCellHeaders()
        let widthRefs = Set(headers.map(\.listHeaderWidthRef))
        let headerWithWidthRef = try nooriTableCellHeader(widthRef: 0x0500, in: headers)

        expect(widthRefs).to(contain(UInt16(0x0000)))
        expect(widthRefs).to(contain(UInt16(0x0400)))
        expect(widthRefs).to(contain(UInt16(0x0500)))
        expect(headerWithWidthRef.property) == 0x0020_0000
        expect(headerWithWidthRef.propertyInfo.verticalAlignment) == .center
        expect(headerWithWidthRef.cellPropertyInfo.rawValue) == 0x0500
        expect(headerWithWidthRef.isHeader) == false
    }
}

private func nooriTableCellHeaders() throws -> [HwpTableCellHeader] {
    let hwp = try openHwp(#file, "noori")
    let headers = FixtureDerivedValues.tables(from: hwp).flatMap(\.cellArray).map(\.header)

    expect(headers).notTo(beEmpty())
    return headers
}

private func nooriTableCellHeader(
    widthRef: UInt16,
    in headers: [HwpTableCellHeader]
) throws -> HwpTableCellHeader {
    guard let header = headers.first(where: { $0.listHeaderWidthRef == widthRef }) else {
        fail("Expected noori fixture to contain table cell widthRef \(widthRef)")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue)
    }

    return header
}
