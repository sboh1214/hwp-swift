@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FootnoteDividerInfoDecodeTests: XCTestCase {
    func testDecodeReadsWideFourByteLengthVariant() {
        let info = HwpFootnoteDividerInfo.decode(from: wideDividerPayload(length: 4000))

        expect(info?.length) == 4000
        expect(info?.marginTop) == 850
        expect(info?.marginBottom) == 567
        expect(info?.spacingBetweenNotes) == 283
        expect(info?.type) == 1
        expect(info?.thickness) == 2
        expect(info?.color) == HwpColor(0x20, 0x50, 0x80)
    }

    func testDecodeReadsNarrowTwoByteLengthVariant() {
        let info = HwpFootnoteDividerInfo.decode(from: narrowDividerPayload(length: 2000))

        expect(info?.length) == 2000
        expect(info?.marginTop) == 100
        expect(info?.marginBottom) == 200
        expect(info?.spacingBetweenNotes) == 300
        expect(info?.type) == 3
        expect(info?.thickness) == 5
        expect(info?.color) == HwpColor(255, 0, 0)
    }

    func testDecodeTreatsNonPositiveLengthAsAutomatic() {
        let negative = HwpFootnoteDividerInfo.decode(from: wideDividerPayload(length: -1))
        let zero = HwpFootnoteDividerInfo.decode(from: narrowDividerPayload(length: 0))

        expect(negative).notTo(beNil())
        expect(negative?.length).to(beNil())
        expect(zero).notTo(beNil())
        expect(zero?.length).to(beNil())
    }

    func testDecodeReturnsNilWhenBothVariantsHaveInvalidLineIndexes() {
        // wide type(offset 22) = 60, narrow type(offset 20) = spacing 하위 byte = 60
        let payload = wideDividerPayload(length: 100, type: 60, spacing: 60)

        expect(HwpFootnoteDividerInfo.decode(from: payload)).to(beNil())
    }

    func testDecodePrefersWideVariantWhenBothValidRegardlessOfSize() {
        // spacing 3 → narrow type 후보(offset 20=3)와 wide type(offset 22=1)이 모두
        // 유효한 모호한 28바이트 payload. 길이 필드는 4 byte 고정이므로 크기와
        // 무관하게 wide로 확정한다 — hwplib·hwp-rs 실측 (R45 #1, R44 크기 기반 정정).
        let payload = wideDividerPayload(length: 4000, spacing: 3)
        expect(payload.count) == 28

        let info = HwpFootnoteDividerInfo.decode(from: payload)

        expect(info?.type) == 1
        expect(info?.marginTop) == 850
        expect(info?.length) == 4000
    }

    func testDecodeKeepsWidePreferenceWithExtraTrailing() {
        // 임의 trailing이 붙어 30바이트가 돼도 wide 유지 — 레코드 크기로 폭을
        // 추론하지 않는다 (R45 #1: narrow+trailing을 wide로 오분류하던 것 방지).
        let payload = wideDividerPayload(length: 4000, spacing: 3) + Data([0, 0])
        expect(payload.count) == 30

        let info = HwpFootnoteDividerInfo.decode(from: payload)

        expect(info?.length) == 4000
        expect(info?.marginTop) == 850
        expect(info?.type) == 1
    }

    func testFootnoteShapeExposesNumberingModeRawValueFromPropertyBits() throws {
        let perSection = try HwpFootnoteShape.load(footnoteShapePayload(property: 1 << 10))
        let perPage = try HwpFootnoteShape.load(footnoteShapePayload(property: 2 << 10))
        let masked = try HwpFootnoteShape.load(
            footnoteShapePayload(property: (1 << 9) | (1 << 12))
        )

        expect(perSection.numberingModeRawValue) == 1
        expect(perPage.numberingModeRawValue) == 2
        // bits 10-11 밖의 bit(9, 12)는 무시된다.
        expect(masked.numberingModeRawValue) == 0
    }
}

private func dividerPayloadPrefix(property: UInt32 = 0) -> Data {
    var data = Data()
    data.append(littleEndianData(property))
    data.append(littleEndianData(UInt16(0))) // user symbol
    data.append(littleEndianData(UInt16(0))) // decoration head
    data.append(littleEndianData(UInt16(0))) // decoration tail
    data.append(littleEndianData(UInt16(1))) // start number
    return data
}

private func wideDividerPayload(
    length: Int32,
    type: UInt8 = 1,
    spacing: Int16 = 283
) -> Data {
    var data = dividerPayloadPrefix()
    data.append(littleEndianData(length))
    data.append(littleEndianData(Int16(850))) // margin top
    data.append(littleEndianData(Int16(567))) // margin bottom
    data.append(littleEndianData(spacing))
    data.append(type)
    data.append(UInt8(2)) // thickness
    data.append(littleEndianData(UInt32(0x0080_5020)))
    return data
}

private func narrowDividerPayload(length: Int16) -> Data {
    var data = dividerPayloadPrefix()
    data.append(littleEndianData(length))
    data.append(littleEndianData(Int16(100))) // margin top
    data.append(littleEndianData(Int16(200))) // margin bottom
    data.append(littleEndianData(Int16(300))) // spacing between notes
    data.append(UInt8(3)) // type
    data.append(UInt8(5)) // thickness
    data.append(littleEndianData(UInt32(0x0000_00FF)))
    return data
}

private func footnoteShapePayload(property: UInt32) -> Data {
    var data = narrowDividerPayload(length: 0)
    data.replaceSubrange(0 ..< 4, with: littleEndianData(property))
    data.append(contentsOf: [0, 0]) // 필수 unknown trailing
    return data
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
