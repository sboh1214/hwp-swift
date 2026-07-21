@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FootnoteShapeRawPayloadTests: XCTestCase {
    func testFootnoteShapePreservesSymbolRawValuesAndPayloads() throws {
        let payload = footnoteShapePayload(
            userSymbol: 0x2020,
            decorationHead: 0x005B,
            decorationTail: 0x005D
        )

        let shape = try HwpFootnoteShape.load(payload)
        var sameShape = shape
        sameShape.userSymbolRawPayload = Data([0xCA])
        sameShape.decorationHeadRawPayload = Data([0xFE])
        sameShape.decorationTailRawPayload = Data([0xED])

        expect(shape.rawPayload) == payload
        expect(shape.userSymbol) == "\u{2020}"
        expect(shape.userSymbolRawValue) == 0x2020
        expect(shape.userSymbolRawPayload) == littleEndianData(WCHAR(0x2020))
        expect(shape.decorationHead) == "["
        expect(shape.decorationHeadRawValue) == 0x005B
        expect(shape.decorationHeadRawPayload) == littleEndianData(WCHAR(0x005B))
        expect(shape.decorationTail) == "]"
        expect(shape.decorationTailRawValue) == 0x005D
        expect(shape.decorationTailRawPayload) == littleEndianData(WCHAR(0x005D))
        expect(sameShape) == shape
    }

    func testFootnoteShapeSymbolRawPayloadsSurviveCodableRoundTrip() throws {
        let payload = footnoteShapePayload(
            userSymbol: 0x2020,
            decorationHead: 0x005B,
            decorationTail: 0x005D
        )

        let decoded = try decodeRoundTrip(HwpFootnoteShape.load(payload))

        expect(decoded.rawPayload) == payload
        expect(decoded.userSymbolRawValue) == 0x2020
        expect(decoded.userSymbolRawPayload) == littleEndianData(WCHAR(0x2020))
        expect(decoded.decorationHeadRawValue) == 0x005B
        expect(decoded.decorationHeadRawPayload) == littleEndianData(WCHAR(0x005B))
        expect(decoded.decorationTailRawValue) == 0x005D
        expect(decoded.decorationTailRawPayload) == littleEndianData(WCHAR(0x005D))
    }

    func testFootnoteShapeRejectsInvalidSymbolWithTypedError() {
        let payload = footnoteShapePayload(userSymbol: 0xD800)

        expect {
            _ = try HwpFootnoteShape.load(payload)
        }.to(throwError { error in
            guard case let HwpError.invalidUnicodeScalar(value) = error else {
                return fail("Expected invalidUnicodeScalar, got \(error)")
            }
            expect(value) == 0xD800
        })
    }

    func testDividerInfoDecodesNarrowBlackSeparatorAsNarrowNotWide() throws {
        // 28바이트 narrow 레코드에서 구분선 종류/굵기는 offset 20·21, 검정 색상은
        // 22-25다. 색상 0이면 wide 해석의 type/thickness(offset 22·23)도 0으로
        // 유효해, 예전엔 크기 28로 wide를 골라 필드가 2바이트 밀렸다 (R44 #1).
        let payload = narrowBlackSeparatorPayload(dividerType: 1, dividerThickness: 2)
        let shape = try HwpFootnoteShape.load(payload)
        let info = try XCTUnwrap(shape.dividerInfo)

        expect(payload.count) == 28
        expect(info.type) == 1
        expect(info.thickness) == 2
        expect(info.color) == HwpColor(0)
    }
}

private func narrowBlackSeparatorPayload(dividerType: UInt8, dividerThickness: UInt8) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(WCHAR(0)))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(dividerType))
    data.append(littleEndianData(dividerThickness))
    data.append(littleEndianData(COLORREF(0)))
    data.append(Data([0, 0]))
    return data
}

private func footnoteShapePayload(
    userSymbol: WCHAR = 0,
    decorationHead: WCHAR = 0,
    decorationTail: WCHAR = 0,
    rawTrailing: Data = Data([0, 0])
) -> Data {
    var data = Data()
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(userSymbol))
    data.append(littleEndianData(decorationHead))
    data.append(littleEndianData(decorationTail))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(UInt8(0)))
    data.append(littleEndianData(COLORREF(0)))
    data.append(rawTrailing)
    return data
}

private func decodeRoundTrip<T: HwpPrimitive>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
