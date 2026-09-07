@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:footNote`·`hp:endNote`·`hp:autoNum` typed 승격 (#168).
///
/// 강등 상태에서는 각주·미주 본문이 통째로 사라졌다 — 미지 요소 강등은 요소
/// 이름만 payload로 담아 `hp:t` 텍스트가 모델에 남지 않는다. 번호 라벨은 각주
/// 본문 문단 안 `hp:autoNum`의 `autoNumberInfo`에서 나오므로 각주만 승격하면
/// 번호 없는 각주가 된다. 실물 대조는 `footnote-endnote` 변환 쌍이 맡는다.
final class HwpxFootnoteMapperTests: XCTestCase {
    private func mapSection(
        _ body: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSection {
        try HwpxSectionFixture.mapSection(body, options: options)
    }

    /// 실물(`footnote-endnote` 변환본)과 같은 모양 — 각주 본문 첫 run이
    /// `hp:ctrl` → `hp:autoNum`을 품고 `hp:subList`는 `vertAlign="TOP"`이다.
    private func noteBody(
        numberFormat: String = "DIGIT",
        superscript: String = "0",
        suffixChar: String = ")"
    ) -> String {
        HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7"><hp:t>본문</hp:t>\
        <hp:ctrl><hp:footNote number="1" suffixChar="41" instId="1115242634">\
        <hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="TOP" \
        textWidth="0" textHeight="0">\
        <hp:p><hp:run charPrIDRef="12">\
        <hp:ctrl><hp:autoNum num="1" numType="FOOTNOTE">\
        <hp:autoNumFormat type="\(numberFormat)" userChar="" prefixChar="" \
        suffixChar="\(suffixChar)" supscript="\(superscript)"/>\
        </hp:autoNum></hp:ctrl>\
        <hp:t> 각주 본문</hp:t></hp:run></hp:p>\
        </hp:subList></hp:footNote></hp:ctrl>\
        <hp:ctrl><hp:endNote number="1" suffixChar="41" instId="1115242635">\
        <hp:subList id="" vertAlign="TOP" textWidth="0" textHeight="0">\
        <hp:p><hp:run charPrIDRef="12">\
        <hp:ctrl><hp:autoNum num="1" numType="ENDNOTE"/></hp:ctrl>\
        <hp:t> 미주 본문</hp:t></hp:run></hp:p>\
        </hp:subList></hp:endNote></hp:ctrl>\
        </hp:run></hp:p>
        """
    }

    private func controls(of section: HwpSection) throws -> [HwpCtrlId] {
        try XCTUnwrap(section.paragraph[1].ctrlHeaderArray)
    }

    func testFootnoteAndEndnotePromoteWithParagraphText() throws {
        let ctrls = try controls(of: try mapSection(noteBody()))
        guard ctrls.count == 2,
              case let .footnote(footnote) = ctrls[0],
              case let .endnote(endnote) = ctrls[1]
        else {
            return fail("Expected .footnote + .endnote, got \(ctrls)")
        }

        expect(footnote.header.ctrlId) == HwpOtherCtrlId.footnote.rawValue
        expect(endnote.header.ctrlId) == HwpOtherCtrlId.endnote.rawValue
        // 리스트 헤더의 문단 수는 실제 문단 수와 같아야 한다 — 바이너리 로더가
        // 이 값으로 문단을 세므로 어긋나면 왕복이 깨진다.
        expect(footnote.listArray.first?.header.paragraphCount) == 1
        expect(footnote.listArray.first?.header.propertyInfo.verticalAlignment) == .top
        // 강등 상태에서 통째로 사라지던 것 — 본문 텍스트가 모델에 실려야 한다.
        let text = footnote.listArray.first?.paragraphArray.first?.paraText?.charArray
            .compactMap { $0.type == .char ? UnicodeScalar($0.value).map(Character.init) : nil }
        expect(text.map { String($0) }) == " 각주 본문\r"
    }

    /// 앵커는 각주·미주가 코드 17, 자동 번호가 코드 18이어야 한다 — extended
    /// 문자와 ctrl 슬롯이 짝을 이루지 않으면 `HwpTextRunBuilder`의 서수 정렬이
    /// 무너져 다른 컨트롤을 집는다.
    func testNoteAndAutoNumberAnchorsUseControlCodesSeventeenAndEighteen() throws {
        let section = try mapSection(noteBody())
        let chars = try XCTUnwrap(section.paragraph[1].paraText?.charArray)
        expect(chars.filter { $0.type == .extended }.map(\.value)) == [17, 17]
        expect(chars.filter { $0.type == .extended }.count)
            == section.paragraph[1].ctrlHeaderArray?.count

        let ctrls = try controls(of: section)
        guard case let .footnote(footnote) = ctrls[0],
              let notePara = footnote.listArray.first?.paragraphArray.first
        else {
            return fail("Expected .footnote with a paragraph, got \(ctrls)")
        }
        let noteChars = try XCTUnwrap(notePara.paraText?.charArray)
        expect(noteChars.filter { $0.type == .extended }.map(\.value)) == [18]
        expect(noteChars.filter { $0.type == .extended }.count)
            == notePara.ctrlHeaderArray?.count
    }

    /// 표 143 속성 — bits 0-3 종류·bits 4-11 번호 모양·bit 12 위 첨자.
    /// property를 0으로 두면 종류가 `.page`로 읽혀 번호 치환이 통째로 사라진다.
    func testAutoNumberPropertyCarriesKindShapeAndSuperscript() throws {
        let ctrls = try controls(of: try mapSection(
            noteBody(numberFormat: "CIRCLED_HANGUL_JAMO", superscript: "1")
        ))
        guard case let .footnote(footnote) = ctrls[0],
              case let .autoNumber(auto)? = footnote.listArray.first?
              .paragraphArray.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected .autoNumber inside the footnote, got \(ctrls)")
        }
        let info = try XCTUnwrap(auto.autoNumberInfo)
        expect(info.kind) == HwpAutoNumberKind.footnote
        expect(info.numberShapeRawValue) == 11
        expect(info.isSuperscript) == true
        expect(info.number) == 1
        // `hp:autoNumFormat@suffixChar`는 **리터럴 문자**다 — 같은 이름이라도
        // `hp:footNote@suffixChar`(10진 코드포인트)와 인코딩이 다르다.
        expect(info.decorationTail) == 0x29

        guard case let .endnote(endnote) = ctrls[1],
              case let .autoNumber(endAuto)? = endnote.listArray.first?
              .paragraphArray.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected .autoNumber inside the endnote, got \(ctrls)")
        }
        expect(endAuto.autoNumberInfo?.kind) == HwpAutoNumberKind.endnote
    }

    /// 컨트롤 헤더 payload는 **양 모드 보존**(`decoupledPayload`)이다 —
    /// 바이너리 `HwpListControl.load`가 ctrl id와 무관하게 그 게이트를 쓰므로,
    /// `preservedPayload`로 접으면 바이너리가 들고 있는 바이트를 HWPX만 비운다.
    func testNotePayloadSurvivesViewerOptionsWhileAutoNumberRawIsGated() throws {
        let ctrls = try controls(of: try mapSection(noteBody(), options: .viewer))
        guard case let .footnote(footnote) = ctrls[0],
              case let .autoNumber(auto)? = footnote.listArray.first?
              .paragraphArray.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected .footnote + .autoNumber, got \(ctrls)")
        }
        expect(footnote.header.rawPayload).toNot(beEmpty())
        expect(footnote.listArray.first?.headerRawPayload).toNot(beEmpty())
        // atno는 반대다 — 바이너리 `HwpOtherControl`이 raw만 게이트하고
        // typed 뷰는 게이트 전 원본에서 만들므로, `.viewer`에서도 번호는 산다.
        expect(auto.rawPayload).to(beEmpty())
        expect(auto.rawTrailing).to(beEmpty())
        expect(auto.autoNumberInfo?.kind) == HwpAutoNumberKind.footnote
    }

    /// 합성 payload는 바이너리 실물과 바이트가 같아야 한다 — `footnote-endnote`
    /// HWP 쌍 실측(컨트롤 헤더 20바이트·리스트 헤더 16바이트·atno 16바이트).
    /// manifest의 prefix/suffix 8바이트 핀은 20바이트의 가운데를 못 지키므로
    /// 여기서 전체를 직접 핀한다.
    func testSynthesizedPayloadsMatchBinaryBytes() throws {
        let ctrls = try controls(of: try mapSection(noteBody()))
        guard case let .footnote(footnote) = ctrls[0],
              case let .autoNumber(auto)? = footnote.listArray.first?
              .paragraphArray.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected .footnote + .autoNumber, got \(ctrls)")
        }
        expect(Array(footnote.header.rawPayload)) == [
            0x20, 0x20, 0x6E, 0x66, // "fn  "
            0x01, 0x00, 0x00, 0x00, // number
            0x00, 0x00, // prefixChar
            0x29, 0x00, // suffixChar (10진 "41")
            0x00, 0x00, 0x00, 0x00, // flag
            0x8A, 0x40, 0x79, 0x42, // instId 1115242634
        ]
        expect(Array(try XCTUnwrap(footnote.listArray.first?.headerRawPayload)))
            == [0x01, 0x00, 0x00, 0x00] + [UInt8](repeating: 0, count: 12)
        expect(Array(auto.rawPayload)) == [
            0x6F, 0x6E, 0x74, 0x61, // "atno"
            0x01, 0x00, 0x00, 0x00, // 속성: 각주(1) + DIGIT + 위 첨자 없음
            0x01, 0x00, // 번호
            0x00, 0x00, // 사용자 기호
            0x00, 0x00, // 앞 장식
            0x29, 0x00, // 뒤 장식 ')'
        ]
    }

    /// `hp:subList`가 없어도 리스트는 만든다 — 바이너리 로더는 리스트가 하나도
    /// 없으면 던지므로(`recordDoesNotExist`) 빈 리스트가 왕복 가능한 최소 모양이다.
    func testMissingSubListStillProducesOneEmptyList() throws {
        let body = HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:footNote number="1"/></hp:ctrl></hp:run></hp:p>
        """
        let ctrls = try controls(of: try mapSection(body))
        guard case let .footnote(footnote) = ctrls[0] else {
            return fail("Expected .footnote, got \(ctrls)")
        }
        expect(footnote.listArray.count) == 1
        expect(footnote.listArray.first?.paragraphArray).to(beEmpty())
        expect(footnote.listArray.first?.header.paragraphCount) == 0
    }

    /// 미지 자식은 **이름까지** 보존돼 진단으로 남는다. 둘째 `hp:subList`는
    /// 읽히지 않으므로 함께 강등해야 값도 진단도 없이 사라지지 않는다.
    func testUnknownAndDuplicateChildrenDegradeWithNames() throws {
        let body = HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:footNote number="1"><hp:mystery/>\
        <hp:subList id=""><hp:p><hp:run charPrIDRef="12">\
        <hp:ctrl><hp:autoNum num="1" numType="FOOTNOTE"><hp:riddle/></hp:autoNum></hp:ctrl>\
        <hp:t>가</hp:t></hp:run></hp:p><hp:enigma/></hp:subList>\
        <hp:subList id=""/>\
        </hp:footNote></hp:ctrl></hp:run></hp:p>
        """
        let ctrls = try controls(of: try mapSection(body))
        guard case let .footnote(footnote) = ctrls[0],
              case let .autoNumber(auto)? = footnote.listArray.first?
              .paragraphArray.first?.ctrlHeaderArray?.first
        else {
            return fail("Expected .footnote + .autoNumber, got \(ctrls)")
        }
        expect(footnote.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["mystery", "subList"]
        expect(
            footnote.listArray.first?.headerUnknownChildren
                .map { String(bytes: $0.payload, encoding: .utf8) }
        ) == ["enigma"]
        expect(auto.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["riddle"]
    }

    /// 분류표 규약: 승격한 요소는 강등 표에서 빠져야 두 경로가 갈리지 않는다.
    /// `newNum`은 같은 코드 18이지만 표 144의 다른 payload라 그대로 남는다 (#169).
    func testPromotedElementsLeaveTheDegradeTable() {
        expect(HwpxControlMapper.sectionAttachments["footNote"]).to(beNil())
        expect(HwpxControlMapper.sectionAttachments["endNote"]).to(beNil())
        expect(HwpxControlMapper.sectionAttachments["autoNum"]).to(beNil())
        expect(HwpxControlMapper.sectionAttachments["newNum"]?.code) == 18
    }
}
