import CoreGraphics
import Foundation

/// 합성 접근성 요소 하나 — VoiceOver 가 낭독할 평문 라벨과 대상 표면
/// (페이지 또는 메모 패널) 로컬 top-down rect (#79).
///
/// 문서 본문은 뷰가 아니라 `CALayer` 로 그려져 AX 트리가 없으므로, 뷰가 이
/// 모델을 플랫폼 요소 (`NSAccessibilityElement`/`UIAccessibilityElement`) 로
/// 감싸 노출한다. rect 를 뷰 좌표로 옮기는 것은 레이어 frame 을 아는 뷰 몫이다.
public struct HwpAccessibilityUnit: Sendable, Equatable {
    /// 요소의 출처 — 낭독 순서는 상단 크롬 → 본문 → 하단 크롬 → 메모다.
    public enum Kind: String, Sendable, Hashable {
        /// 본문 텍스트 단위 (`HwpTextUnit` 과 동형)
        case body
        /// 머리말/꼬리말/쪽 번호 — 선택·복사·검색에서는 빠지지만 낭독에서
        /// 통째로 사라지면 안 된다 (`HwpSelectableText` 가 본문만 걷는 이유)
        case pageChrome
        /// 메모 (댓글) 풍선 패널 텍스트 — rect 는 패널 로컬이다
        case memo
    }

    public let kind: Kind
    /// 낭독 라벨 — U+FFFC 개체 마커를 제거한 평문. 공백뿐인 단위는 합성
    /// 단계에서 버려지므로 언제나 읽을 것이 있다.
    public let label: String
    /// 대상 표면 로컬 top-down rect — body/pageChrome 은 페이지, memo 는 패널.
    public let rect: CGRect
    /// 개요 제목 문단인가 — VoiceOver 헤딩 트레이트·로터 탐색 재료 (#77 의
    /// `HwpDocumentMetadata.outline` 과 제목 접두 대조로 판정한다).
    public let isHeading: Bool

    public init(kind: Kind, label: String, rect: CGRect, isHeading: Bool = false) {
        self.kind = kind
        self.label = label
        self.rect = rect
        self.isHeading = isHeading
    }
}

/// 페이지 콘텐츠 → 접근성 요소 모델 합성 (#79). 순수 함수라 플랫폼 뷰 없이
/// 검증된다 — 뷰는 결과를 레이어 frame origin 만큼 옮겨 플랫폼 요소로 감싼다.
public enum HwpAccessibilityContent {
    /// 페이지 하나의 접근성 요소 (페이지 로컬 top-down, 낭독 순서).
    ///
    /// - Parameters:
    ///   - bodyUnits: 본문 텍스트 단위. 뷰는 `HwpSelectionGeometry.units(forPage:)`
    ///     캐시를 그대로 넘겨 단위 전개를 이중화하지 않는다 (검색 #75 와 같은
    ///     이유 — 1,030쪽 문서에서 단위 전개 두 벌 상주 금지).
    ///   - headingTitles: 이 쪽의 개요 제목 목록 (`HwpDocumentMetadata.outline`).
    ///     제목은 컨트롤 제거·공백 접힘 정규화를 지난 문단 평문이므로 같은
    ///     정규화 뒤 대조해 헤딩을 표시한다 (세 갈래 규칙은 `isHeading` doc).
    ///
    /// 낭독 순서: 페이지 상반부 크롬 (머리말) → 본문 (문서 순서) → 하반부
    /// 크롬 (꼬리말/쪽 번호). 크롬은 블록 좌표만으로 머리말/꼬리말을 구분할
    /// 수단이 rect 뿐이라 페이지 세로 중앙을 경계로 가른다.
    public static func pageUnits(
        page: HwpPage,
        bodyUnits: [HwpTextUnit],
        headingTitles: [String] = []
    ) -> [HwpAccessibilityUnit] {
        var headerChrome: [HwpAccessibilityUnit] = []
        var footerChrome: [HwpAccessibilityUnit] = []
        for block in page.blocks where block.role == .pageChrome {
            HwpBlockContentWalker.walkText(block: block) { attributed, rect, _ in
                guard let label = accessibilityLabel(attributed.string) else { return }
                let unit = HwpAccessibilityUnit(kind: .pageChrome, label: label, rect: rect)
                if rect.midY <= page.size.height / 2 {
                    headerChrome.append(unit)
                } else {
                    footerChrome.append(unit)
                }
            }
        }
        headerChrome.sort(by: isInReadingOrder)
        footerChrome.sort(by: isInReadingOrder)

        let body = bodyUnits.compactMap { unit -> HwpAccessibilityUnit? in
            guard let label = accessibilityLabel(unit.attributedString.string) else { return nil }
            return HwpAccessibilityUnit(
                kind: .body,
                label: label,
                rect: unit.rect,
                isHeading: isHeading(label: label, titles: headingTitles)
            )
        }
        return headerChrome + body + footerChrome
    }

    /// 메모 패널의 접근성 요소 (패널 로컬 top-down). 패널 모델은 paint list 만
    /// 보유하므로 `.drawText` 명령을 전개한다 — rect 높이는 렌더와 같은
    /// `HwpDrawnTextLayout` 으로 계산해 화면 줄 상자와 일치한다.
    public static func memoPanelUnits(panel: HwpMemoPanel) -> [HwpAccessibilityUnit] {
        var units: [HwpAccessibilityUnit] = []
        for command in panel.paintList.commands {
            guard case let .drawText(attributed, origin, lineWidth) = command,
                  let label = accessibilityLabel(attributed.string)
            else { continue }
            let lines = HwpDrawnTextLayout.lines(
                attributedString: attributed,
                origin: origin,
                lineWidth: max(lineWidth, 1)
            )
            let union = lines.reduce(CGRect.null) { $0.union($1.selectionRect) }
            // 조판이 줄을 내지 못한 텍스트도 라벨은 버리지 않는다 — 요소가
            // 사라지는 것보다 최소 rect 로 남는 쪽이 낫다.
            let rect = union.isNull
                ? CGRect(origin: origin, size: CGSize(width: max(lineWidth, 1), height: 1))
                : union
            units.append(HwpAccessibilityUnit(kind: .memo, label: label, rect: rect))
        }
        return units
    }

    /// 낭독 라벨 — U+FFFC 개체 마커를 지우고, 남는 것이 공백뿐이면 nil
    /// (읽을 것이 없는 요소는 VoiceOver 탐색만 늘린다).
    static func accessibilityLabel(_ text: String) -> String? {
        let stripped = HwpSelectionGeometry.strippingControlMarkers(text)
        guard stripped.contains(where: { !$0.isWhitespace }) else { return nil }
        return stripped
    }

    /// 개요 제목 판정 — 라벨을 제목 수집과 같은 정규화에 통과시킨 뒤 세 갈래로
    /// 대조한다:
    ///
    /// 1. **동등** — 안 잘린 제목은 문단 평문 전체라 온전한 제목 문단과 일치한다.
    ///    무조건 접두 대조를 쓰면 같은 쪽에서 접두가 겹치는 일반 문단("요약하면
    ///    다음과 같다" vs 제목 "요약")이 전부 헤딩으로 오탐된다.
    /// 2. **잘린 제목의 접두** — 200자 상한 (`titleCharacterLimit`) 에 닿은
    ///    제목만 문단 평문의 접두일 수 있다.
    /// 3. **분할 제목의 첫 조각** — 쪽/단 경계로 쪼개진 제목 문단은 첫 조각
    ///    라벨이 제목보다 짧은 접두다 (역방향 대조). 뒤 조각은 접두가 아니라
    ///    표시되지 않는다 — 로터 정지점은 첫 조각 하나면 된다. 남는 근사는
    ///    "제목의 접두와 정확히 일치하는 더 짧은 본문 문단"의 오탐뿐이다.
    static func isHeading(label: String, titles: [String]) -> Bool {
        guard !titles.isEmpty else { return false }
        let collapsed = collapsedForTitleMatch(label)
        guard !collapsed.isEmpty else { return false }
        return titles.contains { title in
            guard !title.isEmpty else { return false }
            if collapsed == title {
                return true
            }
            if title.count == HwpOutlineItem.titleCharacterLimit, collapsed.hasPrefix(title) {
                return true
            }
            return collapsed.count < title.count && title.hasPrefix(collapsed)
        }
    }

    /// 제목 수집 (`HwpOutlineCollector.titleUnits` + `collapsedWhitespace`) 과
    /// 같은 정규화. 조판 문자열은 묶음 빈칸 (30)·고정폭 빈칸 (31) 을 원문
    /// 코드로 담는데 이 둘은 유니코드 공백이 아니라 `isWhitespace` 접힘에
    /// 걸리지 않는다 — 수집처럼 공백으로 매핑하고, 수집이 버리는 그 밖의
    /// 컨트롤 코드 (<32, 비공백) 는 지운 뒤 공백을 접는다.
    static func collapsedForTitleMatch(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value == 30 || scalar.value == 31 {
                scalars.append(" ")
            } else if scalar.value < 32, !Character(scalar).isWhitespace {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 크롬 그룹 안 낭독 순서 — 위에서 아래, 같은 줄이면 왼쪽에서 오른쪽.
    private static func isInReadingOrder(
        _ lhs: HwpAccessibilityUnit, _ rhs: HwpAccessibilityUnit
    ) -> Bool {
        lhs.rect.minY != rhs.rect.minY
            ? lhs.rect.minY < rhs.rect.minY
            : lhs.rect.minX < rhs.rect.minX
    }
}
