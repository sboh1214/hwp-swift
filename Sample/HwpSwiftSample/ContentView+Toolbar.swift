import HwpKit
import HwpKitCore
import SwiftUI

/// 툴바 행 (#74·#76·#77·#78·#120) — `HwpDocumentToolbar` 하나에 이 앱이 넣는
/// 컨트롤 전부다.
///
/// 독립 View로 뽑지 않고 `ContentView`의 extension으로 나눈 이유 (#140):
/// 툴바가 만지는 호스트 상태가 여덟 가지(`showPicker`·사이드바 두 값·
/// `currentPage`·`loadProgress`·`exportProgress`·`zoomScale`·`fitZoom`)에
/// `@FocusState`와 플랫폼 조건부 인쇄 앵커까지 더해져, 자식 뷰로 만들면
/// 인자 열셋짜리 이니셜라이저가 생긴다. 그중 `@FocusState`는 **아래로만**
/// 넘길 수 있고(형제로 갈라지면 Cmd+F가 조용히 죽는다) 인쇄 앵커는
/// `#if !os(macOS)`라 시그니처 자체가 플랫폼마다 갈린다. extension은 소유권도
/// 뷰 identity도 건드리지 않으므로 그 위험이 통째로 없다.
extension ContentView {
    func toolbar(document: HwpDocument) -> some View {
        HwpDocumentToolbar {
            Button {
                showPicker = true
            } label: {
                toolbarLabel("Re-open", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            // 목록이 비어 있으면 누를 것이 없으므로 버튼 자체를 내지 않는다.
            // 축소판 버튼에는 그런 조건이 없다 — 쪽은 언제나 있다.
            if !document.metadata.outline.isEmpty {
                sidebarButton(.outline, document: document)
                    .help("개요·책갈피 \(document.metadata.outline.count)개")
            }
            sidebarButton(.thumbnails, document: document)
                .help("쪽 축소판 \(document.pages.count)개")

            Divider().frame(height: 20)

            HwpPageNavigator(
                currentPage: $currentPage,
                totalPages: max(document.pages.count, 1)
            )

            if let loadProgress {
                ProgressView(value: loadProgress)
                    .frame(width: 120)
                    .help("페이지 배치 중… \(Int(loadProgress * 100))%")
            }

            Divider().frame(height: 20)

            // 배치가 끝나기 전 문서는 페이지가 모자란 채로 내보내진다
            Button {
                exportPDF(document: document, then: .save)
            } label: {
                toolbarLabel("PDF로 내보내기", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .disabled(loadProgress != nil || exportProgress != nil)

            Button {
                exportPDF(document: document, then: .print)
            } label: {
                toolbarLabel("인쇄", systemImage: "printer")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(loadProgress != nil || exportProgress != nil)

            #if !os(macOS)
                // iPad 팝오버 앵커 — 이 자리에 있어야 인쇄를 누른 창에 뜬다.
                HwpPrintAnchor(box: printAnchor)
                    .frame(width: 1, height: 1)
            #endif

            // Cmd+F는 **호스트가** 소유한다 — 라이브러리(`HwpSearchBar`)는
            // 전역 단축키를 선점하지 않고 포커스 훅만 받는다. Cmd+O·Cmd+P와
            // 같은 관례다. 툴바가 `loadedView` 안에만 있으므로 이 단축키도
            // 문서가 열려 있는 동안에만 산다 (인쇄와 같은 성질).
            Button {
                searchFieldFocused = true
            } label: {
                toolbarLabel("찾기", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: [.command])

            Spacer()

            HwpZoomControls(zoomScale: $zoomScale, fitZoom: $fitZoom)
        }
    }

    /// 사이드바 모드 토글. 이미 그 모드가 보이는 중이면 눌러서 감춘다.
    ///
    /// 활성 표시는 **실제로 그려질** 축을 따른다: 개요가 없는 문서에서 `.outline`
    /// 선택이 축소판으로 대체되면 그 사실이 버튼에 보여야 한다. 그리고 그 버튼을
    /// 눌러 여닫아도 `sidebarMode`는 건드리지 않는다 — 대체된 축을 그대로 써
    /// 넣으면 한 번의 감췄다 열기로 사용자의 개요 선택이 조용히 사라진다.
    @ViewBuilder
    private func sidebarButton(_ mode: SidebarMode, document: HwpDocument) -> some View {
        let draws = sidebarMode.resolved(for: document) == mode
        let isActive = sidebarVisible && draws
        Button {
            if isActive {
                sidebarVisible = false
            } else if draws {
                sidebarVisible = true
            } else {
                sidebarMode = mode
                sidebarVisible = true
            }
        } label: {
            toolbarLabel(mode.title, systemImage: mode.systemImage)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? Color.accentColor : nil)
    }

    /// 좁은 화면(iPhone)에서는 아이콘만 쓴다 — 툴바는 그냥 `HStack`이라 한 줄에
    /// 안 들어가면 SwiftUI가 **글자 단위로** 줄바꿈해 버튼이 세로로 늘어난다
    /// (시뮬레이터 실측). macOS는 폭이 남으므로 글자를 그대로 보인다.
    @ViewBuilder
    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        #if os(macOS)
            Text(title)
        #else
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        #endif
    }
}
