@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 구역 첫 쪽 감추기 `hp:visibility` → 표 130 bits 0·1·2·5 (#167).
///
/// 머리말·꼬리말이 typed 승격된 뒤로는 이 플래그가 조판에 닿는다 —
/// `HwpPageChromeBuilder.applySectionHideFlags`가 머리말·꼬리말·쪽 번호를
/// 표 145 마스크로 환산해 구역 첫 쪽에 쓴다.
final class HwpxSecPrVisibilityTests: XCTestCase {
    /// `blankBody`의 `hp:startNum` 뒤에 임의의 `hp:visibility`를 끼운 구역 본문.
    private func body(visibility: String) -> String {
        HwpxSectionFixture.blankBody.replacingOccurrences(
            of: "<hp:pagePr",
            with: visibility + "<hp:pagePr"
        )
    }

    private func sectionDef(_ body: String) throws -> HwpSectionDef {
        let section = try HwpxSectionFixture.mapSection(body)
        for paragraph in section.paragraph {
            for ctrl in paragraph.ctrlHeaderArray ?? [] {
                if case let .section(def) = ctrl {
                    return def
                }
            }
        }
        throw XCTSkip("section def not found")
    }

    func testHideFlagsMapToSectionDefinitionBits() throws {
        let def = try sectionDef(body(visibility: """
        <hp:visibility hideFirstHeader="1" hideFirstFooter="1" \
        hideFirstMasterPage="1" hideFirstPageNum="1" border="SHOW_ALL" fill="SHOW_ALL"/>
        """))
        expect(def.propertyInfo.hideHeader) == true
        expect(def.propertyInfo.hideFooter) == true
        expect(def.propertyInfo.hideMasterPage) == true
        expect(def.propertyInfo.hidePageNumberPosition) == true
        // 표현이 셋이다 — property·파생 필드·propertyInfo.rawValue가 함께 서야 한다.
        expect(def.property & 0b100111) == 0b100111
        expect(def.propertyInfo.rawValue) == def.property
    }

    /// 감추기가 꺼진 실물(`header-footer` 변환본이 그렇다)과 요소 자체가 없는
    /// 문서는 모두 플래그가 서지 않아야 한다.
    func testZeroOrAbsentVisibilityLeavesFlagsClear() throws {
        let zeroed = try sectionDef(body(visibility: """
        <hp:visibility hideFirstHeader="0" hideFirstFooter="0" hideFirstPageNum="0"/>
        """))
        expect(zeroed.propertyInfo.hideHeader) == false
        expect(zeroed.propertyInfo.hideFooter) == false
        expect(zeroed.propertyInfo.hidePageNumberPosition) == false

        let absent = try sectionDef(HwpxSectionFixture.blankBody)
        expect(absent.propertyInfo.hideHeader) == false
        expect(absent.propertyInfo.hideFooter) == false
        expect(absent.propertyInfo.hidePageNumberPosition) == false
    }

    /// 부분 지정: 켠 플래그만 서고 나머지는 그대로다.
    func testOnlyRequestedFlagsAreSet() throws {
        let def = try sectionDef(body(visibility: """
        <hp:visibility hideFirstFooter="1"/>
        """))
        expect(def.propertyInfo.hideHeader) == false
        expect(def.propertyInfo.hideFooter) == true
        expect(def.propertyInfo.hideMasterPage) == false
        expect(def.propertyInfo.hidePageNumberPosition) == false
    }

    /// `hp:visibility`를 소비 목록에 넣으면 그 서브트리가 상위 순회에서 빠진다 —
    /// 안쪽 미지 자식을 따로 걷지 않으면 값도 진단도 없이 사라진다
    /// (`startNum`·`margin`과 같은 규약).
    func testUnknownChildrenInsideVisibilitySurviveAsDiagnostics() throws {
        let def = try sectionDef(body(visibility: """
        <hp:visibility hideFirstHeader="1"><hp:mystery/></hp:visibility>
        """))
        expect(def.unknownChildren.compactMap { String(bytes: $0.payload, encoding: .utf8) })
            .to(contain("mystery"))
        // 플래그는 그대로 읽혀야 한다 — 진단 보존이 매핑을 막지 않는다.
        expect(def.propertyInfo.hideHeader) == true
    }

    /// 둘째 `hp:visibility`는 읽히지 않으므로 진단으로 강등해야 한다.
    func testDuplicateVisibilityIsDemotedToDiagnostics() throws {
        let def = try sectionDef(body(visibility: """
        <hp:visibility hideFirstHeader="1"/><hp:visibility hideFirstFooter="1"/>
        """))
        // 첫 요소만 읽는다.
        expect(def.propertyInfo.hideHeader) == true
        expect(def.propertyInfo.hideFooter) == false
        expect(def.unknownChildren.compactMap { String(bytes: $0.payload, encoding: .utf8) })
            .to(contain("visibility"))
    }
}
