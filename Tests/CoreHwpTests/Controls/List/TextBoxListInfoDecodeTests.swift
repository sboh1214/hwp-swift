@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class TextBoxListInfoDecodeTests: XCTestCase {
    func testDecodeReadsMarginsAndMaxTextWidth() {
        var payload = Data()
        for margin in [Int16(-100), 200, 300, -400] {
            payload.append(littleEndianData(margin))
        }
        payload.append(littleEndianData(UInt32(42520)))

        let info = HwpTextBoxListInfo.decode(from: payload)

        expect(info?.leftMargin) == -100
        expect(info?.rightMargin) == 200
        expect(info?.topMargin) == 300
        expect(info?.bottomMargin) == -400
        expect(info?.maxTextWidth) == 42520
    }

    func testDecodeReturnsNilForPayloadShorterThan12Bytes() {
        expect(HwpTextBoxListInfo.decode(from: Data(repeating: 0, count: 11))).to(beNil())
        expect(HwpTextBoxListInfo.decode(from: Data())).to(beNil())
    }

    func testDecodeIgnoresBytesBeyondTheFixedLayout() {
        var payload = Data(repeating: 0, count: 8)
        payload.append(littleEndianData(UInt32(999)))
        payload.append(contentsOf: [0xCA, 0xFE])

        let info = HwpTextBoxListInfo.decode(from: payload)

        expect(info?.maxTextWidth) == 999
        expect(info?.leftMargin) == 0
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
