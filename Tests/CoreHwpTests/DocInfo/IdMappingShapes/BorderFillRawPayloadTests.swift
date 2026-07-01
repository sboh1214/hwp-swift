@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class BorderFillRawPayloadTests: XCTestCase {
    func testBorderFillInitializerPreservesRawPayloadWithNonZeroDataStartIndex() throws {
        let slicedPayload = concatenatedData(Data([0xFF, 0xEE]), borderFillPayload()).dropFirst(2)
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
        expect(borderFill.borderLineArray.map(\.type)) == [
            .line,
            .longDotLine,
            .dotLine,
            .dashDot,
        ]
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
                name: "borderLine.color",
                payload: concatenatedData(littleEndianData(UInt16(0x1234)), Data([1, 2, 3])),
                expectedBytes: 4,
                actualBytes: 1
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

    func testBorderLineTypeUsesActualRawValueMapping() {
        expect(HwpBorderType.none.rawValue) == 0
        expect(HwpBorderType.line.rawValue) == 1
        expect(HwpBorderType.longDotLine.rawValue) == 2
        expect(HwpBorderType.dotLine.rawValue) == 3
        expect(HwpBorderType.doubleLine.rawValue) == 8
        expect(HwpBorderType.wave.rawValue) == 12
    }

    func testHancomGeneratedDefaultBorderFillUsesNoneLineType() throws {
        let hwp = try openHwp(#file, "text-box")
        let borderFills = hwp.docInfo.idMappings.borderFillArray

        expect(borderFills).to(haveCount(2))
        for borderFill in borderFills {
            expect(borderFill.borderType) == [0, 0, 0, 0]
            expect(borderFill.borderThickness) == [0, 0, 0, 0]
            expect(borderFill.borderColor) == Array(repeating: HwpColor(0, 0, 0), count: 4)
            expect(borderFill.borderLineArray.map(\.type)) == [
                HwpBorderType.none,
                HwpBorderType.none,
                HwpBorderType.none,
                HwpBorderType.none,
            ]
        }
    }

    func testMigratedNooriFixtureConfirmsInterleavedBorderFillOrder() throws {
        let hwp = try openHwp(#file, "noori")
        let borderFill = hwp.docInfo.idMappings.borderFillArray[4]

        expect(borderFill.rawPayload.prefix(26)) == Data([
            0x00, 0x00,
            0x01, 0x07, 0x1B, 0x17, 0x60, 0x00,
            0x01, 0x07, 0x1B, 0x17, 0x60, 0x00,
            0x01, 0x07, 0x1B, 0x17, 0x60, 0x00,
            0x01, 0x07, 0x1B, 0x17, 0x60, 0x00,
        ])
        expect(borderFill.borderType) == [1, 1, 1, 1]
        expect(borderFill.borderThickness) == [7, 7, 7, 7]
        expect(borderFill.borderColor) == Array(repeating: HwpColor(0x1B, 0x17, 0x60), count: 4)
        expect(borderFill.borderLineArray.map(\.type)) == [.line, .line, .line, .line]
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
    data.append(borderLinePayload(type: 1, thickness: 5, color: 0x0033_2211))
    data.append(borderLinePayload(type: 2, thickness: 6, color: 0x0066_5544))
    data.append(borderLinePayload(type: 3, thickness: 7, color: 0x0099_8877))
    data.append(borderLinePayload(type: 4, thickness: 8, color: 0x00CC_BBAA))
    data.append(Data([9, 10]))
    data.append(littleEndianData(UInt32(0x00FF_EEDD)))
    data.append(fillInfo)
    return data
}

private func borderLinePayload(type: UInt8, thickness: UInt8, color: UInt32) -> Data {
    concatenatedData(Data([type, thickness]), littleEndianData(color))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
