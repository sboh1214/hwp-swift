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
/// "렌더 가드 3층"), 이 축을 직접 검사하는 스위트가 없어 겹치는 렌더가 기준선으로
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
    private static let budgets: [String: OverlapBudget] = [
        "legacy-common-control-property": OverlapBudget(
            pages: 368, totalIntrusion: 6920, worstIntrusion: 354
        ),
    ]

    /// 각주가 없거나 겹치지 않는 픽스처의 예산 — 전부 0이어야 한다.
    private static let cleanBudget = OverlapBudget(
        pages: 0, totalIntrusion: 0, worstIntrusion: 0
    )

    func testFootnoteStackDoesNotOverlapBody() async throws {
        var failures: [String] = []
        for fixture in try FixtureRoot.loadAllFixtures(from: #file)
            where !Self.unparseableFixtureIds.contains(fixture.id)
        {
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: fixture.documentURL)
            var pages = 0
            var total: CGFloat = 0
            var worst: (page: Int, amount: CGFloat) = (0, 0)
            for (pageIndex, page) in document.pages.enumerated() {
                guard let noteTop = Self.footnoteTop(of: page),
                      let bodyBottom = Self.bodyBottom(of: page) else { continue }
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
                failures.append("[\(fixture.id)] " + String(
                    format: "각주가 본문을 덮음 — 쪽 %d (허용 %d), 총 침범 %.0fpt "
                        + "(허용 %.0f), 최대 %.1fpt @p%d (허용 %.0f)",
                    pages, budget.pages, total, budget.totalIntrusion,
                    worst.amount, worst.page, budget.worstIntrusion
                ))
            }
        }
        expect(failures.joined(separator: "\n")) == ""
    }

    /// 각주 영역은 본문 상단 위로 올라가지 못한다 (#95).
    ///
    /// 상한 없는 배치 (절대 캐시 모드) 에서 스택이 콘텐츠 높이를 넘으면 영역
    /// 상단이 음수까지 내려가 각주 **앞부분이 종이 밖으로 잘려 사라졌다** (수정 전
    /// 실측: 헌법주석 5쪽, 최악 렌더 인덱스 79의 −217.6pt). 위 겹침과 달리 이쪽은
    /// 빚이 아니라 **불변식**이다 — 어느 픽스처에서도 0이어야 한다.
    func testFootnoteAreaStaysInsideContentTop() async throws {
        var failures: [String] = []
        for fixture in try FixtureRoot.loadAllFixtures(from: #file)
            where !Self.unparseableFixtureIds.contains(fixture.id)
        {
            let document = try await HwpDocumentLoader(fontResolver: .testDeterministic)
                .load(from: fixture.documentURL)
            for (pageIndex, page) in document.pages.enumerated() {
                guard let noteTop = Self.footnoteTop(of: page) else { continue }
                let contentTop = page.margins.top
                if noteTop < contentTop - Self.tolerance {
                    failures.append("[\(fixture.id)] " + String(
                        format: "p%d 각주 영역 상단 %.1f < 본문 상단 %.1f",
                        pageIndex, noteTop, contentTop
                    ))
                }
            }
        }
        expect(failures.joined(separator: "\n")) == ""
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

    /// 이 페이지 본문 텍스트의 최하단 — 빈 블록은 잉크가 없으니 세지 않는다.
    private static func bodyBottom(of page: HwpPage) -> CGFloat? {
        page.blocks
            .filter {
                $0.role == .body && $0.kind != .footnote
                    && ($0.attributedString?.length ?? 0) > 0
            }
            .map(\.frame.maxY)
            .max()
    }
}
