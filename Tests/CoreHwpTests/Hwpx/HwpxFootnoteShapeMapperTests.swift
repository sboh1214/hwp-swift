@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:footNotePr`·`hp:endNotePr` → 구역의 각주·미주 모양 (표 133·134, #168).
///
/// 조판이 보는 구분선 값은 typed 필드가 아니라 `rawPayload`를 재디코드한
/// `dividerInfo`다 — payload를 합성하지 않으면 HWP 쌍이 0.34pt 구분선을 그리는
/// 자리에서 HWPX만 튜닝 폴백 1.0pt를 그린다.
final class HwpxFootnoteShapeMapperTests: XCTestCase {
    private func sectionDef(
        _ notePr: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSectionDef {
        let body = HwpxSectionFixture.blankBody.replacingOccurrences(
            of: "</hp:secPr>", with: notePr + "</hp:secPr>"
        )
        let section = try HwpxSectionFixture.mapSection(body, options: options)
        guard case let .section(sectionDef)? = section.paragraph[0].ctrlHeaderArray?.first else {
            throw XCTSkip("first control must be .section")
        }
        return sectionDef
    }

    /// `footnote-endnote` 변환본의 실물 그대로.
    private static let realFootNotePr = """
    <hp:footNotePr>\
    <hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>\
    <hp:noteLine length="-1" type="SOLID" width="0.12 mm" color="#000000"/>\
    <hp:noteSpacing betweenNotes="283" belowLine="567" aboveLine="850"/>\
    <hp:numbering type="CONTINUOUS" newNum="1"/>\
    <hp:placement place="EACH_COLUMN" beneathText="0"/>\
    </hp:footNotePr>
    """

    private static let realEndNotePr = """
    <hp:endNotePr>\
    <hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>\
    <hp:noteLine length="14692344" type="SOLID" width="0.12 mm" color="#000000"/>\
    <hp:noteSpacing betweenNotes="0" belowLine="567" aboveLine="850"/>\
    <hp:numbering type="CONTINUOUS" newNum="1"/>\
    <hp:placement place="END_OF_DOCUMENT" beneathText="0"/>\
    </hp:endNotePr>
    """

    /// 합성 payload는 HWP 쌍 FOOTNOTE_SHAPE 28바이트와 바이트가 같아야 한다.
    func testSynthesizedPayloadMatchesBinaryBytes() throws {
        let def = try sectionDef(Self.realFootNotePr + Self.realEndNotePr)
        expect(Array(def.footNoteShape.rawPayload)) == [
            0x00, 0x00, 0x00, 0x00, // 속성
            0x00, 0x00, // 사용자 기호
            0x00, 0x00, // 앞 장식
            0x29, 0x00, // 뒤 장식 ')'
            0x01, 0x00, // 시작 번호
            0xFF, 0xFF, 0xFF, 0xFF, // 구분선 길이 -1 (자동) — **4바이트**
            0x52, 0x03, // 구분선 위 850
            0x37, 0x02, // 구분선 아래 567
            0x1B, 0x01, // 주석 사이 283
            0x01, // 종류 SOLID
            0x01, // 굵기 0.12 mm
            0x00, 0x00, 0x00, 0x00, // 색 #000000
        ]
        // 미주는 길이와 주석 사이만 다르다 (14,692,344 = 0x00E02FF8).
        expect(Array(def.endNoteShape.rawPayload.dropFirst(12).prefix(10)))
            == [0xF8, 0x2F, 0xE0, 0x00, 0x52, 0x03, 0x37, 0x02, 0x00, 0x00]
    }

    /// 조판이 읽는 값은 `dividerInfo`뿐이다 — 길이 필드를 2바이트로 쓰면
    /// wide 우선 디코드가 무효가 돼 narrow로 폴백하고 여백·색이 오염된다.
    func testDividerInfoDecodesWithFourByteLength() throws {
        let def = try sectionDef(Self.realFootNotePr + Self.realEndNotePr)
        let footnote = try XCTUnwrap(def.footNoteShape.dividerInfo)
        // 길이 -1은 "자동"이라 nil이고, 조판이 단 폭의 1/3로 그린다.
        expect(footnote.length).to(beNil())
        expect(footnote.marginTop) == 850
        expect(footnote.marginBottom) == 567
        expect(footnote.spacingBetweenNotes) == 283
        expect(footnote.type) == 1
        expect(footnote.thickness) == 1
        expect(try XCTUnwrap(def.endNoteShape.dividerInfo).length) == 14_692_344
    }

    /// 표 134 속성 — bits 0-7 번호 모양·bits 8-9 배치·bits 10-11 번호 매김·
    /// bit 12 위 첨자. 실측(한글.app 미주 모양 대화상자)으로 0x150B를 얻었다.
    func testPropertyBitsMatchMeasuredNonDefaultSample() throws {
        let notePr = """
        <hp:endNotePr>\
        <hp:autoNumFormat type="CIRCLED_HANGUL_JAMO" userChar="" prefixChar="[" \
        suffixChar="]" supscript="1"/>\
        <hp:noteLine length="14692344" type="SOLID" width="0.12 mm" color="#000000"/>\
        <hp:noteSpacing betweenNotes="0" belowLine="567" aboveLine="850"/>\
        <hp:numbering type="ON_SECTION" newNum="3"/>\
        <hp:placement place="END_OF_SECTION" beneathText="0"/>\
        </hp:endNotePr>
        """
        let shape = try sectionDef(notePr).endNoteShape
        expect(shape.property) == 0x150B
        expect(shape.property & 0xFF) == 11
        expect(shape.numberingModeRawValue) == 1
        expect(shape.placesEndnoteAtSectionEnd) == true
        expect(shape.startingNumber) == 3
        expect(shape.decorationHeadRawValue) == 0x5B
        expect(shape.decorationTailRawValue) == 0x5D
    }

    /// `HwpFootnoteShape.load`가 `decoupledPayload`를 쓰므로 payload는 양 모드
    /// 보존이다 — `.viewer`에서 비우면 구분선이 튜닝 폴백으로 떨어진다.
    func testPayloadSurvivesViewerOptions() throws {
        let def = try sectionDef(Self.realFootNotePr, options: .viewer)
        expect(def.footNoteShape.rawPayload.count) == 28
        expect(def.footNoteShape.dividerInfo).toNot(beNil())
    }

    /// 생략 속성·생략 요소의 기본값은 한컴 참조 모델 생성자에서 온다 —
    /// `CNoteSpacing()`은 850/567/567, `CNoteLine()`은 길이 0·SOLID·0.12 mm,
    /// `CFNNumbering()`은 시작 번호 1이다. 0으로 접으면 `HwpFootnoteLayout`이 그
    /// 값을 그대로 써서 **구분선 여백과 주석 사이 간격이 0**이 된다 (종류·굵기는
    /// 조판이 읽지 않으므로 payload 동등성 몫이다).
    func testOmittedNoteSpacingAndLineUseReferenceDefaults() throws {
        let shape = try sectionDef("<hp:footNotePr/>").footNoteShape
        let divider = try XCTUnwrap(shape.dividerInfo)
        expect(divider.marginTop) == 567
        expect(divider.marginBottom) == 567
        expect(divider.spacingBetweenNotes) == 850
        expect(divider.length).to(beNil()) // 참조 기본값 0 = 자동
        expect(divider.type) == 1 // LT2_SOLID
        expect(divider.thickness) == 1 // LWT_0_12
        expect(shape.startingNumber) == 1
    }

    /// **명시된 0은 보존한다** — 기본값은 속성이 아예 없을 때만 쓴다. 둘을 뭉치면
    /// 저작자가 0으로 지운 간격이 참조 기본값으로 되살아난다.
    func testExplicitZeroSpacingIsPreservedOverReferenceDefaults() throws {
        let shape = try sectionDef("""
        <hp:footNotePr>\
        <hp:noteSpacing betweenNotes="0" belowLine="0" aboveLine="0"/>\
        </hp:footNotePr>
        """).footNoteShape
        let divider = try XCTUnwrap(shape.dividerInfo)
        expect(divider.marginTop) == 0
        expect(divider.marginBottom) == 0
        expect(divider.spacingBetweenNotes) == 0
    }

    /// 각주 다단 배열의 셋째 값은 한컴 직렬화 이름이 `RIGHT_MOST_COLUMN`이다 —
    /// `RIGHT_COLUMN`으로 적으면 정상 입력이 0(각 단마다)으로 접힌다.
    func testFootnoteColumnPlacementUsesOfficialEnumName() throws {
        let notePr = "<hp:footNotePr><hp:placement place=\"RIGHT_MOST_COLUMN\"/></hp:footNotePr>"
        let placementShape = try sectionDef(notePr).footNoteShape
        expect((placementShape.property >> 8) & 0b11) == 2
        expect(HwpxFootnoteShapeMapper.placements["MERGED_COLUMN"]) == 1
    }

    /// `hp:noteLine@type`은 `hh:underline@shape`와 같은 OWPML `LINETYPE2` 이름표지만
    /// 값은 테두리 축(`LINETYPE2` 그대로)이다 — 3D 넷의 공식 이름을 모르면 실물
    /// 문서의 구분선 종류가 기본값이 된다.
    func testNoteLineRecognizesOfficialThreeDimensionalLineNames() throws {
        let notePr = "<hp:footNotePr><hp:noteLine type=\"THICK3D\"/></hp:footNotePr>"
        let lineShape = try sectionDef(notePr).footNoteShape
        expect(try XCTUnwrap(lineShape.dividerInfo).type) == 14
        expect(HwpxLineTypeMapper.borderLineTypes["THICKREV3D"]) == 15
        expect(HwpxLineTypeMapper.borderLineTypes["3D"]) == 16
        expect(HwpxLineTypeMapper.borderLineTypes["REV3D"]) == 17
    }

    /// 구분선은 글자선처럼 1을 빼지 않는다 — `line-shapes` 쌍에서 각주 `DOT`가 2,
    /// 미주 `DASH`가 3으로 저장됐다 (#177). 글자선 표를 잘못 태우면 둘 다 한 칸씩
    /// 밀려 HWP 쌍과 어긋난다.
    func testNoteLineUsesBorderLineValuesNotCharacterLineShapes() throws {
        let notePr = "<hp:footNotePr><hp:noteLine type=\"DOT\"/></hp:footNotePr>"
            + "<hp:endNotePr><hp:noteLine type=\"DASH\"/></hp:endNotePr>"
        let def = try sectionDef(notePr)
        expect(try XCTUnwrap(def.footNoteShape.dividerInfo).type) == 2
        expect(try XCTUnwrap(def.endNoteShape.dividerInfo).type) == 3
    }

    /// `color="none"`을 한컴 `GetAttribute`는 **흰색**(0xFFFFFFFF)으로 읽는다 —
    /// `colorAttribute`가 `#` 접두 없는 값을 nil로 돌려주므로 호출부가 막지 않으면
    /// 흰 구분선이 검정으로 뒤집힌다.
    func testNoneDividerColorMapsToWhiteNotBlack() throws {
        let notePr = "<hp:footNotePr><hp:noteLine color=\"none\"/></hp:footNotePr>"
        let noneShape = try sectionDef(notePr).footNoteShape
        let divider = try XCTUnwrap(noneShape.dividerInfo)
        expect(divider.color) == HwpColor(red: 255, green: 255, blue: 255)
        // 속성 생략은 생성자 값 `m_cColor(0x000000)`이다.
        let omitted = try sectionDef("<hp:footNotePr><hp:noteLine/></hp:footNotePr>")
        expect(try XCTUnwrap(omitted.footNoteShape.dividerInfo).color)
            == HwpColor(red: 0, green: 0, blue: 0)
    }

    /// 숫자로 읽히지 않는 굵기도 참조 기본값(0.12 mm)으로 접어야 한다 —
    /// `thicknessIndex`는 파싱 실패에 index 0(0.1 mm)을 돌려주므로 생략만 막으면
    /// `width="0.12mm"`(공백 없음) 같은 값이 조용히 다른 굵기가 된다.
    func testUnreadableDividerWidthFallsBackToReferenceDefault() throws {
        let notePr = "<hp:footNotePr><hp:noteLine width=\"0.12mm\"/></hp:footNotePr>"
        let widthShape = try sectionDef(notePr).footNoteShape
        let divider = try XCTUnwrap(widthShape.dividerInfo)
        expect(divider.thickness) == 1 // LWT_0_12
    }

    /// `beneathText`(텍스트에 이어 바로 출력)는 표 134가 위 첨자 바로 다음 줄에
    /// 적은 항목이라 bit 13에 싣는다 — 읽는 소비자는 없지만 컨트롤 헤더의
    /// `flag`·`instId`와 같이 실물이 담은 값을 합성에서 잃지 않는다.
    func testBeneathTextIsCarriedInPropertyBitThirteen() throws {
        let notePr = "<hp:footNotePr><hp:placement beneathText=\"1\"/></hp:footNotePr>"
        let beneath = try sectionDef(notePr).footNoteShape
        expect((beneath.property >> 13) & 1) == 1
        let plain = try sectionDef(Self.realFootNotePr).footNoteShape
        expect((plain.property >> 13) & 1) == 0
    }

    /// 요소가 없으면 손대지 않는다 — 값을 지어내면 없던 구분선 설정이 생긴다.
    func testAbsentNotePropertiesKeepBlankDocumentDefaults() throws {
        let def = try sectionDef("")
        expect(def.footNoteShape.rawPayload).to(beEmpty())
        expect(def.footNoteShape.dividerInfo).to(beNil())
        expect(def.endNoteShape.rawPayload).to(beEmpty())
    }

    /// 승격된 두 요소는 진단에서 빠지고, 그 안의 미지 자식은 남아야 한다 —
    /// 소비 래퍼 안쪽을 걷지 않으면 미래 요소가 조용히 사라진다.
    func testConsumedNotePropertiesLeaveOnlyInnerUnknownsInDiagnostics() throws {
        let def = try sectionDef(
            "<hp:footNotePr><hp:noteLine type=\"SOLID\"/><hp:mystery/></hp:footNotePr>"
        )
        expect(def.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["mystery"]
    }

    /// 둘째 `hp:footNotePr`는 읽히지 않으므로 진단으로 강등해야 한다.
    func testDuplicateNotePropertiesAreDemotedToDiagnostics() throws {
        let def = try sectionDef(Self.realFootNotePr + "<hp:footNotePr/>")
        expect(def.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["footNotePr"]
    }
}
