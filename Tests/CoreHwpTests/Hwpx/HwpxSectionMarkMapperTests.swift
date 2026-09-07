@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:newNum`·`hp:pageHiding`·`hp:bookmark`·`hp:indexmark` typed 승격 (#169).
///
/// 강등 상태에서는 조판이 쪽 번호를 되돌리지도(`applyNewNumbers`) 감추지도
/// (`pageHideMask`) 못해 HWP 쌍과 다른 쪽이 나왔다. 실물 대조는 `section-marks`
/// 변환 쌍이 맡고(등가 축 + 쪽 크롬 직접 핀), 여기서는 실물에 없는 조합
/// (개별 감추기 비트·생략 기본값·두 번째 키워드·과길이 이름)을 합성 입력으로
/// 잠근다.
final class HwpxSectionMarkMapperTests: XCTestCase {
    private func mapSection(
        _ body: String,
        options: HwpLoadOptions = .default
    ) throws -> HwpSection {
        try HwpxSectionFixture.mapSection(body, options: options)
    }

    private func markBody(_ ctrls: String) -> String {
        HwpxSectionFixture.blankBody + """
        <hp:p><hp:run charPrIDRef="0"><hp:t>본문</hp:t>\(ctrls)</hp:run></hp:p>
        """
    }

    private func controls(of section: HwpSection) throws -> [HwpCtrlId] {
        try XCTUnwrap(section.paragraph[1].ctrlHeaderArray)
    }

    private func mark(_ ctrls: String, options: HwpLoadOptions = .default) throws -> HwpCtrlId {
        let mapped = try controls(of: try mapSection(markBody(ctrls), options: options))
        return try XCTUnwrap(mapped.first)
    }

    // MARK: - 앵커

    /// 새 번호·쪽 감추기는 제어 문자 코드 21, 책갈피·찾아보기 표식은 22다.
    /// **18은 자동 번호(`atno`) 전용**이고 승격 전 강등 표는 `newNum`을 18로
    /// 적고 있었다 — 실물 `.hwp` 41건이 전부 21이다.
    func testMarkAnchorsUseControlCodesTwentyOneAndTwentyTwo() throws {
        let section = try mapSection(markBody("""
        <hp:ctrl><hp:newNum num="9" numType="PAGE"/></hp:ctrl>\
        <hp:ctrl><hp:pageHiding hidePageNum="1"/></hp:ctrl>\
        <hp:ctrl><hp:bookmark name="표식"/></hp:ctrl>\
        <hp:ctrl><hp:indexmark><hp:firstKey>키</hp:firstKey></hp:indexmark></hp:ctrl>
        """))
        let chars = try XCTUnwrap(section.paragraph[1].paraText?.charArray)
        expect(chars.filter { $0.type == .extended }.map(\.value)) == [21, 21, 22, 22]
        let mapped = try controls(of: section)
        expect(mapped.count) == 4
    }

    /// 강등 표에는 `pageNumCtrl`(홀/짝수 조정)만 남는다 — 네 요소가 빠져야 두
    /// 경로가 갈리지 않는다.
    func testPromotedElementsLeaveTheDegradeTable() {
        for name in ["newNum", "pageHiding", "bookmark", "indexmark"] {
            expect(HwpxControlMapper.sectionAttachments[name]).to(beNil())
        }
        expect(HwpxControlMapper.sectionAttachments["pageNumCtrl"]?.code) == 21
        expect(Set(HwpxSectionMarkMapper.marks.keys))
            == ["newNum", "pageHiding", "bookmark", "indexmark"]
    }

    // MARK: - 새 번호 지정 (표 144)

    /// 표 144 payload는 4CC + 속성 UINT32 + 번호 UINT16 = 10바이트다.
    /// **12바이트 이상이면 안 된다** — 레거시 `numberingInfo` 오버레이가
    /// UINT32 3개를 읽어 실물 바이너리에는 없는 뷰를 만든다 (실물 41건 전부 nil).
    func testNewNumberPayloadMatchesTableOneFortyFourAndAvoidsNumberingOverlay() throws {
        guard case let .newNumber(control) = try mark(
            #"<hp:ctrl><hp:newNum num="9" numType="PAGE"/></hp:ctrl>"#
        ) else {
            return fail("Expected .newNumber")
        }
        expect([UInt8](control.rawPayload))
            == [0x6F, 0x6E, 0x77, 0x6E, 0, 0, 0, 0, 9, 0]
        expect(control.newNumberInfo?.property) == 0
        expect(control.newNumberInfo?.number) == 9
        expect(control.newNumberInfo?.kind) == HwpAutoNumberKind.page
        expect(control.numberingInfo).to(beNil())
    }

    /// 번호 종류는 `hp:autoNum`과 같은 `AUTONUMTYPE` 어휘다 (한컴 공개 모델에서
    /// 두 요소가 같은 클래스 `CAutoNumNewNumType`이다).
    func testNewNumberKindsFollowTheAutoNumberVocabulary() throws {
        let expected: [(String, HwpAutoNumberKind)] = [
            ("PAGE", .page), ("FOOTNOTE", .footnote), ("ENDNOTE", .endnote),
            ("PICTURE", .picture), ("TABLE", .table), ("EQUATION", .equation),
        ]
        for (name, kind) in expected {
            guard case let .newNumber(control) = try mark(
                "<hp:ctrl><hp:newNum num=\"3\" numType=\"\(name)\"/></hp:ctrl>"
            ) else {
                return fail("Expected .newNumber for \(name)")
            }
            expect(control.newNumberInfo?.kind).to(equal(kind), description: name)
        }
    }

    /// 속성 생략은 한컴 공개 모델 생성자 값(`m_nNum(1)`·`m_uNumType(ANT_PAGE)`)이다.
    func testOmittedNewNumberAttributesUseReferenceModelDefaults() throws {
        guard case let .newNumber(control) = try mark(
            "<hp:ctrl><hp:newNum/></hp:ctrl>"
        ) else {
            return fail("Expected .newNumber")
        }
        expect(control.newNumberInfo?.property) == 0
        expect(control.newNumberInfo?.number) == 1
    }

    /// **`TOTAL_PAGE`는 승격하지 않는다** — `HwpAutoNumberKind`가 0-5뿐이라
    /// `.page`로 접히는데, 새 번호의 `.page`는 `pendingPageNumber`를 갈아 그
    /// 뒤 **모든 쪽**의 번호를 바꾼다. 강등 상태에는 없던 오작동이므로 자리
    /// (코드 21·4CC)만 지키고 되돌린다.
    func testUnrepresentableNewNumberKindsFallBackToTheDegradedAnchor() throws {
        for name in ["TOTAL_PAGE", "MYSTERY"] {
            let section = try mapSection(markBody(
                "<hp:ctrl><hp:newNum num=\"4\" numType=\"\(name)\"/></hp:ctrl>"
            ))
            let chars = try XCTUnwrap(section.paragraph[1].paraText?.charArray)
            expect(chars.filter { $0.type == .extended }.map(\.value)).to(
                equal([21]), description: name
            )
            guard case let .notImplemented(header) = try controls(of: section)[0] else {
                return fail("Expected .notImplemented for \(name)")
            }
            expect(header.ctrlId) == HwpOtherCtrlId.newNumber.rawValue
        }
    }

    /// 참조 모델은 `hp:newNum`에도 `hp:autoNumFormat` 자식을 등록하지만 표 144에는
    /// 그 자리가 없다 — 소비하지 않고 미지 자식으로 남겨 진단에 보고한다.
    func testNewNumberKeepsAutoNumberFormatChildAsUnknownRecord() throws {
        guard case let .newNumber(control) = try mark("""
        <hp:ctrl><hp:newNum num="2" numType="PAGE">\
        <hp:autoNumFormat type="DIGIT"/></hp:newNum></hp:ctrl>
        """) else {
            return fail("Expected .newNumber")
        }
        expect(control.unknownChildren.count) == 1
        expect(control.unknownChildren.first?.payload) == Data("autoNumFormat".utf8)
    }

    // MARK: - 쪽 감추기 (표 145)

    /// 여섯 불리언 → 표 145 bits 0-5. 실물 쌍은 두 마스크(0x29·0x16)로만 덮으므로
    /// 비트별 대응은 여기서 하나씩 잠근다. 이름과 순서는 한컴 공개 모델
    /// `pageHiding.cpp`의 나열이고, 조판이 읽는 값(0x01 머리말·0x02 꼬리말·
    /// 0x20 쪽 번호)은 `HwpPageChromeBuilder`의 표 132 환산과도 일치한다.
    func testPageHidingBooleansMapToTableOneFortyFiveBits() throws {
        let expected: [(String, UInt32)] = [
            ("hideHeader", 0x01), ("hideFooter", 0x02), ("hideMasterPage", 0x04),
            ("hideBorder", 0x08), ("hideFill", 0x10), ("hidePageNum", 0x20),
        ]
        for (name, bit) in expected {
            guard case let .pageHide(control) = try mark(
                "<hp:ctrl><hp:pageHiding \(name)=\"1\"/></hp:ctrl>"
            ) else {
                return fail("Expected .pageHide for \(name)")
            }
            expect(control.pageHideInfo?.rawValue).to(equal(bit), description: name)
            expect([UInt8](control.rawPayload.prefix(4))) == [0x64, 0x68, 0x67, 0x70]
            expect(control.rawPayload.count) == 8
        }
    }

    /// 속성이 하나도 없으면 마스크 0 — 참조 모델 생성자가 전부 false다.
    /// 조판이 그대로 "아무것도 감추지 않음"으로 읽는다.
    func testOmittedPageHidingAttributesHideNothing() throws {
        guard case let .pageHide(control) = try mark(
            "<hp:ctrl><hp:pageHiding/></hp:ctrl>"
        ) else {
            return fail("Expected .pageHide")
        }
        expect(control.pageHideInfo?.rawValue) == 0
    }

    // MARK: - 책갈피

    /// 컨트롤 헤더는 4CC 4바이트뿐이고 이름은 `CTRL_DATA`의 ParameterSet에 있다.
    func testBookmarkNameRidesInACtrlDataParameterSet() throws {
        guard case let .bookmark(control) = try mark(
            #"<hp:ctrl><hp:bookmark name="표식 A1"/></hp:ctrl>"#
        ) else {
            return fail("Expected .bookmark")
        }
        expect([UInt8](control.rawPayload)) == [0x6D, 0x6B, 0x6F, 0x62]
        expect(control.rawTrailing).to(beEmpty())
        expect(control.ctrlDataRecords.count) == 1
        expect([UInt8](try XCTUnwrap(control.ctrlDataRecords.first).rawPayload)) == [
            0x1B, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x40, 0x01, 0x00, 0x05, 0x00,
            0x5C, 0xD4, 0xDD, 0xC2, 0x20, 0x00, 0x41, 0x00, 0x31, 0x00,
        ]
        expect(control.bookmarkInfo?.name) == "표식 A1"
        expect(control.bookmarkInfo?.nameCharacterCount) == 5
    }

    // MARK: - 찾아보기 표식

    /// 키워드는 속성이 아니라 자식 요소의 텍스트다 (참조 모델 `indexmark.cpp`는
    /// 속성을 하나도 읽지 않는다). 문자열 뒤 UINT32는 한글 12.30 실측 -1이다.
    func testIndexmarkKeywordsComeFromChildElements() throws {
        guard case let .indexmark(control) = try mark("""
        <hp:ctrl><hp:indexmark><hp:firstKey>본문</hp:firstKey></hp:indexmark></hp:ctrl>
        """) else {
            return fail("Expected .indexmark")
        }
        expect([UInt8](control.rawPayload)) == [
            0x6D, 0x78, 0x64, 0x69, 0x02, 0x00, 0xF8, 0xBC, 0x38, 0xBB,
            0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        ]
        expect(control.indexmarkInfo?.text) == "본문"
        expect(control.indexmarkInfo?.textCharacterCount) == 2
    }

    /// 두 번째 키워드는 실물 표본이 없다 — 첫 키워드와 같은 (길이 WORD + WCHAR)
    /// 꼴로 이어 붙이고 합성 입력으로만 잠근다.
    func testIndexmarkSecondKeyFollowsTheFirstKeyLayout() throws {
        guard case let .indexmark(control) = try mark("""
        <hp:ctrl><hp:indexmark><hp:firstKey>가</hp:firstKey>\
        <hp:secondKey>나</hp:secondKey></hp:indexmark></hp:ctrl>
        """) else {
            return fail("Expected .indexmark")
        }
        expect([UInt8](control.rawPayload)) == [
            0x6D, 0x78, 0x64, 0x69,
            0x01, 0x00, 0x00, 0xAC,
            0x01, 0x00, 0x98, 0xB0,
            0xFF, 0xFF, 0xFF, 0xFF,
        ]
        // 바이너리 뷰는 첫 키워드만 typed로 읽고 나머지는 trailing에 남긴다.
        expect(control.indexmarkInfo?.text) == "가"
        expect([UInt8](try XCTUnwrap(control.indexmarkInfo?.rawTrailing)))
            == [0x01, 0x00, 0x98, 0xB0, 0xFF, 0xFF, 0xFF, 0xFF]
    }

    // MARK: - 안전

    /// 길이 WORD에 담기지 않는 문자열은 **트랩 대신 강등**이다 (P1) — 길이만
    /// 접으면 길이 필드와 바이트가 어긋나 문자열이 조용히 잘린다. 던지지도
    /// 않는다: 이 컨트롤은 구역 첫 문단(복구 대상이 아닌 자리)에 흔히 놓여
    /// 던지면 문서 전체가 파싱 실패가 된다.
    func testOverlongNamesDegradeInsteadOfTrappingOrThrowing() throws {
        let overlong = String(repeating: "가", count: Int(WORD.max) + 1)
        let cases = [
            "<hp:ctrl><hp:bookmark name=\"\(overlong)\"/></hp:ctrl>",
            "<hp:ctrl><hp:indexmark><hp:firstKey>\(overlong)</hp:firstKey>"
                + "</hp:indexmark></hp:ctrl>",
        ]
        let fourCCs = [HwpOtherCtrlId.bookmark.rawValue, HwpOtherCtrlId.indexmark.rawValue]
        for (body, fourCC) in zip(cases, fourCCs) {
            let section = try mapSection(markBody(body))
            let chars = try XCTUnwrap(section.paragraph[1].paraText?.charArray)
            expect(chars.filter { $0.type == .extended }.map(\.value)) == [22]
            guard case let .notImplemented(header) = try controls(of: section)[0] else {
                return fail("Expected .notImplemented for overlong name")
            }
            expect(header.ctrlId) == fourCC
        }
    }

    /// typed 뷰는 `.viewer`(payload 보존 off)에서도 살아야 한다 — 합성 payload를
    /// 바이너리 로더에 태우면 게이트 비대칭까지 그대로 따라온다.
    /// `HwpOtherControl.init`은 `rawTrailing`만 게이트에 걸고 typed 뷰는 게이트 전
    /// 원본에서 만든다. 책갈피 이름은 `HwpCtrlData`가 `decoupledPayload`라 양 모드
    /// 보존이다.
    func testTypedViewsSurviveViewerMode() throws {
        let body = """
        <hp:ctrl><hp:newNum num="9" numType="PAGE"/></hp:ctrl>\
        <hp:ctrl><hp:pageHiding hidePageNum="1"/></hp:ctrl>\
        <hp:ctrl><hp:bookmark name="표식"/></hp:ctrl>\
        <hp:ctrl><hp:indexmark><hp:firstKey>키</hp:firstKey></hp:indexmark></hp:ctrl>
        """
        let ctrls = try controls(of: try mapSection(markBody(body), options: .viewer))
        guard ctrls.count == 4,
              case let .newNumber(newNumber) = ctrls[0],
              case let .pageHide(pageHide) = ctrls[1],
              case let .bookmark(bookmark) = ctrls[2],
              case let .indexmark(indexmark) = ctrls[3]
        else {
            return fail("Expected four typed marks, got \(ctrls)")
        }
        expect(newNumber.newNumberInfo?.number) == 9
        expect(pageHide.pageHideInfo?.rawValue) == 0x20
        expect(bookmark.bookmarkInfo?.name) == "표식"
        expect(indexmark.indexmarkInfo?.text) == "키"
    }

    /// 승격된 컨트롤은 `parseDiagnostics()`의 `notImplementedControl`에서 빠진다 —
    /// 강등 상태에서는 넷 다 여기로 보고됐다.
    func testPromotedMarksLeaveTheNotImplementedDiagnostics() throws {
        let section = try mapSection(markBody("""
        <hp:ctrl><hp:newNum num="9" numType="PAGE"/></hp:ctrl>\
        <hp:ctrl><hp:pageHiding hidePageNum="1"/></hp:ctrl>\
        <hp:ctrl><hp:bookmark name="표식"/></hp:ctrl>\
        <hp:ctrl><hp:indexmark><hp:firstKey>키</hp:firstKey></hp:indexmark></hp:ctrl>
        """))
        for ctrl in try controls(of: section) {
            if case .notImplemented = ctrl {
                return fail("Expected no degraded control, got \(ctrl)")
            }
        }
    }
}
