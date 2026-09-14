import HwpKit
import HwpKitCore
import SwiftUI

/// 사이드바가 보이는 내용. `Identifiable`인 것은 iOS `.sheet(item:)`이
/// 요구해서다 (표시 여부와 내용이 한 값이라 둘이 어긋날 수 없다).
enum SidebarMode: Identifiable {
    case outline
    case thumbnails

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .outline: "개요"
        case .thumbnails: "축소판"
        }
    }

    var systemImage: String {
        switch self {
        case .outline: "list.bullet.indent"
        case .thumbnails: "square.grid.2x2"
        }
    }

    /// 이 문서에서 **실제로 그려질 축** (표시 여부와 무관).
    ///
    /// 개요를 골랐는데 그 문서에 개요가 없으면 축소판으로 대신한다 — 개요가 없는
    /// 문서에서 사이드바가 통째로 사라지던 것이 이 축을 추가한 이유다 (#76).
    /// 대체는 **그리기에서만** 일어나고 `sidebarMode`를 덮어쓰지 않으므로, 개요가
    /// 있는 문서를 다음에 열면 다시 개요가 나온다.
    ///
    /// `isComplete`를 함께 보는 것이 중요하다. 개요는 프로그레시브라 1쪽에 제목이
    /// 없는 문서(표지·서식)는 **첫 스냅샷에서 빈 목록**으로 오는데, 그때 대체하면
    /// 축소판 그리드가 마운트돼 쪽을 그리기 시작했다가 다음 스냅샷에서 헐린다
    /// (그 작업은 세대 가드에 막혀 캐시되지도 않는다).
    func resolved(for document: HwpDocument) -> SidebarMode {
        guard self == .outline,
              document.metadata.isComplete,
              document.metadata.outline.isEmpty
        else { return self }
        return .thumbnails
    }
}

/// 고른 축을 그리는 사이드바 (#76·#77) — 갈래 하나가 전부다.
///
/// macOS는 인라인 열, iOS는 시트로 이 뷰를 낸다 (`ContentView`). 두 목록 뷰가
/// 공유하는 것은 여기까지다 — `OutlineSidebar`는 `List` 한 줄이면 되지만
/// `ThumbnailSidebar`는 `LazyVGrid` + 셀별 지연 요청·취소가 필요해 코드를
/// 나누지 않는다 (`ThumbnailSidebar`의 주석).
struct DocumentSidebar: View {
    let mode: SidebarMode
    let document: HwpDocument
    /// **1-기반**이다 (`HwpPageNavigator`·`OutlineSidebar`와 같은 규약).
    @Binding var currentPage: Int
    /// 축소판 렌더러는 **호스트가 소유한다** — 이 뷰가 만들면 축을 토글하거나
    /// iPhone 시트를 닫을 때마다 그때까지 그린 축소판을 통째로 버린다.
    let thumbnails: HwpPageThumbnails
    /// 항목을 눌러 이동한 **뒤** 호스트가 할 일 (iPhone 시트 닫기 등).
    var onSelect: (() -> Void)?

    var body: some View {
        switch mode {
        case .outline:
            OutlineSidebar(
                outline: document.metadata.outline,
                currentPage: $currentPage,
                onSelect: onSelect
            )
        case .thumbnails:
            ThumbnailSidebar(
                document: document,
                currentPage: $currentPage,
                thumbnails: thumbnails,
                onSelect: onSelect
            )
        }
    }
}
