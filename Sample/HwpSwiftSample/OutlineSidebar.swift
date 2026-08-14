import HwpKitCore
import SwiftUI

/// 개요·책갈피 사이드바 (#77) — **호스트가 만드는 UI의 예시**다.
///
/// `HwpKit`은 목록 UI를 내지 않는다 (`Sources/HwpKit/AGENTS.md`의 "v1 스코프
/// 밖" — 검색 결과 목록과 같은 기준: `List` 행 레이아웃·선택 강조·접근성·
/// 플랫폼 chrome 분기가 붙어 현행 `Tools/`의 순수 `HStack` 관례를 넘는다).
/// 대신 `HwpDocumentMetadata.outline`이 `Identifiable` + 1-기반 쪽 번호 +
/// 수준까지 채워 오므로, 이 파일이 그 재료만으로 사이드바가 만들어짐을 보인다.
struct OutlineSidebar: View {
    let outline: [HwpOutlineItem]
    @Binding var currentPage: Int
    /// 항목을 눌러 이동한 **뒤** 호스트가 할 일 (iPhone 시트 닫기 등).
    var onSelect: (() -> Void)?

    /// 수준 한 단계당 들여쓰기.
    private static let indentPerLevel: CGFloat = 12

    var body: some View {
        // 갈래 나누기와 현재 위치 판정은 **한 번만** 한다 — 행마다 다시 접으면
        // 1,944개짜리 목록에서 O(n²)가 된다 (헌법주석).
        let headings = outline.headings
        let bookmarks = outline.bookmarks
        // 강조 대상은 지금 보고 있는 쪽을 **여는** 개요 — 현재 쪽 이하의 마지막
        // 개요다. 제목이 없는 쪽에서도 자기 자리를 알려 주므로
        // `pageNumber == currentPage`로만 강조하는 것보다 목차답게 읽힌다.
        let current = headings.last { $0.pageNumber <= currentPage }
        return List {
            if !headings.isEmpty {
                Section("개요") {
                    ForEach(headings) { item in
                        row(item, isCurrent: item == current)
                    }
                }
            }
            if !bookmarks.isEmpty {
                Section("책갈피") {
                    ForEach(bookmarks) { item in
                        row(item, isCurrent: false)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
    }

    private func row(_ item: HwpOutlineItem, isCurrent: Bool) -> some View {
        Button {
            currentPage = item.pageNumber
            onSelect?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if item.kind == .bookmark {
                    Image(systemName: "bookmark")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .font(font(for: item))
                Spacer(minLength: 8)
                Text("\(item.pageNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 개요 수준은 1-기반이라 첫 수준의 들여쓰기가 0이다.
            .padding(.leading, CGFloat((item.level ?? 1) - 1) * Self.indentPerLevel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHint("\(item.pageNumber)쪽으로 이동")
    }

    private func font(for item: HwpOutlineItem) -> Font {
        switch item.level ?? 3 {
        case 1: .body.weight(.semibold)
        case 2: .body
        default: .callout
        }
    }

    private func accessibilityLabel(for item: HwpOutlineItem) -> String {
        guard item.kind == .heading, let level = item.level else {
            return "책갈피 \(item.title)"
        }
        return "\(level)수준 개요 \(item.title)"
    }
}
