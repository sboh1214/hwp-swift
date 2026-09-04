import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 접근성 요소 합성 (#79) — 라벨·rect·낭독 순서·헤딩 판정·메모 패널 전개.
/// 순수 함수라 플랫폼 뷰 없이 검증한다 (뷰 통합은 HwpKitNativeTests 몫).
final class HwpAccessibilityContentTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
    }

    private func textBlock(
        _ text: String,
        frame: CGRect,
        role: HwpBlockRole = .body
    ) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: frame,
            kind: .text,
            attributedString: attributed(text),
            role: role
        )
    }

    private func page(blocks: [AnyHwpBlock], height: CGFloat = 842) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: height),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: blocks,
            pageNumber: 1
        )
    }

    private func pageUnits(
        _ page: HwpPage, headingTitles: [String] = []
    ) -> [HwpAccessibilityUnit] {
        HwpAccessibilityContent.pageUnits(
            page: page,
            bodyUnits: HwpSelectableText.units(in: page),
            headingTitles: headingTitles
        )
    }

    // MARK: - 본문 라벨

    func testBodyUnitsBecomeLabeledElementsInDocumentOrder() {
        let page = page(blocks: [
            textBlock("첫 문단", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
            textBlock("둘째 문단", frame: CGRect(x: 50, y: 140, width: 400, height: 20)),
        ])

        let units = pageUnits(page)

        expect(units.map(\.label)) == ["첫 문단", "둘째 문단"]
        expect(units.map(\.kind)) == [.body, .body]
        expect(units[0].rect) == CGRect(x: 50, y: 100, width: 400, height: 20)
    }

    /// U+FFFC 개체 자리 표시 마커는 낭독 라벨에서 지운다 — 복사
    /// (`plainText(for:)`) 와 같은 정리다.
    func testControlMarkersAreStrippedFromLabels() {
        let page = page(blocks: [
            textBlock("그림\u{FFFC} 설명", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
        ])

        expect(self.pageUnits(page).map(\.label)) == ["그림 설명"]
    }

    /// 마커를 지우고 공백만 남는 단위는 버린다 — 읽을 것이 없는 요소는
    /// VoiceOver 탐색만 늘린다.
    func testWhitespaceOnlyUnitsAreSkipped() {
        let page = page(blocks: [
            textBlock("  \u{FFFC}  ", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
            textBlock("본문", frame: CGRect(x: 50, y: 140, width: 400, height: 20)),
        ])

        expect(self.pageUnits(page).map(\.label)) == ["본문"]
    }

    /// 한 줄 끝(10)으로 끝난 문단의 빈 줄 앵커는 **공백**이어야 한다 (#137).
    /// 앵커를 U+200B로 두면 `isWhitespace`가 거짓이라 이 건너뛰기를 통과해
    /// 읽을 것이 없는 VoiceOver 정지점이 생긴다.
    func testEmptyLastLineAnchorDoesNotCreateAReadableUnit() {
        let page = page(blocks: [
            textBlock("\u{0A} ", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
            textBlock("본문", frame: CGRect(x: 50, y: 140, width: 400, height: 20)),
        ])

        expect(self.pageUnits(page).map(\.label)) == ["본문"]
    }

    // MARK: - 쪽 크롬

    /// 머리말/꼬리말/쪽 번호는 본문 단위 (`HwpSelectableText`) 가 걷지 않으므로
    /// 별도 순회로 싣는다 — 낭독 순서는 상단 크롬 → 본문 → 하단 크롬.
    func testChromeSurroundsBodyInReadingOrder() {
        let page = page(blocks: [
            textBlock("본문", frame: CGRect(x: 50, y: 400, width: 400, height: 20)),
            textBlock(
                "쪽 번호 1", frame: CGRect(x: 270, y: 800, width: 60, height: 16),
                role: .pageChrome
            ),
            textBlock(
                "머리말", frame: CGRect(x: 50, y: 20, width: 400, height: 16),
                role: .pageChrome
            ),
        ])

        let units = pageUnits(page)

        expect(units.map(\.label)) == ["머리말", "본문", "쪽 번호 1"]
        expect(units.map(\.kind)) == [.pageChrome, .body, .pageChrome]
    }

    /// 같은 그룹 안 크롬은 위 → 아래, 같은 줄이면 왼쪽 → 오른쪽으로 읽는다.
    func testChromeWithinGroupSortsByPosition() {
        let page = page(blocks: [
            textBlock(
                "오른쪽 머리말", frame: CGRect(x: 400, y: 20, width: 100, height: 16),
                role: .pageChrome
            ),
            textBlock(
                "왼쪽 머리말", frame: CGRect(x: 50, y: 20, width: 100, height: 16),
                role: .pageChrome
            ),
        ])

        expect(self.pageUnits(page).map(\.label)) == ["왼쪽 머리말", "오른쪽 머리말"]
    }

    // MARK: - 헤딩 판정

    /// 안 잘린 제목은 문단 평문 전체다 — 공백 접힘 정규화 뒤 **동등** 대조.
    func testHeadingMatchesWholeParagraphTitle() {
        let page = page(blocks: [
            textBlock("제1장  총칙과 부칙", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
            textBlock("일반 본문", frame: CGRect(x: 50, y: 140, width: 400, height: 20)),
        ])

        let units = pageUnits(page, headingTitles: ["제1장 총칙과 부칙"])

        expect(units.map(\.isHeading)) == [true, false]
    }

    /// 안 잘린 제목에 접두 대조를 쓰면 같은 쪽에서 접두가 겹치는 일반 문단이
    /// 전부 헤딩으로 오탐된다 — 로터 "제목" 탐색이 엉뚱한 자리에 선다.
    func testBodyParagraphSharingTitlePrefixIsNotHeading() {
        let page = page(blocks: [
            textBlock("요약", frame: CGRect(x: 50, y: 100, width: 400, height: 20)),
            textBlock("요약하면 다음과 같다", frame: CGRect(x: 50, y: 140, width: 400, height: 20)),
        ])

        let units = pageUnits(page, headingTitles: ["요약"])

        expect(units.map(\.isHeading)) == [true, false]
    }

    /// 200자 상한에 닿은 제목만 문단 평문의 접두일 수 있다 — 그때는 접두 대조.
    func testTruncatedTitleMatchesByPrefix() {
        let truncated = String(repeating: "가", count: HwpOutlineItem.titleCharacterLimit)

        expect(HwpAccessibilityContent.isHeading(
            label: truncated + " 이어지는 본문", titles: [truncated]
        )) == true
    }

    /// 쪽/단 경계로 쪼개진 제목 문단은 첫 조각 라벨이 제목보다 짧다 — 역방향
    /// 접두 대조로 첫 조각을 로터 정지점으로 남긴다 (뒤 조각은 접두가 아니라
    /// 표시되지 않는다).
    func testSplitHeadingFirstFragmentIsMarked() {
        expect(HwpAccessibilityContent.isHeading(
            label: "제1장 총칙과", titles: ["제1장 총칙과 부칙"]
        )) == true
        expect(HwpAccessibilityContent.isHeading(
            label: "부칙", titles: ["제1장 총칙과 부칙"]
        )) == false
    }

    /// 조판 문자열의 묶음 빈칸(30)·고정폭 빈칸(31)은 유니코드 공백이 아니라
    /// isWhitespace 접힘에 안 걸린다 — 제목 수집(`titleUnits`)처럼 공백으로
    /// 매핑해야 대조가 성립한다.
    func testControlCharacterSpacesMatchTitleNormalization() {
        expect(HwpAccessibilityContent.isHeading(
            label: "제1장\u{1E}총칙", titles: ["제1장 총칙"]
        )) == true
        expect(HwpAccessibilityContent.collapsedForTitleMatch("제1장\u{1F}총칙"))
            == "제1장 총칙"
    }

    /// 헤딩은 본문 단위에만 붙는다 — 개요 스코프가 최상위 본문 문단이라
    /// (#77) 크롬 텍스트는 제목과 겹쳐도 헤딩이 아니다.
    func testChromeIsNeverMarkedAsHeading() {
        let page = page(blocks: [
            textBlock(
                "제1장 총칙", frame: CGRect(x: 50, y: 20, width: 400, height: 16),
                role: .pageChrome
            ),
        ])

        let units = pageUnits(page, headingTitles: ["제1장 총칙"])

        expect(units.map(\.isHeading)) == [false]
    }

    func testEmptyTitleNeverMatchesAsHeading() {
        expect(HwpAccessibilityContent.isHeading(label: "본문", titles: [""])) == false
        expect(HwpAccessibilityContent.isHeading(label: "본문", titles: [])) == false
    }

    // MARK: - 메모 패널

    /// 패널 모델은 paint list 만 보유하므로 `.drawText` 를 전개한다 — rect 는
    /// 렌더와 같은 조판 (`HwpDrawnTextLayout`) 의 줄 상자 합집합이다.
    func testMemoPanelDrawTextBecomesElements() {
        let panel = HwpMemoPanel(
            width: 200,
            paintList: HwpPaintList(commands: [
                .fillRect(rect: CGRect(x: 0, y: 0, width: 200, height: 60), color: CGColor(
                    gray: 1, alpha: 1
                )),
                .drawText(
                    attributedString: attributed("메모 내용"),
                    origin: CGPoint(x: 10, y: 20),
                    lineWidth: 180
                ),
            ]),
            contentHeight: 120
        )

        let units = HwpAccessibilityContent.memoPanelUnits(panel: panel)

        expect(units.count) == 1
        expect(units[0].kind) == HwpAccessibilityUnit.Kind.memo
        expect(units[0].label) == "메모 내용"
        // 줄 상자는 origin 에서 시작하고 (좌측 정렬) 높이가 양수다.
        expect(units[0].rect.minX) == 10
        expect(units[0].rect.height) > 0
        expect(units[0].rect.minY) >= 20 - 1
    }

    func testMemoPanelSkipsWhitespaceOnlyText() {
        let panel = HwpMemoPanel(
            width: 200,
            paintList: HwpPaintList(commands: [
                .drawText(
                    attributedString: attributed("   "),
                    origin: CGPoint(x: 10, y: 20),
                    lineWidth: 180
                ),
            ])
        )

        expect(HwpAccessibilityContent.memoPanelUnits(panel: panel)).to(beEmpty())
    }

    func testMemoPanelWithoutTextCommandsIsEmpty() {
        let panel = HwpMemoPanel(width: 200, paintList: HwpPaintList(commands: []))

        expect(HwpAccessibilityContent.memoPanelUnits(panel: panel)).to(beEmpty())
    }
}
