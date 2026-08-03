import CoreGraphics
@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 각주 스택과 본문 블록의 세로 겹침 가드 (#95).
///
/// 각주는 페이지 하단 영역에 쌓이므로 **본문 블록 아래**에 있어야 한다. 겹치면
/// 두 글자가 같은 자리에 그려져 그 띠가 통째로 읽히지 않는다. 렌더 해시는
/// "안 바뀜"만 증명하고 블록 스냅샷은 표본 페이지만 보므로 (루트 AGENTS.md
/// "렌더 가드 4층"), 이 축을 직접 검사하는 스위트가 없어 겹치는 렌더가 기준선으로
/// 굳어 있었다.
///
/// 기준선은 **커밋된 소스 상수**이고 기본 `swift test`·CI에서 상시 실행된다 —
/// 좌표를 기기 독립으로 만드는 것은 `HwpFontResolver.testDeterministic`이다.
/// 기본 resolver로 뜨면 캐시 없는 각주의 줄 수가 설치 폰트 메트릭의 함수가 되어
/// 한컴오피스가 없는 CI 러너와 갈린다.
final class FixtureFootnoteOverlapTests: XCTestCase {
    /// 겹침으로 판정할 최소 침범량 (pt). 반올림 잡음만 흡수한다.
    private static let tolerance: CGFloat = 0.5

    /// 파싱 자체가 거부되는 픽스처 — 암호 2종·배포용·DRM
    /// (`HwpError.unsupportedFeature`, FixturePreviewFidelityTests와 같은 목록)
    private static let unparseableFixtureIds: Set<String> = [
        "문서암호설정-보안수준높음",
        "문서암호설정-보안수준보통",
        "배포용문서",
        "drm-unsupported-derived",
    ]

    /// 픽스처별 겹침 예산 — **줄여야 할 빚**이지 목표가 아니다. 개선하면 함께
    /// 낮춘다 (상한이라 낮추지 않으면 다음 회귀가 그 여유 안에 숨는다).
    private struct OverlapBudget {
        let pages: Int
        let totalIntrusion: CGFloat
        let worstIntrusion: CGFloat
    }

    /// `legacy-common-control-property`(헌법주석)만 0이 아니다. 남은 원인은 한글의
    /// **각주 이어짐** — 한 페이지 각주가 본문이 남긴 자리를 넘으면 한글은 다음
    /// 쪽에 이어 싣는데 우리는 그 페이지에 전부 쌓는다. 강제 이월은 한글에 없는
    /// 각주 전용 페이지를 만들어 1,030쪽 실측을 깬다 (2026-08-03 실측: 각주 영역
    /// 상단을 본문 하단에 맞추고 넘침을 이월하면 겹침 0쪽 / **1,035쪽**, 각주 전용
    /// 페이지 485·486·669·1034) — 착수 전 한글.app 실측이 필요하다
    /// (`Sources/HwpKitCore/AGENTS.md` 각주 항목).
    ///
    /// **세 축을 같이 잠근다.** #95 수정 전후 실측 (deterministic resolver):
    /// 쪽수 362 → 368, 총 침범 14,707 → 6,917pt, 최대 470.5 → 353.0pt. 쪽수가
    /// 늘어난 것은 회귀가 아니다 — 조각 단위 귀속 전에는 앞 조각 페이지의 각주
    /// 영역이 **예약된 채 비어** 있어 (겹칠 각주 자체가 없어) 세지 않았다. 각주가
    /// 제 페이지로 돌아오면서 그 페이지가 집계에 들어오고, 대신 마지막 조각에
    /// 몰렸던 스택이 흩어져 총량과 최악값이 절반 아래로 내려간다. 그래서 심각도
    /// (총 침범·최대 침범)를 함께 기록해야 쪽수 하나로 오독하지 않는다.
    ///
    /// 조각 경계를 **그려진 슬라이스**로 통일한 뒤 (#95 리뷰 반영) 다시 재면
    /// 쪽수 368 → 366, 최대 353.0pt 불변, 총 침범 6,917 → 7,521pt다. 총량만
    /// 올라간다 — 참조가 그려진 쪽으로 각주가 돌아오면서, 캐시 좌표를 믿던
    /// 시절 뒷 쪽으로 밀려나 겹침을 면했던 각주가 제 쪽 본문 위에 다시 쌓이기
    /// 때문이다 (참조가 그 쪽에 없는 각주 43 → 1건, 남은 1건은 표 셀 참조).
    /// **정합성이 총량을 늘리는 이 경우가 예산을 올려도 되는 유일한 경우다** —
    /// 그 외에는 낮추는 방향만이고, 근거 없이 올리면 이 스위트는 존재할 이유가
    /// 없다.
    ///
    /// 잉크 판정을 표·그림·도형까지 넓히고 (`hasInk`) 중첩 각주를 마지막 조각으로
    /// 미룬 뒤에도 실측은 366쪽·7,521pt·353.0pt로 **불변**이다 — 이 코퍼스에서는
    /// 두 결함 모두 잠재였다는 뜻이고, 그래서 예산도 그대로 둔다.
    private static let budgets: [String: OverlapBudget] = [
        "legacy-common-control-property": OverlapBudget(
            pages: 366, totalIntrusion: 7525, worstIntrusion: 354
        ),
    ]

    /// 각주가 없거나 겹치지 않는 픽스처의 예산 — 전부 0이어야 한다.
    private static let cleanBudget = OverlapBudget(
        pages: 0, totalIntrusion: 0, worstIntrusion: 0
    )

    /// 각주 스택이 본문 프레임 **하단**을 넘는 양 (#95 리뷰). 상단 클램프가
    /// 콘텐츠 높이를 넘는 스택을 아래로 밀어내면서 생긴 빚이고, 옳은 답은 각주
    /// 이어짐이다. 실측 (2026-08-03, 결정론 폰트): 헌법주석 1쪽·총 4pt·최대
    /// 3.5pt @p78, 종이 밖은 0쪽. 조각 단위 귀속 전에는 거대 스택이 마지막
    /// 조각에 몰려 훨씬 컸다 — 각주가 참조 쪽으로 흩어지며 이 빚도 함께 줄었다.
    private static let bottomBudgets: [String: OverlapBudget] = [
        "legacy-common-control-property": OverlapBudget(
            pages: 1, totalIntrusion: 5, worstIntrusion: 4
        ),
    ]

    /// 세 축을 **한 순회**에서 잰다 (#95 리뷰 반영). 코퍼스를 두 번 조판하면
    /// 1,030쪽 픽스처 때문에 기본 `swift test`·CI 애플 잡마다 18초가 그대로 더
    /// 붙는다. 실패는 성격이 달라 (예산 vs 불변식) 따로 모아 각각 단언한다.
    ///
    /// **불변식**은 둘이다: 각주 영역 상단이 본문 상단 위로 올라가지 않을 것,
    /// 각주가 종이 밖으로 나가지 않을 것. 상한 없는 배치 (절대 캐시 모드) 에서
    /// 스택이 콘텐츠 높이를 넘으면 영역 상단이 음수까지 내려가 각주 앞부분이
    /// 종이 밖으로 잘려 사라졌다 (수정 전 실측: 헌법주석 5쪽, 최악 렌더 인덱스
    /// 79의 −217.6pt).
    ///
    /// 본문 프레임 **하단**을 넘는 것은 불변식이 아니라 **빚**이다 — 위 클램프가
    /// 초과분을 아래로 밀어내기 때문이고, 옳은 답은 각주 이어짐이다 (미구현).
    /// 자르면 각주가 사라지고, 강제 이월은 한글에 없는 각주 전용 페이지를 만든다
    /// (1,030 → 1,035쪽). 종이 안에 머무는 한 아래 여백을 침범할 뿐이라 예산으로
    /// 두되, 종이를 넘는 순간 불변식 위반이다.
    func testFootnoteStackStaysBelowBodyAndInsideThePage() async throws {
        var overlapFailures: [String] = []
        var bottomFailures: [String] = []
        var invariantFailures: [String] = []
        for fixture in try FixtureRoot.loadAllFixtures(from: #file)
            where !Self.unparseableFixtureIds.contains(fixture.id)
        {
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: fixture.documentURL)
            var pages = 0
            var total: CGFloat = 0
            var worst: (page: Int, amount: CGFloat) = (0, 0)
            var bottomPages = 0
            var bottomTotal: CGFloat = 0
            var bottomWorst: (page: Int, amount: CGFloat) = (0, 0)
            for (pageIndex, page) in document.pages.enumerated() {
                guard let noteTop = Self.footnoteTop(of: page) else { continue }
                let contentTop = page.margins.top
                if noteTop < contentTop - Self.tolerance {
                    invariantFailures.append("[\(fixture.id)] " + String(
                        format: "p%d 각주 영역 상단 %.1f < 본문 상단 %.1f",
                        pageIndex, noteTop, contentTop
                    ))
                }
                if let noteBottom = Self.footnoteBottom(of: page) {
                    if noteBottom > page.size.height + Self.tolerance {
                        invariantFailures.append("[\(fixture.id)] " + String(
                            format: "p%d 각주 하단 %.1f > 종이 %.1f",
                            pageIndex, noteBottom, page.size.height
                        ))
                    }
                    let overflow = noteBottom - (page.size.height - page.margins.bottom)
                    if overflow > Self.tolerance {
                        bottomPages += 1
                        bottomTotal += overflow
                        if overflow > bottomWorst.amount {
                            bottomWorst = (pageIndex, overflow)
                        }
                    }
                }
                guard let bodyBottom = Self.bodyBottom(of: page) else { continue }
                let intrusion = bodyBottom - noteTop
                guard intrusion > Self.tolerance else { continue }
                pages += 1
                total += intrusion
                if intrusion > worst.amount {
                    worst = (pageIndex, intrusion)
                }
            }
            let budget = Self.budgets[fixture.id] ?? Self.cleanBudget
            if pages > budget.pages || total > budget.totalIntrusion
                || worst.amount > budget.worstIntrusion
            {
                overlapFailures.append("[\(fixture.id)] " + String(
                    format: "각주가 본문을 덮음 — 쪽 %d (허용 %d), 총 침범 %.0fpt "
                        + "(허용 %.0f), 최대 %.1fpt @p%d (허용 %.0f)",
                    pages, budget.pages, total, budget.totalIntrusion,
                    worst.amount, worst.page, budget.worstIntrusion
                ))
            }
            let bottomBudget = Self.bottomBudgets[fixture.id] ?? Self.cleanBudget
            if bottomPages > bottomBudget.pages || bottomTotal > bottomBudget.totalIntrusion
                || bottomWorst.amount > bottomBudget.worstIntrusion
            {
                bottomFailures.append("[\(fixture.id)] " + String(
                    format: "각주가 본문 하단을 넘음 — 쪽 %d (허용 %d), 총 %.0fpt "
                        + "(허용 %.0f), 최대 %.1fpt @p%d (허용 %.0f)",
                    bottomPages, bottomBudget.pages, bottomTotal, bottomBudget.totalIntrusion,
                    bottomWorst.amount, bottomWorst.page, bottomBudget.worstIntrusion
                ))
            }
        }
        expect(invariantFailures.joined(separator: "\n")) == ""
        expect(overlapFailures.joined(separator: "\n")) == ""
        expect(bottomFailures.joined(separator: "\n")) == ""
    }

    // MARK: - 페이지 기하

    /// 이 페이지 각주 스택의 최상단 (구분선 포함) — 각주가 없으면 nil.
    /// 머리말/꼬리말 (`role == .pageChrome`) 은 본문 흐름이 아니라 제외한다.
    private static func footnoteTop(of page: HwpPage) -> CGFloat? {
        page.blocks
            .filter { $0.kind == .footnote && $0.role == .body }
            .flatMap { block -> [CGFloat] in
                guard case let .footnote(note) = block.payload else { return [block.frame.minY] }
                // 구분선은 블록-로컬이 아니라 페이지 좌표다 (HwpFootnoteBlock 참조).
                return [block.frame.minY, note.separatorLine.minY]
            }
            .min()
    }

    /// 이 페이지 각주 스택의 최하단 — 각주가 없으면 nil. 구분선은 스택 위라
    /// 하단 판정에는 블록만 본다.
    private static func footnoteBottom(of page: HwpPage) -> CGFloat? {
        page.blocks
            .filter { $0.kind == .footnote && $0.role == .body }
            .map(\.frame.maxY)
            .max()
    }

    /// 이 페이지 본문의 최하단 — 잉크가 없는 블록은 세지 않는다.
    private static func bodyBottom(of page: HwpPage) -> CGFloat? {
        page.blocks
            .filter { $0.role == .body && $0.kind != .footnote && hasInk($0) }
            .map(\.frame.maxY)
            .max()
    }

    /// 빈 **텍스트** 블록만 잉크가 없다 (#95 리뷰 반영). 표·그림·도형·글상자는
    /// 내용이 payload에 살아 `attributedString`이 nil이므로, 텍스트 유무로 거르면
    /// 최하단이 표인 쪽의 겹침이 통째로 예산에서 빠진다.
    private static func hasInk(_ block: AnyHwpBlock) -> Bool {
        guard block.kind == .text else { return true }
        return (block.attributedString?.length ?? 0) > 0
    }
}
