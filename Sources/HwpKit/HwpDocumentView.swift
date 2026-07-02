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

        func makeCoordinator() -> Coordinator {
            Coordinator(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        }

        private func configure(_ view: HwpDocumentNSView, context: Context) {
            view.document = document
            if let zoomScale {
                view.zoomScale = zoomScale.wrappedValue
            }
            if let currentPage {
                view.updateVisiblePages(range: currentPage.wrappedValue ..< (currentPage.wrappedValue + 1))
            }
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
        }

        final class Coordinator {
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
                currentPage?.wrappedValue = page
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

        func makeCoordinator() -> Coordinator {
            Coordinator(
                zoomScale: zoomScale,
                currentPage: currentPage,
                onHyperlinkTapped: onHyperlinkTapped,
                onUnsupportedElement: onUnsupportedElement
            )
        }

        private func configure(_ view: HwpDocumentUIView, context: Context) {
            view.document = document
            if let zoomScale {
                view.zoomScale = zoomScale.wrappedValue
            }
            if let currentPage {
                view.updateVisiblePages(range: currentPage.wrappedValue ..< (currentPage.wrappedValue + 1))
            }
            view.onHyperlinkTapped = context.coordinator.handleHyperlinkTapped(_:)
            view.onUnsupportedElement = context.coordinator.handleUnsupportedElement(_:)
            view.onPageChanged = context.coordinator.handlePageChanged(_:)
        }

        final class Coordinator {
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
                currentPage?.wrappedValue = page
            }
        }
    }
#endif
