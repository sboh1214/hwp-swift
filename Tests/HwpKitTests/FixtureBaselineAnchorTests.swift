import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 그려지는 베이스라인이 **문서 자신의 줄 캐시**와 맞는지 (#178).
///
/// 오라클은 한글이 저장한 `PARA_LINE_SEG`다 — 베이스라인 = 줄 상자 상단
/// (`lineLocation`) + `baselineDistance`. 두 값 모두 문서에 적혀 있으므로 이 스위트는
/// 우리 렌더를 우리 산식이 아니라 **한글의 기록**에 맞춘다.
///
/// 한글 12.30.0 (2026-09-12) 이 같은 규칙으로 **그린다**는 것은 PDF 내보내기의
/// 벡터 텍스트 베이스라인으로 확인했다: 글자 크기 8종 × 줄 간격 종류 4종 × 글꼴 3종 ×
/// 상대크기 2종을 실은 합성 문서 34줄에서 PDF 베이스라인이 `vertpos + baseline`과
/// 최대 0.10pt(한글 PDF의 0.12pt 장치 양자화) 차이였고, `CharShape`의 12줄과
/// `noori` 본문 18줄도 같았다. 비율은 `HwpBaselineAnchorTests`가, 픽셀 자리는
/// `FixtureDecorationLineRenderTests`가 함께 잠근다.
///
/// 폰트는 `HwpFontResolver.testDeterministic`이다 — 앵커는 글꼴 지표의 함수가
/// 아니므로 (그것이 이 수정의 요지다) 기기·CI가 같은 값을 낸다.
final class FixtureBaselineAnchorTests: XCTestCase {
    private static func firstPage(_ id: String, file: String = #file) async throws -> HwpPage {
        let url = FixtureRoot.url(from: file)
            .appendingPathComponent(id)
            .appendingPathComponent("document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        return try XCTUnwrap(document.pages.first)
    }

    /// pt 비교 허용 오차 — 누적 부동소수 잔차만 흡수한다 (실측 일치는 정확하다).
    private static let tolerance = 0.001

    /// 쪽의 `drawText` 명령마다 그 블록의 줄 전체를 돌려준다.
    private static func drawnLines(_ page: HwpPage) -> [[HwpDrawnLine]] {
        page.paintList.commands.compactMap { command in
            guard case let .drawText(attributedString, origin, lineWidth) = command
            else { return nil }
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            return lines.isEmpty ? nil : lines
        }
    }

    /// 쪽의 `drawText` 명령마다 (그 블록 상단, 첫 줄 베이스라인)을 돌려준다.
    private static func textBlocks(_ page: HwpPage) -> [(top: CGFloat, baseline: CGFloat)] {
        page.paintList.commands.compactMap { command in
            guard case let .drawText(attributedString, origin, lineWidth) = command,
                  let first = HwpDrawnTextLayout.lines(
                      attributedString: attributedString, origin: origin, lineWidth: lineWidth
                  ).first
            else { return nil }
            return (origin.y, first.baselineOrigin.y)
        }
    }

    /// `CharShape` 12문단 — 줄 캐시는 전부 `vertsize=1000 baseline=850`이고 세로 위치가
    /// 1600 HWPUNIT 간격이다. 본문 상단 99.2pt에서 베이스라인은 107.7 + 16k다.
    /// 4번째 줄은 상대크기 170%(실제 17pt)인데 한글은 줄 상자와 베이스라인을 **기본
    /// 크기 10pt 기준으로 유지**하므로 그 줄도 같은 간격이다 — 수정 전에는 이 줄만
    /// 2.76pt, 나머지는 1.30pt 아래였다.
    func testCharShapeBaselinesMatchTheSavedLineCache() async throws {
        let page = try await Self.firstPage("CharShape")
        let expected = (0 ..< 12).map { 107.7 + 16 * Double($0) }
        expect(Self.textBlocks(page).map { Double($0.baseline) })
            .to(beCloseTo(expected, within: Self.tolerance))
        expect(Self.textBlocks(page).map { Double($0.top) })
            .to(beCloseTo(expected.map { $0 - 8.5 }, within: Self.tolerance))
    }

    /// `underline-above` 한 줄 — 한글 PDF의 텍스트 베이스라인 실측이 107.76pt다
    /// (#178 이슈 본문이 '글자 위' 밑줄 위치로 역산한 값과 같다).
    func testUnderlineAboveBaselineMatchesTheSavedLineCache() async throws {
        let page = try await Self.firstPage("underline-above")
        expect(Self.textBlocks(page).map { Double($0.baseline) })
            .to(beCloseTo([107.7], within: Self.tolerance))
    }

    /// `multi-section` 첫 구역 — 구역이 갈려도 본문 첫 줄은 같은 앵커다.
    func testMultiSectionBaselineMatchesTheSavedLineCache() async throws {
        let page = try await Self.firstPage("multi-section")
        expect(Self.textBlocks(page).map { Double($0.baseline) })
            .to(beCloseTo([107.7], within: Self.tolerance))
    }

    /// `CCL` — **키 큰 글자처럼 취급 개체가 첫 줄에 있고 문단이 줄바꿈되는** 실물이다.
    /// 줄 캐시가 `loc=0 h=4087 baseline=3474` (CCL 로고 40.87pt 상자) 와
    /// `loc=4687 h=1000 baseline=850` 이므로 한글의 baseline은 본문 상단 99.2pt에서
    /// **133.94pt · 154.57pt**다.
    ///
    /// 첫 줄 상자가 큰 문단에서 CT 줄 origin 델타를 그대로 상자 간격으로 쓰면 둘째 줄이
    /// **첫 줄보다, 심지어 개체 상자 바닥보다 위로** 올라간다 (그 형태의 회귀를 한 번 냈다 —
    /// 123.70pt였다). 그래서 여기서 잠그는 것은 ① 첫 줄 baseline 정확값과 ② 둘째 줄이 개체
    /// 상자 바닥 아래라는 것이다.
    ///
    /// 둘째 줄의 절댓값은 줄 **전진량** 축이라 글꼴에 딸린다 — 한글의 전진량은 상자 40.87 +
    /// 간격 6.00 = 46.87인데 우리는 CT의 자연 슬롯을 쓰므로 결정론 글꼴에서 47.95,
    /// 실제 함초롬에서 46.17이 된다 (#180). 그 폭까지 담는 허용 오차로 둔다.
    func testTallInlineObjectOnTheFirstLineKeepsTheFollowingLineBelow() async throws {
        let page = try await Self.firstPage("CCL")
        let baselines = Self.textBlocks(page).map { Double($0.baseline) }
        expect(baselines.count).to(beGreaterThanOrEqualTo(1))
        let lines = try XCTUnwrap(Self.drawnLines(page).first)
        expect(lines.count).to(equal(2))
        guard lines.count == 2 else { return }
        expect(Double(lines[0].baselineOrigin.y))
            .to(beCloseTo(133.94, within: 0.01))
        // 첫 줄 상자 바닥 = 본문 상단 99.2 + 상자 40.87. 둘째 줄은 그 아래여야 한다.
        expect(lines[1].baselineOrigin.y).to(
            beGreaterThan(99.2 + 40.87), description: "둘째 줄은 개체 상자 바닥 아래"
        )
        expect(Double(lines[1].baselineOrigin.y)).to(beCloseTo(154.57, within: 1.5))
    }

    /// `footnote-endnote` — 본문(10pt)과 각주 문단(9pt)이 각자의 줄 상자 앵커를 쓴다.
    /// 각주 줄 캐시의 `baselineDistance`는 765 HWPUNIT = 7.65pt이고
    /// (`FixtureFootnoteContinuationTests`가 헌법주석에서 같은 값을 쓴다),
    /// 본문은 850 = 8.5pt다. 각주 스택의 **절대** y는 각주 배치의 함수라 여기서는
    /// 블록 상단 대비 앵커만 잠근다.
    func testFootnoteAndBodyUseTheirOwnLineBoxAnchor() async throws {
        let page = try await Self.firstPage("footnote-endnote")
        let anchors = Self.textBlocks(page).map { Double($0.baseline - $0.top) }
        expect(anchors).to(beCloseTo([8.5, 7.65], within: Self.tolerance))
    }
}
