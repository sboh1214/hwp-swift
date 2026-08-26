import HwpKitCore
import SwiftUI

/// 미지원 요소 집계 배너 (#126) — **호스트가 만드는 UI의 예시**다.
///
/// 라이브러리는 `onUnsupportedElement` 콜백으로 요소를 낼 뿐 배너 UI는 앱
/// 몫이다 (`AGENTS.md`의 "배너 UI는 호스트 몫이다"). 집계 축은 `kind`가
/// 아니라 `hint`다 — 실제 방출 kind는 사실상 `.placeholder` 하나이고, hint가
/// "수식"·"차트" 같은 사용자에게 보일 수 있는 한국어 라벨을 이미 담고 있다.
struct UnsupportedElementsBanner: View {
    let elements: Set<HwpUnsupportedElement>
    /// 목록 버튼을 눌렀을 때 호스트가 할 일 (macOS 열 토글 / iOS 시트 표시).
    let onShowList: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(Self.summary(for: elements))
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("목록", action: onShowList)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    /// hint별 집계 요약 — "미지원 요소 5개 — 수식 3 · 차트 2" 꼴.
    /// 종류가 많으면 상위 3종만 보이고 나머지는 개수로 접는다 (배너는 한 줄이다).
    static func summary(for elements: Set<HwpUnsupportedElement>) -> String {
        let counts = Dictionary(grouping: elements, by: \.hint).mapValues(\.count)
        let ranked = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        let shown = ranked.prefix(3).map { "\($0.key) \($0.value)" }
        var text = "미지원 요소 \(elements.count)개 — \(shown.joined(separator: " · "))"
        if ranked.count > 3 {
            text += " 외 \(ranked.count - 3)종"
        }
        return text
    }
}

/// 미지원 요소 목록 (#126). 행을 누르면 그 요소가 있는 쪽으로 이동한다 —
/// 프로그래밍 방식 쪽 이동 전례(`OutlineSidebar`·`ThumbnailSidebar`)와 같은
/// `currentPage` 바인딩 통로를 쓴다.
///
/// `HwpUnsupportedElement`는 `Identifiable`이 아니고 `Hashable`이라 `ForEach`는
/// `id: \.self`를 쓴다. 입력이 `Set`인 것은 콜백이 델타가 아니라 배열 전체를
/// 매번 재방출하기 때문이다 — 호스트가 `Set`으로 받아 중복을 접는다.
struct UnsupportedElementsList: View {
    let elements: Set<HwpUnsupportedElement>
    /// 쪽 이동 클램프 상한. `unsupportedElements()`에는 `outline()`과 달리
    /// 쪽 상한 클램프가 없어 앱이 방어한다.
    let pageCount: Int
    @Binding var currentPage: Int
    /// 항목을 눌러 이동한 **뒤** 호스트가 할 일 (iPhone 시트 닫기 등).
    var onSelect: (() -> Void)?

    var body: some View {
        List {
            Section("미지원 요소 \(elements.count)개") {
                ForEach(sorted, id: \.self) { element in
                    row(element)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
    }

    /// 문서 순서(쪽 오름차순)로 보이되, 같은 쪽 안에서는 hint로 묶이게 한다 —
    /// `Set`은 순서가 없으므로 정렬이 없으면 갱신마다 목록이 뒤섞인다.
    private var sorted: [HwpUnsupportedElement] {
        elements.sorted { lhs, rhs in
            lhs.page != rhs.page ? lhs.page < rhs.page : lhs.hint < rhs.hint
        }
    }

    private func row(_ element: HwpUnsupportedElement) -> some View {
        Button {
            currentPage = min(max(1, element.page), max(pageCount, 1))
            onSelect?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(element.hint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(element.page)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("미지원 요소 \(element.hint)")
        .accessibilityHint("\(element.page)쪽으로 이동")
    }
}
