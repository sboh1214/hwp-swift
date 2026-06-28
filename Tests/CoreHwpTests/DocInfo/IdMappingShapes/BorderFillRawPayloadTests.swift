@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BorderFillRawPayloadTests: XCTestCase {
    func testBorderFillInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let slicedPayload = (Data([0xFF, 0xEE]) + borderFillPayload()).dropFirst(2)
        var reader = DataReader(slicedPayload)

        let borderFill = try HwpBorderFill(&reader)

        expect(borderFill.rawPayload) == slicedPayload
        expect(borderFill.property) == 0x1234
        expect(borderFill.fillInfo) == [0xAA, 0xBB]
        expect(reader.isEOF) == true
    }

    func testBorderFillPreservesRawPayloadWithoutChangingEquality() throws {
        let payload = borderFillPayload()

        let borderFill = try HwpBorderFill.load(payload)
        var sameBorderFill = borderFill
        sameBorderFill.rawPayload = Data([0xCA, 0xFE])

        expect(borderFill.rawPayload) == payload
        expect(borderFill.property) == 0x1234
        expect(borderFill.borderType) == [1, 2, 3, 4]
        expect(borderFill.borderThickness) == [5, 6, 7, 8]
        expect(borderFill.borderColor.map(\.red)) == [0x11, 0x44, 0x77, 0xAA]
        expect(borderFill.diagonalType) == 9
        expect(borderFill.diagonalThickness) == 10
        expect(borderFill.diagonalColor) == HwpColor(0xDD, 0xEE, 0xFF)
        expect(borderFill.fillInfo) == [0xAA, 0xBB]
        expect(sameBorderFill) == borderFill
    }

    func testBorderFillAcceptsEmptyFillInfoAndPreservesRawPayload() throws {
        let payload = borderFillPayload(fillInfo: Data())

        let borderFill = try HwpBorderFill.load(payload)

        expect(borderFill.rawPayload) == payload
        expect(borderFill.fillInfo).to(beEmpty())
    }

    func testBorderFillRejectsTruncatedFixedFieldsWithTypedError() {
        let scenarios = [
            BorderFillTruncationScenario(
                name: "property",
                payload: Data([0x34]),
                expectedBytes: 2,
                actualBytes: 1
            ),
            BorderFillTruncationScenario(
                name: "borderType",
                payload: littleEndianData(UInt16(0x1234)) + Data([1, 2, 3]),
                expectedBytes: 4,
                actualBytes: 3
            ),
            BorderFillTruncationScenario(
                name: "diagonalColor",
                payload: Data(borderFillPayload(fillInfo: Data()).prefix(31)),
                expectedBytes: 4,
                actualBytes: 3
            ),
        ]

        for scenario in scenarios {
            expect {
                _ = try HwpBorderFill.load(scenario.payload)
            }.to(throwError { error in
                guard case let HwpError.truncatedData(expected, actual) = error else {
                    return fail("Expected truncatedData for \(scenario.name), got \(error)")
                }
                expect(expected) == scenario.expectedBytes
                expect(actual) == scenario.actualBytes
            })
        }
    }

    func testBorderFillDefaults() {
        expect(HwpBorderFill().fillInfo).to(beEmpty())
        expect(HwpBorderFill(fillInfo: [1, 2, 3]).fillInfo) == [1, 2, 3]
    }
}

private struct BorderFillTruncationScenario {
    let name: String
    let payload: Data
    let expectedBytes: Int
    let actualBytes: Int
}

private func borderFillPayload(fillInfo: Data = Data([0xAA, 0xBB])) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt16(0x1234)))
    data.append(Data([1, 2, 3, 4]))
    data.append(Data([5, 6, 7, 8]))
    data.append(littleEndianData(UInt32(0x0033_2211)))
    data.append(littleEndianData(UInt32(0x0066_5544)))
    data.append(littleEndianData(UInt32(0x0099_8877)))
    data.append(littleEndianData(UInt32(0x00CC_BBAA)))
    data.append(Data([9, 10]))
    data.append(littleEndianData(UInt32(0x00FF_EEDD)))
    data.append(fillInfo)
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
