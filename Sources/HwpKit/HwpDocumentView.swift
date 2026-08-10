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
    private let currentPage: Binding<Int>?
    private let searchController: HwpSearchController?
    private let onHyperlinkTapped: ((String) -> Void)?
    private let onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?

    public init(
        document: HwpDocument,
        zoomScale: Binding<CGFloat>? = nil,
        currentPage: Binding<Int>? = nil,
        searchController: HwpSearchController? = nil,
        onHyperlinkTapped: ((String) -> Void)? = nil,
        onUnsupportedElement: ((HwpUnsupportedElement) -> Void)? = nil
    ) {
        self.document = document
        self.zoomScale = zoomScale
        self.currentPage = currentPage
        self.searchController = searchController
        self.onHyperlinkTapped = onHyperlinkTapped
        self.onUnsupportedElement = onUnsupportedElement
    }

    public var body: some View {
        #if os(macOS)
            NSViewWrapper(
                document: document,
                zoomScale: zoomScale,
                currentPage: currentPage,
                searchController: searchController,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        #elseif os(iOS)
            UIViewWrapper(
                document: document,
                zoomScale: zoomScale,
                currentPage: currentPage,
                searchController: searchController,
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
        let currentPage: Binding<Int>?
        let searchController: HwpSearchController?
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
            }
            normalizeOutOfRangePageBinding(coordinator: context.coordinator)
            normalizeOutOfRangeZoomBinding(
                coordinator: context.coordinator, clampedScale: view.zoomScale
            )
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
    }
#endif

#if os(iOS)
    private struct UIViewWrapper: UIViewRepresentable {
        let document: HwpDocument
        let zoomScale: Binding<CGFloat>?
        let currentPage: Binding<Int>?
        let searchController: HwpSearchController?
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
            }
            normalizeOutOfRangePageBinding(coordinator: context.coordinator)
            normalizeOutOfRangeZoomBinding(
                coordinator: context.coordinator, clampedScale: view.zoomScale
            )
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
    }
#endif
