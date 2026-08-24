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

    func testFootnoteEndnoteFixtureDividerDecodesAsWide() throws {
        // 실 저장본은 길이 4 byte(wide)다 — foot 레코드를 narrow로 읽으면 종류
        // index가 27(offset 20)로 범위를 벗어나 wide만 유효하고, wide 기준에서
        // 종류/굵기/색이 정상값(1·1·검정)이 된다 (R45 #1).
        let hwp = try openHwp(#file, "footnote-endnote")
        let sectionDef = hwp.sectionArray
            .flatMap(\.paragraph)
            .compactMap { paragraph -> HwpSectionDef? in
                paragraph.ctrlHeaderArray?.compactMap { ctrl -> HwpSectionDef? in
                    if case let .section(def) = ctrl {
                        return def
                    }
                    return nil
                }.first
            }
            .first
        let info = try XCTUnwrap(sectionDef?.footNoteShape.dividerInfo)

        expect(info.type) == 1
        expect(info.thickness) == 1
        expect(info.color) == HwpColor(0)
        expect(info.marginTop) == 850
    }
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

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}
