@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:pageNum` → `.pageNumberPosition` typed 매핑 — 속성 대응표·표 147 payload
/// 합성·미소비 자식 강등을 합성 XML로 고정한다 (#135).
final class HwpxPageNumberMapperTests: XCTestCase {
    private struct UnexpectedControl: Error {
        let ctrls: [HwpCtrlId]
    }

    /// 빈 구역 뒤에 `hp:ctrl` 하나를 가진 문단을 붙여 그 컨트롤을 꺼낸다.
    private func mapPageNumber(
        _ element: String
    ) throws -> (paragraph: HwpParagraph, position: HwpPageNumberPosition) {
        let section = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody + """
            <hp:p><hp:run charPrIDRef="7"><hp:ctrl>\(element)</hp:ctrl></hp:run>\
            <hp:linesegarray><hp:lineseg textpos="0" vertpos="0" vertsize="1000" \
            textheight="1000" baseline="850" spacing="600" horzpos="0" \
            horzsize="42520" flags="393216"/></hp:linesegarray></hp:p>
            """
        )
        let paragraph = section.paragraph[1]
        let ctrls = try XCTUnwrap(paragraph.ctrlHeaderArray)
        guard ctrls.count == 1, case let .pageNumberPosition(position) = ctrls[0] else {
            throw UnexpectedControl(ctrls: ctrls)
        }
        return (paragraph, position)
    }

    func testNooriPageNumMapsToTypedControlWithBinaryIdenticalPayload() throws {
        // noori 실저장본 그대로 — HWP 쌍의 pgnp는 property 0x0500, WCHAR 4개 전부 0
        // (Fixtures/noori/manifest.json `pageNumberPositions[0]`).
        let (paragraph, position) = try mapPageNumber(
            "<hp:pageNum pos=\"BOTTOM_CENTER\" formatType=\"DIGIT\" sideChar=\"\"/>"
        )
        let chars = try XCTUnwrap(paragraph.paraText?.charArray)

        // ext21(쪽 번호 위치) → 13. 합성 payload 선두 4바이트가 ctrl id다.
        expect(chars.map(\.value)) == [21, 13]
        expect(chars[0].type) == HwpCharType.extended
        expect(chars[0].inlineControl?.rawControlId)
            == HwpOtherCtrlId.pageNumberPosition.rawValue

        expect(position.otherCtrlId) == HwpOtherCtrlId.pageNumberPosition
        expect(position.property) == 0x0500
        expect(position.propertyInfo.rawValue) == 0x0500
        expect(position.propertyInfo.displayPosition) == 5
        expect(position.propertyInfo.numberFormat) == 0
        expect(position.userSymbol) == 0
        expect(position.headDecoration) == 0
        expect(position.tailDecoration) == 0
        expect(position.unused) == 0
        expect(position.unknown) == 0
        expect(Array(position.rawPayload))
            == [112, 110, 103, 112, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        expect(position.rawTrailing.isEmpty) == true
        expect(position.unknownChildren).to(beEmpty())
        // 분류 가능한 요소는 위치가 확실하므로 lineseg가 유지된다.
        expect(paragraph.paraLineSeg.paraLineSegInternalArray.count) == 1
    }

    func testPositionsMapToTable148Codes() throws {
        // 표 148 bit 8-11: 0 없음, 1~3 위, 4~6 아래, 7/8 바깥쪽, 9/10 안쪽.
        let expected: [(name: String, code: Int)] = [
            ("NONE", 0), ("TOP_LEFT", 1), ("TOP_CENTER", 2), ("TOP_RIGHT", 3),
            ("BOTTOM_LEFT", 4), ("BOTTOM_CENTER", 5), ("BOTTOM_RIGHT", 6),
            ("OUTSIDE_TOP", 7), ("OUTSIDE_BOTTOM", 8), ("INSIDE_TOP", 9), ("INSIDE_BOTTOM", 10),
        ]
        expect(expected.count) == HwpxPageNumberMapper.positions.count
        for entry in expected {
            let (_, position) = try mapPageNumber(
                "<hp:pageNum pos=\"\(entry.name)\" formatType=\"DIGIT\" sideChar=\"\"/>"
            )
            expect(position.propertyInfo.displayPosition)
                .to(equal(entry.code), description: entry.name)
            // property 세 표현이 함께 선다.
            expect(position.property)
                .to(equal(UInt32(entry.code) << 8), description: entry.name)
            expect(position.propertyInfo.rawValue)
                .to(equal(position.property), description: entry.name)
        }
    }

    func testFormatTypesMapToTable134Codes() throws {
        // NumberType1 이름 순서 = 표 134 코드 순서 (HwpNumberFormat이 소비).
        let expected: [(name: String, code: Int)] = [
            ("DIGIT", 0), ("CIRCLED_DIGIT", 1), ("ROMAN_CAPITAL", 2), ("ROMAN_SMALL", 3),
            ("LATIN_CAPITAL", 4), ("LATIN_SMALL", 5), ("CIRCLED_LATIN_CAPITAL", 6),
            ("CIRCLED_LATIN_SMALL", 7), ("HANGUL_SYLLABLE", 8), ("CIRCLED_HANGUL_SYLLABLE", 9),
            ("HANGUL_JAMO", 10), ("CIRCLED_HANGUL_JAMO", 11), ("HANGUL_PHONETIC", 12),
            ("IDEOGRAPH", 13), ("CIRCLED_IDEOGRAPH", 14), ("DECAGON_CIRCLE", 15),
            ("DECAGON_CIRCLE_HANJA", 16), ("SYMBOL", 0x80), ("USER_CHAR", 0x81),
        ]
        expect(expected.count) == HwpxNumberFormatMapper.codes.count
        for entry in expected {
            let (_, position) = try mapPageNumber(
                "<hp:pageNum pos=\"BOTTOM_CENTER\" formatType=\"\(entry.name)\" sideChar=\"\"/>"
            )
            expect(position.propertyInfo.numberFormat)
                .to(equal(entry.code), description: entry.name)
            expect(position.property)
                .to(equal(UInt32(entry.code) | 5 << 8), description: entry.name)
        }
    }

    func testHangulAppMeasuredPairsMapToBinaryProperties() throws {
        // 2026-09-02 한글.app 12.30.0 쪽 번호 매기기 대화상자로 만든 .hwp/.hwpx 쌍
        // 4종 — 같은 문서의 HWPX 속성 ↔ HWP pgnp 속성·4번째 WCHAR
        // (Sources/CoreHwp/Hwpx/AGENTS.md "쪽 번호 위치"). 줄표 넣기는 앞/뒤 장식이
        // 아니라 4번째 WCHAR에만 실렸고 payload는 전부 16바이트였다.
        struct MeasuredPair {
            let pos: String
            let format: String
            let sideChar: String
            let property: UInt32
            let unused: UInt16
        }
        let measured: [MeasuredPair] = [
            MeasuredPair(
                pos: "OUTSIDE_TOP", format: "ROMAN_CAPITAL", sideChar: "-",
                property: 0x0702, unused: 0x2D
            ),
            MeasuredPair(
                pos: "INSIDE_BOTTOM", format: "DECAGON_CIRCLE_HANJA", sideChar: "",
                property: 0x0A10, unused: 0
            ),
            MeasuredPair(
                pos: "BOTTOM_LEFT", format: "HANGUL_SYLLABLE", sideChar: "-",
                property: 0x0408, unused: 0x2D
            ),
            MeasuredPair(
                pos: "TOP_CENTER", format: "CIRCLED_DIGIT", sideChar: "-",
                property: 0x0201, unused: 0x2D
            ),
        ]
        for pair in measured {
            let (_, position) = try mapPageNumber(
                "<hp:pageNum pos=\"\(pair.pos)\" formatType=\"\(pair.format)\" "
                    + "sideChar=\"\(pair.sideChar)\"/>"
            )
            expect(position.property).to(equal(pair.property), description: pair.pos)
            expect(position.unused).to(equal(pair.unused), description: pair.pos)
            expect(position.headDecoration).to(equal(0), description: pair.pos)
            expect(position.tailDecoration).to(equal(0), description: pair.pos)
            expect(position.rawPayload.count).to(equal(16), description: pair.pos)
        }
    }

    func testUnknownOrMissingEnumValuesFallBackToZero() throws {
        // 미지 이름은 0(위치 없음·숫자)으로 — 뷰어도 범위 밖 코드를 숫자로 그린다.
        let (_, unknown) = try mapPageNumber(
            "<hp:pageNum pos=\"SIDEWAYS\" formatType=\"KLINGON\" sideChar=\"\"/>"
        )
        expect(unknown.propertyInfo.displayPosition) == 0
        expect(unknown.propertyInfo.numberFormat) == 0
        expect(unknown.property) == 0

        // 속성이 전부 빠진 요소도 컨트롤 슬롯은 서야 WCHAR 정렬이 유지된다.
        let (paragraph, missing) = try mapPageNumber("<hp:pageNum/>")
        expect(paragraph.paraText?.charArray.map(\.value)) == [21, 13]
        expect(missing.propertyInfo.displayPosition) == 0
        expect(missing.propertyInfo.numberFormat) == 0
        expect(missing.unused) == 0
        expect(missing.rawPayload.count) == 16
    }

    func testSideCharLandsInFourthWcharOnly() throws {
        // 줄표 필드(#138): 헌법주석 실물이 0x2D를 싣는 자리다. 앞/뒤 장식 문자는
        // HWPX에 대응 속성이 없어 0으로 남는다 — 조판은 장식이 없을 때만 이
        // 필드로 "- N -"을 만든다.
        let (_, dash) = try mapPageNumber(
            "<hp:pageNum pos=\"BOTTOM_CENTER\" formatType=\"DIGIT\" sideChar=\"-\"/>"
        )
        expect(dash.unused) == 0x2D
        expect(dash.headDecoration) == 0
        expect(dash.tailDecoration) == 0
        expect(dash.userSymbol) == 0
        expect(Array(dash.rawPayload.suffix(8))) == [0, 0, 0, 0, 0, 0, 0x2D, 0]

        // 필드가 WCHAR 하나라 두 글자 이상이면 첫 UTF-16 unit만 싣는다.
        let (_, multi) = try mapPageNumber("<hp:pageNum sideChar=\"★☆\"/>")
        expect(multi.unused) == 0x2605
    }

    func testUnconsumedChildrenDegradeIntoDiagnostics() throws {
        // 속성만 읽는 잎 요소 — 자식이 오면 값도 진단도 없이 사라지지 않고
        // 합성 tagId(0) + 요소명 payload로 남아야 parseDiagnostics()가 본다.
        let (_, position) = try mapPageNumber(
            "<hp:pageNum pos=\"BOTTOM_CENTER\" formatType=\"DIGIT\" sideChar=\"\">"
                + "<hp:extra/></hp:pageNum>"
        )
        let names = position.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(names) == ["extra"]
        expect(position.unknownChildren.map(\.tagId)) == [hwpxSyntheticTagId]
    }

    func testPageNumIsNoLongerInDegradeTable() {
        // 분류표 규약: 승격한 요소는 강등 표에서 빠져야 두 경로가 갈리지 않는다.
        expect(HwpxControlMapper.sectionAttachments["pageNum"]).to(beNil())
        expect(HwpxControlMapper.sectionAttachments["pageNumCtrl"]?.code) == 21
    }
}
