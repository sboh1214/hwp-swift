import CoreGraphics
@testable import HwpKit
@testable import HwpKitCore
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
    /// 미룬 뒤에도 실측은 **불변**이었다 — 이 코퍼스에서는 두 결함 모두 잠재였다.
    ///
    /// 현재 값은 **macOS·iOS가 정확히 같다** (2026-08-04 실측: 366쪽·7,542pt·
    /// 353.0pt @p761). 처음 iOS 잡이 7,541pt로 빨갛던 것은 대체 폰트가 러너마다
    /// 달랐기 때문이고, `testDeterministic`에 캐스케이드를 고정한 뒤 그 축이
    /// 닫혔다 (`HwpFontResolver.fallbackCascade`). 플랫폼별로 예산을 벌려 둘
    /// 이유가 사라졌으므로 관측값에 반올림 여유만 둔다.
    private static let budgets: [String: OverlapBudget] = [
        "legacy-common-control-property": OverlapBudget(
            pages: 366, totalIntrusion: 7545, worstIntrusion: 354
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
                if let noteBounds = Self.footnoteBounds(of: page) {
                    // 세로만 보면 컨테이너 폭을 넘어 그려지는 자손 (각주 안 표는
                    // 한글도 안 자른다 — R39 #3) 이 종이 밖으로 나가도 통과한다
                    let paper = CGRect(origin: .zero, size: page.size)
                        .insetBy(dx: -Self.tolerance, dy: -Self.tolerance)
                    if !paper.contains(noteBounds) {
                        invariantFailures.append("[\(fixture.id)] " + String(
                            format: "p%d 각주 범위 x[%.1f, %.1f] y[%.1f, %.1f] ⊄ 종이 %.0f×%.0f",
                            pageIndex, noteBounds.minX, noteBounds.maxX,
                            noteBounds.minY, noteBounds.maxY,
                            page.size.width, page.size.height
                        ))
                    }
                    let overflow = noteBounds.maxY - (page.size.height - page.margins.bottom)
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
                return [paintedBounds(of: block).minY, note.separatorLine.minY]
            }
            .min()
    }

    /// 이 페이지 각주가 **그리는 범위**의 합집합 — 각주가 없으면 nil. 구분선은
    /// 스택 위라 상단 판정(`footnoteTop`)에서만 본다.
    private static func footnoteBounds(of page: HwpPage) -> CGRect? {
        page.blocks
            .filter { $0.kind == .footnote && $0.role == .body }
            .map { paintedBounds(of: $0) }
            .reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// 블록이 **그리는** 범위 — 프레임 ∪ 자손 개체 rect (#95 리뷰).
    ///
    /// 오버레이·쪽 기준 개체는 컨테이너를 **키우지 않고** 그려지므로
    /// (`HwpFootnoteObjectLayoutTests
    /// .testOverlayWrapModesDoNotGrowFootnoteBlockButStayRendered`) 프레임만 보면
    /// 종이를 넘는 각주 자손도, 각주가 덮는 본문 자손도 놓친다. 그래서 각주뿐
    /// 아니라 **본문 블록에도** 같은 자를 댄다.
    ///
    /// 순회는 페인트와 같은 walker로 받는다 (R41) — `HwpHitTester.paintedRects`의
    /// 분기(각주·표·글상자)를 그대로 따르되 문단 텍스트만 뺀다: 자격 영역의
    /// `textBounds`는 폰트 메트릭 여유를 더한 **상위집합**이라 모든 블록이 몇
    /// pt씩 부풀어 이 기하 축을 무의미하게 만든다. 텍스트는 블록 프레임이 담는다.
    private static func paintedBounds(of block: AnyHwpBlock) -> CGRect {
        var bounds = block.frame
        let origin = block.frame.origin
        func addRect(_ rect: CGRect) {
            bounds = bounds.union(rect)
        }
        func addCell(_: HwpTableCellFrame, _ rect: CGRect) {
            addRect(rect)
        }
        /// 테두리 stroke는 경로 중앙에 그어져 폭의 절반이 rect 밖이다 (R61)
        func addImage(_ image: HwpCellImage, _ rect: CGRect) {
            addRect(HwpHitTester.strokeBounds(rect, borderWidth: image.borderWidth))
        }
        /// 도형 경로는 rect를 넘을 수 있어 paintedRect가 칠 영역을 소유한다 (R63)
        func addShape(_ shape: HwpCellShape, _ rect: CGRect) {
            addRect(shape.paintedRect.offsetBy(
                dx: rect.minX - shape.rect.minX, dy: rect.minY - shape.rect.minY
            ))
        }
        /// 글상자 안 그림·도형도 클립 없이 그려진다 (R46 #1)
        func addTextboxChildren(_ textbox: HwpTextboxFrame, offset: CGPoint) {
            for child in textbox.images.map(\.paintedRect)
                + textbox.shapes.map(\.paintedRect)
            {
                addRect(child.offsetBy(dx: offset.x, dy: offset.y))
            }
        }
        func addTextbox(_ textbox: HwpCellTextbox, _ rect: CGRect) {
            addRect(HwpHitTester.strokeBounds(
                rect, borderWidth: textbox.textbox.effectiveBorderWidth
            ))
            addTextboxChildren(textbox.textbox, offset: rect.origin)
        }
        func addNestedTable(_: HwpNestedTableFrame, _ rect: CGRect) {
            addRect(rect)
        }
        let ignoreText: (NSAttributedString, CGRect, UInt32?) -> Void = { _, _, _ in }
        switch block.payload {
        case let .footnote(footnote):
            HwpBlockContentWalker.walkFootnote(
                footnote,
                origin: origin,
                onParagraphText: ignoreText,
                onCellStart: addCell,
                onCellImage: addImage,
                onCellShape: addShape,
                onCellTextbox: addTextbox,
                onNestedTable: addNestedTable
            )
        case let .table(table):
            HwpBlockContentWalker.walkTable(
                table,
                origin: origin,
                onCellStart: addCell,
                onParagraphText: ignoreText,
                onCellImage: addImage,
                onCellShape: addShape,
                onCellTextbox: addTextbox,
                onNestedTable: addNestedTable
            )
        case let .textbox(textbox):
            addTextboxChildren(textbox, offset: origin)
        default:
            break
        }
        return bounds
    }

    /// 이 페이지 본문이 **그리는** 최하단 — 잉크가 없는 블록은 세지 않는다.
    /// 표·글상자의 쪽 기준·오버레이 자식은 행을 키우지 않고 그 아래에 그려지므로
    /// 프레임만 보면 그 위를 덮은 각주가 침범 0으로 보고된다 (#95 리뷰).
    private static func bodyBottom(of page: HwpPage) -> CGFloat? {
        page.blocks
            .filter { $0.role == .body && $0.kind != .footnote && hasInk($0) }
            .map { paintedBounds(of: $0).maxY }
            .max()
    }

    /// 빈 **텍스트** 블록만 잉크가 없다 (#95 리뷰 반영). 표·그림·도형·글상자는
    /// 내용이 payload에 살아 `attributedString`이 nil이므로, 텍스트 유무로 거르면
    /// 최하단이 표인 쪽의 겹침이 통째로 예산에서 빠진다. 빈 문단 앵커(#145)는
    /// 조판 문자열이 빈칸 1자라 길이로는 못 거른다 — 표식으로 뺀다.
    private static func hasInk(_ block: AnyHwpBlock) -> Bool {
        guard block.kind == .text else { return true }
        guard let attributed = block.attributedString, attributed.length > 0 else {
            return false
        }
        return !HwpTextRunBuilder.isEmptyParagraphAnchor(attributed)
    }
}
