import HwpKitCore
import SwiftUI

/// 문서 내 검색 UI — 검색 필드 + 매치 카운터 + 이전/다음 + 지우기.
///
/// **호스트 chrome을 점유하지 않는다.** `HwpPageNavigator`/`HwpZoomControls`와
/// 같은 성질의 순수 서브트리다: navigation 컨테이너를 요구하지 않고, 창
/// 툴바·내비게이션 바 슬롯을 차지하지 않으며, 환경에 아무것도 심지 않고,
/// 전역 단축키를 소유하지 않는다. SwiftUI `.searchable`은 정확히 그 반대라
/// (가장 가까운 navigation 컨테이너의 chrome에 필드를 **설치**하고
/// `\.isSearching`을 환경에 심는다) 쓰지 않는다 — 그 modifier가 스코프
/// 가드의 금지 토큰에 남아 있는 이유가 이것이다.
///
/// **`@State`를 하나도 두지 않는다.** 파사드의 다른 컴포넌트도 그렇고, 그래야
/// `HwpToolsTests` 관례(뷰 인스턴스를 만들어 body 밖 메서드를 직접 부르는
/// 방식)로 검증된다. 질의는 컨트롤러가 소유하고 포커스는 호스트가 준다.
///
/// ```swift
/// @State private var search = HwpSearchController()
/// @FocusState private var findFocused: Bool
///
/// HwpSearchBar(controller: search, isFocused: $findFocused)
/// HwpDocumentView(document: document, searchController: search)
/// ```
public struct HwpSearchBar: View {
    private let controller: HwpSearchController
    private let isFocused: FocusState<Bool>.Binding?
    private let prompt: LocalizedStringKey
    private let fieldWidth: CGFloat?
    private let showsNavigator: Bool
    private let onDismiss: (() -> Void)?

    /// - Parameters:
    ///   - controller: `HwpDocumentView`에 넘긴 것과 **같은 인스턴스**.
    ///     옵셔널이 아니다 — 안전한 사용법이 기본값이어야 한다.
    ///   - isFocused: 호스트가 Cmd+F 등으로 포커스를 주기 위한 훅. 라이브러리는
    ///     전역 단축키를 소유하지 않으므로, 호스트가 `@FocusState`를 선언해
    ///     자기 `.keyboardShortcut`에서 켜 준다.
    ///   - fieldWidth: 텍스트 필드 고정 폭. **기본이 고정 폭인 이유**: 넘치는
    ///     툴바를 가로 `ScrollView`에 넣는 호스트가 흔한데, 가로 ScrollView는
    ///     자식에게 무한 폭을 제안해 greedy 필드가 레이아웃을 무너뜨린다.
    ///     nil이면 가용 폭을 채운다.
    ///   - showsNavigator: false면 카운터·이전/다음을 감춘다 (호스트가
    ///     `HwpSearchNavigator`를 다른 자리에 두는 경우).
    ///   - onDismiss: 닫기 버튼. nil이면 버튼을 그리지 않는다.
    public init(
        controller: HwpSearchController,
        isFocused: FocusState<Bool>.Binding? = nil,
        prompt: LocalizedStringKey = "Find in document",
        fieldWidth: CGFloat? = 220,
        showsNavigator: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.isFocused = isFocused
        self.prompt = prompt
        self.fieldWidth = fieldWidth
        self.showsNavigator = showsNavigator
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            field
            if showsNavigator {
                HwpSearchNavigator(controller: controller)
            }
            if !controller.query.text.isEmpty {
                Button(LocalizedStringKey("Clear"), action: clearQuery)
            }
            if onDismiss != nil {
                Button(LocalizedStringKey("Done"), action: dismiss)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let text = TextField(prompt, text: queryText)
            .textFieldStyle(.roundedBorder)
            .onSubmit(goToNext)
        Group {
            if let isFocused {
                text.focused(isFocused)
            } else {
                text
            }
        }
        .frame(width: fieldWidth)
    }

    // MARK: - body 밖 (이 계층의 테스트 접점)

    /// 컨트롤러가 질의의 단일 진실이다 — 뷰에 사본을 두면 `search(text:)`가
    /// 호스트 코드에서 불렸을 때 필드가 낡은 값을 계속 보여 준다.
    var queryText: Binding<String> {
        Binding(
            get: { controller.query.text },
            set: { controller.search(text: $0) }
        )
    }

    func setText(_ text: String) {
        controller.search(text: text)
    }

    func goToNext() {
        controller.next()
    }

    func goToPrevious() {
        controller.previous()
    }

    func clearQuery() {
        controller.clear()
    }

    func dismiss() {
        controller.clear()
        onDismiss?()
    }

    var isNavigationDisabled: Bool {
        controller.matchCount == 0
    }

    var statusText: LocalizedStringKey {
        HwpSearchNavigator(controller: controller).counterText
    }
}
