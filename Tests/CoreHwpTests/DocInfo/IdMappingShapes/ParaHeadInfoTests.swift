@testable import CoreHwp
import Nimble
import XCTest

/// 표 39 문단 머리 정보 12바이트의 타입 접근자 (#152) — 실문서 핀과 합성
/// 입력을 가른다. 정렬(bit 0-1)·거리 종류(bit 4)의 비기본값은 한글.app으로
/// 만든 `outline-numbering` 쌍이 실물 근거다.
final class ParaHeadInfoTests: XCTestCase {
    // MARK: - 실문서

    /// 한글.app 12.30 개요 번호 사용자 정의(2026-09-05)의 비기본값 — 1수준 오른쪽
    /// 정렬·번호 너비/자동 내어쓰기 해제·너비 조정 2pt·본문과의 간격 10pt·로마
    /// 대문자, 2수준 가운데 정렬. HWPX 쌍의 `align="RIGHT" useInstWidth="0"
    /// autoIndent="0" widthAdjust="200" textOffsetType="HWPUNIT" textOffset="1000"
    /// numFormat="ROMAN_CAPITAL"`·`align="CENTER"`와 같은 값이다.
    func testOutlineNumberingFixturePinsNonDefaultAlignmentAndOffsetType() throws {
        for hwp in [
            try openHwp(#file, "outline-numbering"), try openHwpx(#file, "outline-numbering"),
        ] {
            let definitions = hwp.docInfo.idMappings.numberingArray
            expect(definitions.count) == 2
            let custom = try XCTUnwrap(definitions.last)
            let first = try XCTUnwrap(custom.formatArray[0].paraHeadInfo)
            expect(first.property) == 0x52
            expect(first.alignment) == HwpParaHeadAlignment.right
            expect(first.useInstWidth) == false
            expect(first.autoIndent) == false
            expect(first.textOffsetType) == HwpParaHeadTextOffsetType.hwpUnit
            expect(first.textOffset) == 1000
            expect(first.widthAdjust) == 200
            expect(first.numberFormat) == 2
            expect(first.charShapeId) == -1

            let second = try XCTUnwrap(custom.formatArray[1].paraHeadInfo)
            expect(second.property) == 0x10D
            expect(second.alignment) == HwpParaHeadAlignment.center
            expect(second.textOffsetType) == HwpParaHeadTextOffsetType.percent
            expect(second.textOffset) == 50
            expect(second.numberFormat) == 8
            // 한글 기본 정의는 그대로다 — 문단 번호 문단이 이쪽을 참조한다.
            let base = try XCTUnwrap(definitions.first?.formatArray[0].paraHeadInfo)
            expect(base.property) == 0x0C
        }
    }

    /// 헌법주석 개요 번호 정의 1-7수준 — 번호 종류 bit 5-8이 로마 대문자(2)·
    /// 숫자(0)·한글 가나다(8)를 번갈아 쓰고 나머지 필드는 전 수준 동일하다.
    func testLegacyOutlineDefinitionLevelsDecodeTable39Fields() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let numbering = try XCTUnwrap(hwp.docInfo.idMappings.numberingArray.first)
        let infos = try numbering.formatArray.map { try XCTUnwrap($0.paraHeadInfo) }

        expect(infos.map(\.numberFormat)) == [2, 0, 8, 0, 8, 0, 8]
        expect(infos.map(\.property)) == [0x4C, 0x0C, 0x10C, 0x0C, 0x10C, 0x0C, 0x10C]
        for info in infos {
            expect(info.alignment) == HwpParaHeadAlignment.left
            expect(info.useInstWidth) == true
            expect(info.autoIndent) == true
            expect(info.textOffsetType) == HwpParaHeadTextOffsetType.percent
            expect(info.textOffset) == 50
            expect(info.widthAdjust) == 0
            expect(info.charShapeId) == -1
        }
        // 5.0.2.2 저장본이라 확장 수준 배열이 없다.
        expect(numbering.extendedFormatArray).to(beNil())
    }

    /// 빈 문서 기본 정의(`HwpIdMappings`)의 실측 근거 — `^1.` 0x0C · `^2.` 0x10C ·
    /// `^7` 0x2C · 확장 수준 0x08(`useInstWidth` 꺼짐).
    func testBlankDocumentDefaultsDecodeNumberFormatAndWidthFlag() throws {
        let numbering = try XCTUnwrap(HwpIdMappings().numberingArray.first)
        let infos = try numbering.formatArray.map { try XCTUnwrap($0.paraHeadInfo) }
        let extended = try XCTUnwrap(numbering.extendedFormatArray)
            .map { try XCTUnwrap($0.paraHeadInfo) }

        expect(infos.map(\.numberFormat)) == [0, 8, 0, 8, 0, 8, 1]
        expect(infos.allSatisfy(\.useInstWidth)) == true
        expect(extended.map(\.property)) == [8, 8, 8]
        expect(extended.allSatisfy { !$0.useInstWidth && $0.autoIndent }) == true
        expect(extended.allSatisfy { $0.textOffset == 50 && $0.charShapeId == -1 }) == true
    }

    /// 디코더는 인코더의 거울상이다 — 전 픽스처의 번호 정의·글머리표 12바이트가
    /// 왕복한다.
    func testFixtureBytesRoundTripThroughEncoder() throws {
        var formatCount = 0
        var bulletCount = 0
        for fixture in try FixtureLoader.loadAll() where fixture.manifest.expectedError == nil {
            let hwp = try HwpFile(fromPath: fixture.documentURL.path)
            for numbering in hwp.docInfo.idMappings.numberingArray {
                let formats = numbering.formatArray + (numbering.extendedFormatArray ?? [])
                for format in formats {
                    let info = try XCTUnwrap(format.paraHeadInfo)
                    expect(info.bytes).to(
                        equal(format.property), description: fixture.manifest.id
                    )
                    formatCount += 1
                }
            }
            for bullet in hwp.docInfo.idMappings.bulletArray {
                let info = try XCTUnwrap(bullet.paraHeadInfo)
                expect(info.infoBytes).to(equal(bullet.info), description: fixture.manifest.id)
                expect(info.charShapeId) == bullet.headCharShapeId
                bulletCount += 1
            }
        }
        // 정의는 픽스처마다 최소 하나(수준 7개)라 대조가 공허하지 않다.
        expect(formatCount) >= 30 * 7
        expect(bulletCount) >= 1
    }

    /// noori 글머리표 `-` — `info` 8바이트 `08 00 00 00 00 00 32 00`은 번호 정의와
    /// 같은 표 39 배치다 (`useInstWidth` 꺼짐 · `autoIndent` 켜짐 · 비율 50%).
    func testNooriBulletSharesTheParaHeadLayout() throws {
        let hwp = try openHwp(#file, "noori")
        let bullet = try XCTUnwrap(hwp.docInfo.idMappings.bulletArray.first)
        let info = try XCTUnwrap(bullet.paraHeadInfo)

        expect(bullet.char) == "-"
        expect(info.property) == 0x08
        expect(info.useInstWidth) == false
        expect(info.autoIndent) == true
        expect(info.alignment) == HwpParaHeadAlignment.left
        expect(info.textOffsetType) == HwpParaHeadTextOffsetType.percent
        expect(info.textOffset) == 50
        expect(info.charShapeId) == -1
    }

    // MARK: - 합성

    /// 표 40 필드를 받는 init이 비트를 합성하고 디코더가 같은 값을 돌려준다 —
    /// 실문서 대조는 위 `testOutlineNumberingFixturePinsNonDefaultAlignmentAndOffsetType`이
    /// 하고, 여기서는 실물에 없는 조합(번호 모양 14·음수 너비 보정·글자 모양 ID 7)의
    /// 합성 왕복만 본다.
    func testTypedInitComposesTable40BitsAndRoundTrips() {
        let info = HwpParaHeadInfo(
            alignment: .right,
            useInstWidth: false,
            autoIndent: false,
            textOffsetType: .hwpUnit,
            numberFormat: 14,
            widthAdjust: -3,
            textOffset: 500,
            charShapeId: 7
        )

        // bit 0-1 = 2, bit 4 = 1, bit 5-8 = 14.
        expect(info.property) == 0b1_1101_0010
        expect(info.alignment) == HwpParaHeadAlignment.right
        expect(info.useInstWidth) == false
        expect(info.autoIndent) == false
        expect(info.textOffsetType) == HwpParaHeadTextOffsetType.hwpUnit
        expect(info.numberFormat) == 14
        expect(info.bytes) == [
            0xD2, 0x01, 0x00, 0x00, 0xFD, 0xFF, 0xF4, 0x01, 0x07, 0x00, 0x00, 0x00,
        ]
        expect(HwpParaHeadInfo(bytes: info.bytes)) == info
        expect(HwpParaHeadInfo(infoBytes: info.infoBytes, charShapeId: 7)) == info

        let center = HwpParaHeadInfo(
            alignment: .center, useInstWidth: true, autoIndent: true,
            textOffsetType: .percent, numberFormat: 0, textOffset: 50
        )
        expect(center.property) == 0b1101
        expect(center.alignment) == HwpParaHeadAlignment.center
    }

    /// 번호 모양은 네 비트에 담긴다 — 표 41 밖 코드(`SYMBOL` 0x80)는 접히고
    /// 음수는 0이다 (HWPX 매퍼와 같은 규약).
    func testNumberFormatFoldsIntoFourBits() {
        let symbol = HwpParaHeadInfo(
            alignment: .left, useInstWidth: true, autoIndent: true,
            textOffsetType: .percent, numberFormat: 0x80, textOffset: 50
        )
        expect(symbol.numberFormat) == 0
        expect(symbol.property) == 0x0C

        let negative = HwpParaHeadInfo(
            alignment: .left, useInstWidth: true, autoIndent: true,
            textOffsetType: .percent, numberFormat: -1, textOffset: 50
        )
        expect(negative.numberFormat) == 0
    }

    /// 정렬 raw 3은 스펙에 정의가 없다 — 값은 보존하되 enum은 nil이다.
    func testUndefinedAlignmentRawValueIsPreservedWithoutACase() throws {
        let info = try XCTUnwrap(HwpParaHeadInfo(bytes: [
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x32, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        ]))
        expect(info.alignmentRawValue) == 3
        expect(info.alignment).to(beNil())
        expect(info.property) == 3
    }

    /// 12바이트 미만은 nil이고 넘치는 꼬리는 무시한다 — 0으로 메우면 글자 모양
    /// ID 0이 실재하는 참조가 되어 바탕글(-1)과 구별되지 않는다.
    func testShortBytesAreNilAndTrailingBytesAreIgnored() throws {
        let twelve: [BYTE] = [
            0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x32, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        ]
        expect(HwpParaHeadInfo(bytes: Array(twelve.prefix(11)))).to(beNil())
        expect(HwpParaHeadInfo(bytes: [])).to(beNil())
        expect(HwpParaHeadInfo(infoBytes: Array(twelve.prefix(7)), charShapeId: -1)).to(beNil())

        let trailing = try XCTUnwrap(HwpParaHeadInfo(bytes: twelve + [0xAA, 0xBB]))
        expect(trailing.bytes) == twelve
        expect(trailing.charShapeId) == -1

        let synthesized = HwpNumberingFormat(property: [1, 2], formatLength: 0, format: "")
        expect(synthesized.paraHeadInfo).to(beNil())
    }

    /// 기본 init은 빈 수준 슬롯의 값이다 — 속성 0 · 거리 0 · 바탕글(-1).
    func testDefaultInitIsTheEmptyLevelSlot() {
        let empty = HwpParaHeadInfo()
        expect(empty.property) == 0
        expect(empty.textOffset) == 0
        expect(empty.widthAdjust) == 0
        expect(empty.charShapeId) == -1
        expect(empty.bytes) == [0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]
        expect(HwpParaHeadInfo.byteCount) == 12
    }
}
