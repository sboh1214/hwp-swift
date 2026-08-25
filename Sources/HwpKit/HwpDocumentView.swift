import HwpKitCore
import HwpKitNative
import SwiftUI

/// 1-기반 public 페이지 바인딩을 0-기반 스크롤 index로 바꾼다. 클램프를
/// 뺄셈보다 먼저 해 Int.min 바인딩(상태 복원)의 오버플로 트랩을 막는다 —
/// macOS·iOS 분기가 공유해 산식이 갈라지지 않는다 (R57 #1).
func hwpScrollPageIndex(fromOneBased requestedPage: Int) -> Int {
    max(1, requestedPage) - 1
}

/// 줌 바인딩이 네이티브 값으로 writeback돼야 하는지 — 비-finite(NaN/±inf)는
/// 톨러런스 비교(NaN 비교는 전부 false)에 앞서 무조건 복구 대상이다 (R58 #1).
func hwpZoomNeedsWriteback(current: CGFloat, native: CGFloat) -> Bool {
    !current.isFinite || abs(current - native) > 0.001
}

/// 지연 작업 재개 시 "사용자가 바인딩을 안 바꿨다" 판정 — NaN은 자기 자신과
/// abs-비교가 불가하고 ±inf는 차가 NaN이라, 동일성·NaN 쌍을 먼저 본다 (R58 #1).
func hwpZoomBindingUnchanged(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    lhs == rhs || (lhs.isNaN && rhs.isNaN) || abs(lhs - rhs) < 0.001
}

public struct HwpDocumentView: View {
    private let document: HwpDocument
    private let zoomScale: Binding<CGFloat>?
    private let fitZoom: Binding<HwpZoomFit?>?
    private let currentPage: Binding<Int>?
    private let searchController: HwpSearchController?
    private let isKeyboardPageNavigationEnabled: Bool
    private let onHyperlinkTapped: ((String) -> Void)?
    private let onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?

    /// - Parameters:
    ///   - fitZoom: 배율을 뷰포트에 맞추는 **원샷 명령** (#78). 값을 넣으면
    ///     뷰가 한 번 적용하고 nil로 되돌린다. 지속 모드가 아니라 창을 리사이즈해도
    ///     다시 맞추지 않는다 — 그 사이 사용자가 핀치로 바꾼 배율을 덮지 않기 위해서다.
    ///     적용 결과 배율은 `zoomScale` 바인딩으로 되돌아온다.
    ///   - isKeyboardPageNavigationEnabled: PageUp/Down·Home/End 페이지 이동 (#120).
    ///     라이브러리는 전역 단축키를 소유하지 않으므로 문서 뷰가 first responder일
    ///     때만 반응한다 (클릭/탭으로 포커스가 잡힌다). 호스트가 이 키들을 직접
    ///     쓰려면 false로 끈다.
    public init(
        document: HwpDocument,
        zoomScale: Binding<CGFloat>? = nil,
        fitZoom: Binding<HwpZoomFit?>? = nil,
        currentPage: Binding<Int>? = nil,
        searchController: HwpSearchController? = nil,
        isKeyboardPageNavigationEnabled: Bool = true,
        onHyperlinkTapped: ((String) -> Void)? = nil,
        onUnsupportedElement: ((HwpUnsupportedElement) -> Void)? = nil
    ) {
        self.document = document
        self.zoomScale = zoomScale
        self.fitZoom = fitZoom
        self.currentPage = currentPage
        self.searchController = searchController
        self.isKeyboardPageNavigationEnabled = isKeyboardPageNavigationEnabled
        self.onHyperlinkTapped = onHyperlinkTapped
        self.onUnsupportedElement = onUnsupportedElement
    }

    public var body: some View {
        #if os(macOS)
            NSViewWrapper(
                document: document,
                zoomScale: zoomScale,
                fitZoom: fitZoom,
                currentPage: currentPage,
                searchController: searchController,
                isKeyboardPageNavigationEnabled: isKeyboardPageNavigationEnabled,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        #elseif os(iOS)
            UIViewWrapper(
                document: document,
                zoomScale: zoomScale,
                fitZoom: fitZoom,
                currentPage: currentPage,
                searchController: searchController,
                isKeyboardPageNavigationEnabled: isKeyboardPageNavigationEnabled,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        #endif
    }
}

/// Platform-neutral bridge between the native views' callbacks and SwiftUI
/// bindings — shared by the macOS and iOS representables.
final class HwpDocumentCoordinator {
    private var zoomScale: Binding<CGFloat>?
    private var currentPage: Binding<Int>?
    private var onHyperlinkTapped: ((String) -> Void)?
    private var onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
    private var isApplyingBinding = false
    /// 현재 적용된 문서 세대 — 지연 작업(클램프 등)이 예약 시점 문서가 아직
    /// 현재인지 대조한다. 래퍼 struct는 최신 문서를 볼 수 없어 클래스인
    /// coordinator가 보유한다 (#6). loadToken은 직접 구성 문서에서 nil이라
    /// 교체를 구분하지 못해 문서 동등성 기반 세대를 쓴다 (#4). 같은 문서로의
    /// 재등록은 멱등 — 정당한 pending 클램프를 폐기하지 않는다.
    private var lastDocument: HwpDocument?
    private(set) var activeDocumentGeneration: UInt64 = 0

    func registerDocument(_ document: HwpDocument) -> UInt64 {
        if lastDocument != document {
            lastDocument = document
            activeDocumentGeneration &+= 1
        }
        return activeDocumentGeneration
    }

    private var appliedFit: HwpZoomFit?
    private var appliedFitGeneration: UInt64 = 0

    /// 옛 문서를 향한 fit 명령을 교체본이 적용하지 못하게 거른다.
    ///
    /// 네이티브 뷰는 예약(`pendingFitZoom`)을 문서 교체에서 버리지만, 래퍼가 같은
    /// 명령을 새 문서용으로 다시 건네면 그 가드는 우회된다 — 세대 비교가 명령을
    /// **지우는** 쪽에만 있고 **적용하는** 쪽에 없었다 (실측: 소비 Task 가 돌기
    /// 전에 문서가 바뀌면 A 의 `.page` 가 B 에 적용돼 배율이 B 의 쪽 맞춤 0.3 으로
    /// 가고 스크롤도 B 의 쪽 머리로 간다).
    ///
    /// 명령이 nil 로 돌아온 것을 관측하면 기록을 지운다 — 그래야 호스트가 같은 값을
    /// 새로 넣은 경우와 옛 명령이 남은 경우가 갈린다. `HwpZoomFit?` 에는 신원이
    /// 없어 **같은 값이 nil 을 거치지 않고 세대를 넘는** 경우는 여전히 구분할 수
    /// 없고, 그때는 적용하지 않는 쪽을 고른다: 옛 문서에 걸린 명령이 새 문서에
    /// 적용되는 것은 확인된 결함이고, 반대 방향의 대가는 버튼을 다시 누르는 것뿐이다.
    func fitToApply(_ command: HwpZoomFit?) -> HwpZoomFit? {
        guard let command else {
            appliedFit = nil
            return nil
        }
        if appliedFit == command, appliedFitGeneration != activeDocumentGeneration {
            return nil
        }
        appliedFit = command
        appliedFitGeneration = activeDocumentGeneration
        return command
    }

    init(
        zoomScale: Binding<CGFloat>?,
        currentPage: Binding<Int>?,
        onHyperlinkTapped: ((String) -> Void)?,
        onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
    ) {
        self.zoomScale = zoomScale
        self.currentPage = currentPage
        self.onHyperlinkTapped = onHyperlinkTapped
        self.onUnsupportedElement = onUnsupportedElement
    }

    func update(
        zoomScale: Binding<CGFloat>?,
        currentPage: Binding<Int>?,
        onHyperlinkTapped: ((String) -> Void)?,
        onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
    ) {
        self.zoomScale = zoomScale
        self.currentPage = currentPage
        self.onHyperlinkTapped = onHyperlinkTapped
        self.onUnsupportedElement = onUnsupportedElement
    }

    func handleHyperlinkTapped(_ url: String) {
        onHyperlinkTapped?(url)
    }

    func handleUnsupportedElement(_ element: HwpUnsupportedElement) {
        onUnsupportedElement?(element)
    }

    func handlePageChanged(_ page: Int) {
        // 문서 대입·프로그래매틱 스크롤의 echo(applyingBinding 구간)는 무시하고
        // 실제 스크롤만 반영한다 — 첫 프로그레시브 스냅샷 이후의 페이지 요청이
        // echo로 덮어써져 유실되지 않게 한다 (P2). 동치 가드는 중복 write 방지.
        guard !isApplyingBinding else { return }
        guard let currentPage, currentPage.wrappedValue != page + 1 else { return }
        currentPage.wrappedValue = page + 1
    }

    /// 바인딩 적용(문서 대입·줌·스크롤) 구간 동안 onPageChanged writeback을
    /// 억제해, 프로그래매틱 변경의 echo가 바인딩을 덮어쓰지 않게 한다 (P2).
    func applyingBinding(_ body: () -> Void) {
        isApplyingBinding = true
        defer { isApplyingBinding = false }
        body()
    }

    func handleZoomChanged(_ scale: CGFloat) {
        // 핀치 줌을 바인딩에 반영해 툴바 배율 라벨을 동기화한다.
        // 바인딩 적용 구간의 동기 echo(범위 밖 값의 네이티브 클램프 재보고)는
        // update 중 상태 쓰기라 억제한다 — 클램프 정규화는
        // normalizeOutOfRangeZoomBinding이 업데이트 밖에서 수행한다 (R38 #3).
        guard !isApplyingBinding else { return }
        guard let zoomScale, hwpZoomNeedsWriteback(current: zoomScale.wrappedValue, native: scale)
        else { return }
        zoomScale.wrappedValue = scale
    }
}

#if os(macOS)
    private struct NSViewWrapper: NSViewRepresentable {
        let document: HwpDocument
        let zoomScale: Binding<CGFloat>?
        let fitZoom: Binding<HwpZoomFit?>?
        let currentPage: Binding<Int>?
        let searchController: HwpSearchController?
        let isKeyboardPageNavigationEnabled: Bool
        let onHyperlinkTapped: ((String) -> Void)?
        let onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?

        func makeNSView(context: Context) -> HwpDocumentNSView {
            let view = HwpDocumentNSView()
            configure(view, context: context)
            return view
        }

        func updateNSView(_ nsView: HwpDocumentNSView, context: Context) {
            context.coordinator.update(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
            configure(nsView, context: context)
        }

        func makeCoordinator() -> HwpDocumentCoordinator {
            HwpDocumentCoordinator(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        }

        /// 검색 세션은 호스트가 소유하고 뷰보다 오래 산다 — 뷰가 사라질 때
        /// 떼지 않으면 그 컨트롤러가 이 뷰의 선택 컨트롤러를, 그것이 다시
        /// 문서 전체(페이지·페인트 리스트·단위 캐시)를 붙든다. 문서를 닫거나
        /// 재로드가 실패해 새 뷰가 붙지 않으면 그대로 남는다.
        static func dismantleNSView(
            _ nsView: HwpDocumentNSView, coordinator _: HwpDocumentCoordinator
        ) {
            nsView.searchController = nil
        }

        private func configure(_ view: HwpDocumentNSView, context: Context) {
            // Callbacks must be wired before the document assignment so the
            // document didSet notifications reach the coordinator.
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
            view.onZoomChanged = context.coordinator.handleZoomChanged(_:)
            // 동일성 가드가 **필수**다. 클래스 옵셔널 var의 didSet은 대입할
            // 때마다 발화하는데, 그 안에서 재배선 → 재스캔 → 관찰자 통지 →
            // 호스트 body 무효화 → 다시 이 configure … 자기 급전 루프가
            // 타이핑 없이도 돈다. 문서 대입의 중복-대입 스킵과 같은 성격이다.
            if view.searchController !== searchController {
                view.searchController = searchController
            }
            // 값 타입 대입이라 didSet 재배선이 없어 동일성 가드가 필요 없다 (#120).
            view.isKeyboardPageNavigationEnabled = isKeyboardPageNavigationEnabled
            _ = context.coordinator.registerDocument(document)
            // 문서 대입·줌·스크롤의 onPageChanged echo가 currentPage 바인딩을
            // 덮어쓰지 않게 이 구간 동안 writeback을 억제한다 — 첫 프로그레시브
            // 스냅샷 이후의 페이지 요청이 유실되지 않고 로드되면 도달한다 (P2).
            context.coordinator.applyingBinding {
                let requestedPage = currentPage?.wrappedValue
                // loadToken이 있으면 구조 동등성으로 스킵, 없으면(직접 구성) 구조가
                // 같아도 색/폰트만 다른 render-only 변경일 수 있어 전달한다 — 네이티브
                // didSet이 스크롤을 유지한 채 재렌더한다 (#6).
                if document.metadata.loadToken == nil || view.document != document {
                    view.document = document
                }
                if let zoomScale, zoomScale.wrappedValue.isFinite,
                   view.zoomScale != zoomScale.wrappedValue
                {
                    view.zoomScale = zoomScale.wrappedValue
                }
                if currentPage != nil, let requestedPage {
                    let pageIndex = hwpScrollPageIndex(fromOneBased: requestedPage)
                    if view.currentVisiblePage() != pageIndex {
                        view.scrollToPage(at: pageIndex)
                    }
                }
                // 페이지 요청을 처리한 **뒤**라야 쪽 맞춤이 그 페이지를 기준으로
                // 삼는다. 배율 대입 다음인 것도 같은 이유다 — 명시 배율과 fit이
                // 같은 갱신에 오면 나중에 온 뜻인 fit이 이긴다 (#78).
                if let fit = context.coordinator.fitToApply(fitZoom?.wrappedValue) {
                    view.applyFitZoom(fit)
                }
            }
            normalizeOutOfRangePageBinding(coordinator: context.coordinator)
            normalizeOutOfRangeZoomBinding(
                coordinator: context.coordinator, clampedScale: view.zoomScale
            )
            consumeFitZoomCommand(coordinator: context.coordinator)
        }

        /// 최종 문서(isComplete)에 없는 페이지 요청은 실제 클램프 값으로 바인딩을
        /// 되돌린다 — 억제된 echo 탓에 무효 바인딩이 남아 매 업데이트 같은 요청을
        /// 재시도하지 않게 한다. 프로그레시브 중간 스냅샷은 "아직 로드 전"이므로
        /// 건드리지 않는다 (P2, 요청 유실 방지와의 경계).
        private func normalizeOutOfRangePageBinding(coordinator: HwpDocumentCoordinator) {
            guard let currentPage, document.metadata.isComplete else { return }
            let requested = currentPage.wrappedValue
            let clamped = min(max(1, requested), max(1, document.pages.count))
            guard clamped != requested else { return }
            let generation = coordinator.registerDocument(document)
            // updateNSView/updateUIView 동기 경로에서 상태를 쓰면 SwiftUI의
            // state-during-update 위반 — 업데이트 밖에서 반영한다 (P2). 재개 시
            // 사용자가 바인딩을 바꿨거나(값 불일치) 다른 문서가 적용됐으면
            // (세대 불일치 — nil 토큰 문서 교체 포함, 새 문서가 그 페이지를
            // 지원할 수 있음) 폐기한다 (#6, #4).
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      currentPage.wrappedValue == requested
                else { return }
                currentPage.wrappedValue = clamped
            }
        }

        /// 네이티브 범위 밖 줌 바인딩은 실제 클램프 값으로 되돌린다 — 동기
        /// echo는 applyingBinding 가드가 억제하므로, 업데이트 밖에서 반영하지
        /// 않으면 무효 바인딩이 남아 매 업데이트 재클램프한다. 재개 시 값·문서
        /// 세대가 바뀌었으면 폐기한다 (R38 #3, 페이지 정규화와 동일 계약).
        private func normalizeOutOfRangeZoomBinding(
            coordinator: HwpDocumentCoordinator, clampedScale: CGFloat
        ) {
            guard let zoomScale else { return }
            let requested = zoomScale.wrappedValue
            guard hwpZoomNeedsWriteback(current: requested, native: clampedScale) else { return }
            let generation = coordinator.registerDocument(document)
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      hwpZoomBindingUnchanged(zoomScale.wrappedValue, requested)
                else { return }
                zoomScale.wrappedValue = clampedScale
            }
        }

        /// 원샷 fit 명령을 소비한다 — 적용은 위 동기 경로가 이미 했고 여기서는
        /// 바인딩만 idle(nil)로 되돌린다. 업데이트 중 상태 쓰기는 SwiftUI 위반이라
        /// 밖에서 하고, 재개 시 사용자가 다른 fit을 넣었거나 다른 문서가 적용됐으면
        /// 폐기한다 (페이지·줌 정규화와 동일 계약).
        ///
        /// **되돌리기와 재적용의 경주는 열리지 않는다.** 이 Task 는 위 두 정규화와
        /// 같은 동기 `configure` 에서 메인 액터 큐에 실리고, 바인딩 쓰기가 부르는
        /// 재렌더는 그 드레인 **뒤**의 갱신 패스라 그때 명령은 이미 nil 이다
        /// (실측: 배율 라이트백 Task → 이 Task 순으로 같은 턴에 돈다). 그래도
        /// 순서에 기대는 코드가 아니라는 점은 적어 둘 값이 있다 — 만약 되돌리기
        /// 전에 `configure` 가 한 번 더 돌면 `.width` 는 같은 배율이라 무해하지만
        /// `.page` 는 스크롤을 다시 쪽 머리로 당긴다.
        private func consumeFitZoomCommand(coordinator: HwpDocumentCoordinator) {
            guard let fitZoom, let requested = fitZoom.wrappedValue else { return }
            let generation = coordinator.registerDocument(document)
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      fitZoom.wrappedValue == requested
                else { return }
                fitZoom.wrappedValue = nil
            }
        }
    }
#endif

#if os(iOS)
    private struct UIViewWrapper: UIViewRepresentable {
        let document: HwpDocument
        let zoomScale: Binding<CGFloat>?
        let fitZoom: Binding<HwpZoomFit?>?
        let currentPage: Binding<Int>?
        let searchController: HwpSearchController?
        let isKeyboardPageNavigationEnabled: Bool
        let onHyperlinkTapped: ((String) -> Void)?
        let onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?

        func makeUIView(context: Context) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(frame: .zero)
            configure(view, context: context)
            return view
        }

        func updateUIView(_ uiView: HwpDocumentUIView, context: Context) {
            context.coordinator.update(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
            configure(uiView, context: context)
        }

        func makeCoordinator() -> HwpDocumentCoordinator {
            HwpDocumentCoordinator(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        }

        /// macOS와 같은 이유 — 호스트가 붙든 검색 세션이 뷰보다 오래 살아
        /// 문서 전체를 붙드는 것을 막는다.
        static func dismantleUIView(
            _ uiView: HwpDocumentUIView, coordinator _: HwpDocumentCoordinator
        ) {
            uiView.searchController = nil
        }

        private func configure(_ view: HwpDocumentUIView, context: Context) {
            // Callbacks must be wired before the document assignment so the
            // document didSet notifications reach the coordinator.
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
            view.onZoomChanged = context.coordinator.handleZoomChanged(_:)
            // 동일성 가드가 **필수**다. 클래스 옵셔널 var의 didSet은 대입할
            // 때마다 발화하는데, 그 안에서 재배선 → 재스캔 → 관찰자 통지 →
            // 호스트 body 무효화 → 다시 이 configure … 자기 급전 루프가
            // 타이핑 없이도 돈다. 문서 대입의 중복-대입 스킵과 같은 성격이다.
            if view.searchController !== searchController {
                view.searchController = searchController
            }
            // 값 타입 대입이라 didSet 재배선이 없어 동일성 가드가 필요 없다 (#120).
            view.isKeyboardPageNavigationEnabled = isKeyboardPageNavigationEnabled
            _ = context.coordinator.registerDocument(document)
            // 문서 대입·줌·스크롤의 onPageChanged echo가 currentPage 바인딩을
            // 덮어쓰지 않게 이 구간 동안 writeback을 억제한다 — 첫 프로그레시브
            // 스냅샷 이후의 페이지 요청이 유실되지 않고 로드되면 도달한다 (P2).
            context.coordinator.applyingBinding {
                let requestedPage = currentPage?.wrappedValue
                // loadToken이 있으면 구조 동등성으로 스킵, 없으면(직접 구성) 구조가
                // 같아도 색/폰트만 다른 render-only 변경일 수 있어 전달한다 — 네이티브
                // didSet이 스크롤을 유지한 채 재렌더한다 (#6).
                if document.metadata.loadToken == nil || view.document != document {
                    view.document = document
                }
                if let zoomScale, zoomScale.wrappedValue.isFinite,
                   view.zoomScale != zoomScale.wrappedValue
                {
                    view.zoomScale = zoomScale.wrappedValue
                }
                if currentPage != nil, let requestedPage {
                    let pageIndex = hwpScrollPageIndex(fromOneBased: requestedPage)
                    if view.currentVisiblePage() != pageIndex {
                        view.scrollToPage(at: pageIndex)
                    }
                }
                // 페이지 요청을 처리한 **뒤**라야 쪽 맞춤이 그 페이지를 기준으로
                // 삼는다. 배율 대입 다음인 것도 같은 이유다 — 명시 배율과 fit이
                // 같은 갱신에 오면 나중에 온 뜻인 fit이 이긴다 (#78).
                if let fit = context.coordinator.fitToApply(fitZoom?.wrappedValue) {
                    view.applyFitZoom(fit)
                }
            }
            normalizeOutOfRangePageBinding(coordinator: context.coordinator)
            normalizeOutOfRangeZoomBinding(
                coordinator: context.coordinator, clampedScale: view.zoomScale
            )
            consumeFitZoomCommand(coordinator: context.coordinator)
        }

        /// 최종 문서(isComplete)에 없는 페이지 요청은 실제 클램프 값으로 바인딩을
        /// 되돌린다 — 억제된 echo 탓에 무효 바인딩이 남아 매 업데이트 같은 요청을
        /// 재시도하지 않게 한다. 프로그레시브 중간 스냅샷은 "아직 로드 전"이므로
        /// 건드리지 않는다 (P2, 요청 유실 방지와의 경계).
        private func normalizeOutOfRangePageBinding(coordinator: HwpDocumentCoordinator) {
            guard let currentPage, document.metadata.isComplete else { return }
            let requested = currentPage.wrappedValue
            let clamped = min(max(1, requested), max(1, document.pages.count))
            guard clamped != requested else { return }
            let generation = coordinator.registerDocument(document)
            // updateNSView/updateUIView 동기 경로에서 상태를 쓰면 SwiftUI의
            // state-during-update 위반 — 업데이트 밖에서 반영한다 (P2). 재개 시
            // 사용자가 바인딩을 바꿨거나(값 불일치) 다른 문서가 적용됐으면
            // (세대 불일치 — nil 토큰 문서 교체 포함, 새 문서가 그 페이지를
            // 지원할 수 있음) 폐기한다 (#6, #4).
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      currentPage.wrappedValue == requested
                else { return }
                currentPage.wrappedValue = clamped
            }
        }

        /// 네이티브 범위 밖 줌 바인딩은 실제 클램프 값으로 되돌린다 — 동기
        /// echo는 applyingBinding 가드가 억제하므로, 업데이트 밖에서 반영하지
        /// 않으면 무효 바인딩이 남아 매 업데이트 재클램프한다. 재개 시 값·문서
        /// 세대가 바뀌었으면 폐기한다 (R38 #3, 페이지 정규화와 동일 계약).
        private func normalizeOutOfRangeZoomBinding(
            coordinator: HwpDocumentCoordinator, clampedScale: CGFloat
        ) {
            guard let zoomScale else { return }
            let requested = zoomScale.wrappedValue
            guard hwpZoomNeedsWriteback(current: requested, native: clampedScale) else { return }
            let generation = coordinator.registerDocument(document)
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      hwpZoomBindingUnchanged(zoomScale.wrappedValue, requested)
                else { return }
                zoomScale.wrappedValue = clampedScale
            }
        }

        /// 원샷 fit 명령을 소비한다 — 적용은 위 동기 경로가 이미 했고 여기서는
        /// 바인딩만 idle(nil)로 되돌린다. 업데이트 중 상태 쓰기는 SwiftUI 위반이라
        /// 밖에서 하고, 재개 시 사용자가 다른 fit을 넣었거나 다른 문서가 적용됐으면
        /// 폐기한다 (페이지·줌 정규화와 동일 계약).
        ///
        /// **되돌리기와 재적용의 경주는 열리지 않는다.** 이 Task 는 위 두 정규화와
        /// 같은 동기 `configure` 에서 메인 액터 큐에 실리고, 바인딩 쓰기가 부르는
        /// 재렌더는 그 드레인 **뒤**의 갱신 패스라 그때 명령은 이미 nil 이다
        /// (실측: 배율 라이트백 Task → 이 Task 순으로 같은 턴에 돈다). 그래도
        /// 순서에 기대는 코드가 아니라는 점은 적어 둘 값이 있다 — 만약 되돌리기
        /// 전에 `configure` 가 한 번 더 돌면 `.width` 는 같은 배율이라 무해하지만
        /// `.page` 는 스크롤을 다시 쪽 머리로 당긴다.
        private func consumeFitZoomCommand(coordinator: HwpDocumentCoordinator) {
            guard let fitZoom, let requested = fitZoom.wrappedValue else { return }
            let generation = coordinator.registerDocument(document)
            Task { @MainActor in
                guard coordinator.activeDocumentGeneration == generation,
                      fitZoom.wrappedValue == requested
                else { return }
                fitZoom.wrappedValue = nil
            }
        }
    }
#endif
