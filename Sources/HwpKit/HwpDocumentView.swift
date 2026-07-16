import HwpKitCore
import HwpKitNative
import SwiftUI

public struct HwpDocumentView: View {
    private let document: HwpDocument
    private let zoomScale: Binding<CGFloat>?
    private let currentPage: Binding<Int>?
    private let onHyperlinkTapped: ((String) -> Void)?
    private let onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?

    public init(
        document: HwpDocument,
        zoomScale: Binding<CGFloat>? = nil,
        currentPage: Binding<Int>? = nil,
        onHyperlinkTapped: ((String) -> Void)? = nil,
        onUnsupportedElement: ((HwpUnsupportedElement) -> Void)? = nil
    ) {
        self.document = document
        self.zoomScale = zoomScale
        self.currentPage = currentPage
        self.onHyperlinkTapped = onHyperlinkTapped
        self.onUnsupportedElement = onUnsupportedElement
    }

    public var body: some View {
        #if os(macOS)
            NSViewWrapper(
                document: document,
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        #elseif os(iOS)
            UIViewWrapper(
                document: document,
                zoomScale: zoomScale,
                currentPage: currentPage,
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
        guard let zoomScale, abs(zoomScale.wrappedValue - scale) > 0.001 else { return }
        zoomScale.wrappedValue = scale
    }
}

#if os(macOS)
    private struct NSViewWrapper: NSViewRepresentable {
        let document: HwpDocument
        let zoomScale: Binding<CGFloat>?
        let currentPage: Binding<Int>?
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

        private func configure(_ view: HwpDocumentNSView, context: Context) {
            // Callbacks must be wired before the document assignment so the
            // document didSet notifications reach the coordinator.
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
            view.onZoomChanged = context.coordinator.handleZoomChanged(_:)
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
                if let zoomScale, view.zoomScale != zoomScale.wrappedValue {
                    view.zoomScale = zoomScale.wrappedValue
                }
                if let currentPage, let requestedPage {
                    let pageIndex = max(0, requestedPage - 1)
                    if view.currentVisiblePage() != pageIndex {
                        view.scrollToPage(at: pageIndex)
                    }
                }
            }
        }
    }
#endif

#if os(iOS)
    private struct UIViewWrapper: UIViewRepresentable {
        let document: HwpDocument
        let zoomScale: Binding<CGFloat>?
        let currentPage: Binding<Int>?
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

        private func configure(_ view: HwpDocumentUIView, context: Context) {
            // Callbacks must be wired before the document assignment so the
            // document didSet notifications reach the coordinator.
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
            view.onZoomChanged = context.coordinator.handleZoomChanged(_:)
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
                if let zoomScale, view.zoomScale != zoomScale.wrappedValue {
                    view.zoomScale = zoomScale.wrappedValue
                }
                if let currentPage, let requestedPage {
                    let pageIndex = max(0, requestedPage - 1)
                    if view.currentVisiblePage() != pageIndex {
                        view.scrollToPage(at: pageIndex)
                    }
                }
            }
        }
    }
#endif
