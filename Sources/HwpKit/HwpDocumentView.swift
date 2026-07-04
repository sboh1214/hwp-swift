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
        // The equality guard keeps configure()'s echo of the binding-derived
        // page from writing state back during a SwiftUI view update.
        guard let currentPage, currentPage.wrappedValue != page + 1 else { return }
        currentPage.wrappedValue = page + 1
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
            if view.document != document {
                view.document = document
            }
            if let zoomScale, view.zoomScale != zoomScale.wrappedValue {
                view.zoomScale = zoomScale.wrappedValue
            }
            let pageIndex = currentPage.map { max(0, $0.wrappedValue - 1) } ?? 0
            view.updateVisiblePages(range: pageIndex ..< pageIndex + 1)
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
            if view.document != document {
                view.document = document
            }
            if let zoomScale, view.zoomScale != zoomScale.wrappedValue {
                view.zoomScale = zoomScale.wrappedValue
            }
            if let currentPage {
                let pageIndex = max(0, currentPage.wrappedValue - 1)
                if view.currentVisiblePage() != pageIndex {
                    view.scrollToPage(at: pageIndex)
                }
            }
        }
    }
#endif
