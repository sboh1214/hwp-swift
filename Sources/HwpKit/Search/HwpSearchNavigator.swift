import HwpKitCore
import SwiftUI

/// 매치 카운터 + 이전/다음 버튼.
///
/// 검색어 입력은 자기 디자인으로 만들면서 탐색 UI만 빌려 쓰는 호스트를 위해
/// 따로 낸다. `HwpSearchBar`가 이것을 내부에서 **조립**한다 — 분해가 아니라
/// 재사용이라, `HwpPageNavigator`가 툴바 안에서 쓰이는 구조와 대칭이다.
///
/// `HwpPageNavigator`/`HwpZoomControls`와 같은 성질의 **순수 서브트리**다:
/// navigation 컨테이너를 요구하지 않고, 호스트의 창 툴바·내비게이션 바
/// chrome을 점유하지 않으며, 환경에 아무것도 심지 않고, 전역 단축키를
/// 소유하지 않는다.
public struct HwpSearchNavigator: View {
    private let controller: HwpSearchController

    /// - Parameter controller: `HwpDocumentView`에 넘긴 것과 **같은 인스턴스**.
    public init(controller: HwpSearchController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(counterText)
                .monospacedDigit()
            Button(LocalizedStringKey("‹"), action: goToPrevious)
                .disabled(isNavigationDisabled)
            Button(LocalizedStringKey("›"), action: goToNext)
                .disabled(isNavigationDisabled)
        }
    }

    // MARK: - body 밖 (이 계층의 테스트 접점)

    func goToNext() {
        controller.next()
    }

    func goToPrevious() {
        controller.previous()
    }

    var isNavigationDisabled: Bool {
        controller.matchCount == 0
    }

    /// 전부 `LocalizedStringKey`다 — `bundle:` 없이 쓰므로 호스트 번들에서
    /// 해석된다(`HwpZoomControls`와 같은 규약). 순수 `String` 보간을 쓰면 그
    /// 번역 창구가 조용히 막힌다.
    var counterText: LocalizedStringKey {
        let total = controller.matchCount
        let ordinal = hwpDisplayMatchNumber(
            currentIndex: controller.currentMatchIndex, matchCount: total
        )
        switch controller.phase {
        case .idle:
            return "Find"
        case .scanning where total == 0:
            return "Searching…"
        case .complete where total == 0:
            return "No results"
        // 상한에 걸렸으면 표시된 수가 전부가 아니라는 것을 "+"로 알린다
        case .truncated:
            return "\(ordinal) of \(total)+"
        case .scanning, .complete:
            return "\(ordinal) of \(total)"
        }
    }
}
