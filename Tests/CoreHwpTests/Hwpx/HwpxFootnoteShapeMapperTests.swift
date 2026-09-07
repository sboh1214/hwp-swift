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
