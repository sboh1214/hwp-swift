@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:header`·`hp:footer` typed 승격 (#167).
///
/// 조판(`HwpPageChromeBuilder`)이 읽는 것은 적용 범위와 리스트 문단 둘뿐이고,
/// 적용 범위는 컨트롤 헤더 payload를 **되읽어** 얻으므로 payload 합성과 그
/// 보존 게이트가 렌더 필수다. 실물 대조는 `header-footer` 변환 쌍이 맡는다
/// (`HwpxFixtureRenderTests.testHwpxPageChromeMatchesHwpPairs`).
final class HwpxHeaderFooterMapperTests: XCTestCase {
    private func mapSection(
        _ body: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSection {
        try HwpxSectionFixture.mapSection(body, options: options)
    }

    /// 실물(`header-footer` 변환본)과 같은 모양 — 머리말은 `vertAlign="TOP"`,
    /// 꼬리말은 `"BOTTOM"`이고 둘 다 `applyPageType="BOTH"`다.
    private func headerFooterBody(
        applyPageType: String = "BOTH",
        footerApplyPageType: String = "BOTH"
    ) -> String {
        HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:header id="1" applyPageType="\(applyPageType)">\
        <hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="TOP" \
        textWidth="42520" textHeight="4252">\
        <hp:p><hp:run charPrIDRef="2"><hp:t>머리말</hp:t></hp:run></hp:p>\
        </hp:subList></hp:header></hp:ctrl>\
        <hp:ctrl><hp:footer id="2" applyPageType="\(footerApplyPageType)">\
        <hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="BOTTOM" \
        textWidth="42520" textHeight="4252">\
        <hp:p><hp:run charPrIDRef="2"><hp:t>꼬리말</hp:t></hp:run></hp:p>\
        </hp:subList></hp:footer></hp:ctrl>\
        </hp:run></hp:p>
        """
    }

    private func controls(of section: HwpSection) throws -> [HwpCtrlId] {
        try XCTUnwrap(section.paragraph[1].ctrlHeaderArray)
    }

    func testHeaderAndFooterPromoteWithParagraphsAndVerticalAlignment() throws {
        let section = try mapSection(headerFooterBody())
        let ctrls = try controls(of: section)
        guard ctrls.count == 2,
              case let .header(header) = ctrls[0],
              case let .footer(footer) = ctrls[1]
        else {
            return fail("Expected .header + .footer, got \(ctrls)")
        }

        expect(header.header.ctrlId) == HwpOtherCtrlId.header.rawValue
        expect(footer.header.ctrlId) == HwpOtherCtrlId.footer.rawValue
        expect(header.listArray.first?.paragraphArray.count) == 1
        expect(footer.listArray.first?.paragraphArray.count) == 1
        // 리스트 헤더의 문단 수는 실제 문단 수와 같아야 한다 — 바이너리 로더가
        // 이 값으로 문단을 세므로 어긋나면 왕복이 깨진다.
        expect(header.listArray.first?.header.paragraphCount) == 1
        // 표 89 세로 정렬: 머리말 위, 꼬리말 아래.
        expect(header.listArray.first?.header.propertyInfo.verticalAlignment) == .top
        expect(footer.listArray.first?.header.propertyInfo.verticalAlignment) == .bottom
    }

    /// 앵커는 제어 문자 코드 16이어야 한다 — extended 문자와 ctrl 슬롯이 짝을
    /// 이루지 않으면 `HwpTextRunBuilder`의 서수 정렬이 무너진다.
    func testHeaderFooterAnchorsUseControlCodeSixteen() throws {
        let section = try mapSection(headerFooterBody())
        let chars = try XCTUnwrap(section.paragraph[1].paraText?.charArray)
        expect(chars.map(\.value)) == [16, 16, 13]
        // 짝 불변식: extended 문자 수 == ctrl 슬롯 수. 하나만 어긋나도
        // `HwpTextRunBuilder`의 서수 인덱싱이 다른 컨트롤을 집는다.
        let extendedCount = chars.filter { $0.type == .extended }.count
        expect(extendedCount) == section.paragraph[1].ctrlHeaderArray?.count
    }

    /// 적용 범위(표 141 bits 0-1)는 payload를 되읽어 얻는다.
    func testApplyPageTypeMapsToScopeBits() throws {
        let section = try mapSection(
            headerFooterBody(applyPageType: "ODD", footerApplyPageType: "EVEN")
        )
        let ctrls = try controls(of: section)
        guard case let .header(header) = ctrls[0], case let .footer(footer) = ctrls[1] else {
            return fail("Expected .header + .footer, got \(ctrls)")
        }
        expect(header.headerFooterApplyScope) == .oddPagesOnly
        expect(footer.headerFooterApplyScope) == .evenPagesOnly
        expect(header.headerFooterPropertyRawValue) == 2
        expect(footer.headerFooterPropertyRawValue) == 1
    }

    /// 생략과 미지 이름은 양쪽으로 접는다 — 범위를 추측해 쪽을 건너뛰면
    /// 머리말이 통째로 사라지므로, 모르면 그리는 쪽이 안전하다.
    func testMissingOrUnknownApplyPageTypeFallsBackToBothPages() throws {
        let body = headerFooterBody().replacingOccurrences(
            of: "<hp:header id=\"1\" applyPageType=\"BOTH\">", with: "<hp:header id=\"1\">"
        ).replacingOccurrences(
            of: "applyPageType=\"BOTH\"", with: "applyPageType=\"SOMETIMES\""
        )
        let ctrls = try controls(of: try mapSection(body))
        guard case let .header(header) = ctrls[0], case let .footer(footer) = ctrls[1] else {
            return fail("Expected .header + .footer, got \(ctrls)")
        }
        expect(header.headerFooterApplyScope) == .bothPages
        expect(footer.headerFooterApplyScope) == .bothPages
    }

    /// payload는 **양 모드 보존**이다 — 바이너리 `HwpListControl.load`가 같은
    /// 이유로 `decoupledPayload`를 쓴다. `.viewer`에서 비우면 적용 범위가
    /// 사라져 홀·짝수 머리말이 전부 양쪽으로 그려진다.
    func testApplyScopeSurvivesViewerOptions() throws {
        let section = try mapSection(
            headerFooterBody(applyPageType: "ODD"), options: .viewer
        )
        let ctrls = try controls(of: section)
        guard case let .header(header) = ctrls[0] else {
            return fail("Expected .header, got \(ctrls)")
        }
        expect(header.header.rawPayload).toNot(beEmpty())
        expect(header.headerFooterApplyScope) == .oddPagesOnly
    }

    /// `hp:subList`가 없어도 리스트는 만든다 — 바이너리 로더는 리스트가 하나도
    /// 없으면 던지므로(`recordDoesNotExist`) 빈 리스트가 왕복 가능한 최소 모양이다.
    func testMissingSubListStillProducesOneEmptyList() throws {
        let body = HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:header id="1" applyPageType="BOTH"/></hp:ctrl>\
        </hp:run></hp:p>
        """
        let ctrls = try controls(of: try mapSection(body))
        guard case let .header(header) = ctrls[0] else {
            return fail("Expected .header, got \(ctrls)")
        }
        expect(header.listArray.count) == 1
        expect(header.listArray.first?.paragraphArray).to(beEmpty())
        expect(header.listArray.first?.header.paragraphCount) == 0
    }

    /// 미지 자식은 **이름까지** 보존돼 진단으로 남는다 — 승격이 "미해석 강등은
    /// 진단으로 보고됨" 규약을 깨지 않아야 한다. 이름을 보지 않으면 `consumed:`
    /// 목록이 틀려 소비돼야 할 자식이 진단에 섞여도 통과한다.
    func testUnknownChildrenKeepElementNames() throws {
        let body = HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:header id="1" applyPageType="BOTH">\
        <hp:mystery/>\
        <hp:subList id=""><hp:p><hp:run charPrIDRef="2"><hp:t>가</hp:t></hp:run></hp:p>\
        <hp:enigma/></hp:subList>\
        </hp:header></hp:ctrl>\
        </hp:run></hp:p>
        """
        let ctrls = try controls(of: try mapSection(body))
        guard case let .header(header) = ctrls[0] else {
            return fail("Expected .header, got \(ctrls)")
        }
        // subList는 소비되므로 헤더 쪽 미지 자식은 mystery 하나뿐이어야 한다.
        expect(header.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["mystery"]
        expect(
            header.listArray.first?.headerUnknownChildren
                .map { String(bytes: $0.payload, encoding: .utf8) }
        ) == ["enigma"]
    }

    /// 둘째 `hp:subList`는 읽히지 않으므로 진단으로 강등해야 한다 — 이름 단위
    /// 소비 표시라 그대로 두면 값도 진단도 없이 사라진다.
    func testDuplicateSubListIsDemotedToDiagnostics() throws {
        let body = HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="7">\
        <hp:ctrl><hp:header id="1" applyPageType="BOTH">\
        <hp:subList id=""><hp:p><hp:run charPrIDRef="2"><hp:t>가</hp:t></hp:run></hp:p></hp:subList>\
        <hp:subList id=""><hp:p><hp:run charPrIDRef="2"><hp:t>나</hp:t></hp:run></hp:p></hp:subList>\
        </hp:header></hp:ctrl>\
        </hp:run></hp:p>
        """
        let ctrls = try controls(of: try mapSection(body))
        guard case let .header(header) = ctrls[0] else {
            return fail("Expected .header, got \(ctrls)")
        }
        // 첫 subList만 리스트가 되고 둘째는 진단으로 남는다.
        expect(header.listArray.count) == 1
        expect(header.unknownChildren.map { String(bytes: $0.payload, encoding: .utf8) })
            == ["subList"]
    }

    /// 합성 payload는 바이너리 실물과 같은 모양이어야 한다 — 컨트롤 헤더
    /// 12바이트(4CC + 속성 + `hp:header@id`), 리스트 헤더 34바이트(문단 수 +
    /// 속성 + textWidth·textHeight + 0). `header-footer` HWP 쌍 실측.
    func testSynthesizedPayloadsMatchBinaryShape() throws {
        let section = try mapSection(headerFooterBody())
        let ctrls = try controls(of: section)
        guard case let .header(header) = ctrls[0] else {
            return fail("Expected .header, got \(ctrls)")
        }
        expect(header.header.rawPayload.count) == 12
        expect(Array(header.header.rawPayload.suffix(4))) == [1, 0, 0, 0]
        let list = try XCTUnwrap(header.listArray.first)
        expect(list.headerRawPayload.count) == 34
        // trailing 26바이트의 앞 두 UINT32 = textWidth 42520 · textHeight 4252.
        expect(list.header.rawTrailingWords?.prefix(4).map(Int.init))
            == [42520, 0, 4252, 0]
    }
}
