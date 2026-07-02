#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import HwpKitCore

    public final class HwpDocumentNSView: NSView {
        public var document: HwpDocument? {
            didSet {
                pageLayers.values.forEach { $0.removeFromSuperlayer() }
                pageLayers.removeAll()
                needsLayout = true
            }
        }

        public var documentActor: HwpDocumentActor?
        public var imageCache: HwpImageCache
        public var zoomScale: CGFloat = 1.0 {
            didSet {
                zoomScale = max(zoomScale, 0.05)
                layoutPageLayers()
            }
        }

        public var onHyperlinkTapped: ((String) -> Void)?
        public var onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
        public var onPageChanged: ((Int) -> Void)?

        var pageLayers: [Int: HwpPageLayer] = [:]

        private let hitTester = HwpHitTester()
        private let defaultPageSize = CGSize(width: 595, height: 842)
        private let pageSpacing: CGFloat = 16
        private var activeVisibleRange: Range<Int> = 0 ..< 0

        override public init(frame: NSRect = .zero) {
            imageCache = HwpImageCache()
            super.init(frame: frame)
            wantsLayer = true
            setupClickGesture()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            wantsLayer = true
            layer?.masksToBounds = false
        }

        override public func layout() {
            super.layout()
            layoutPageLayers()
        }

        public func updateVisiblePages(range: Range<Int>) {
            activeVisibleRange = range

            guard !range.isEmpty else {
                pageLayers.values.forEach { $0.removeFromSuperlayer() }
                pageLayers.removeAll()
                return
            }

            let retainedRange = retainedPageRange(for: range)
            for (index, pageLayer) in pageLayers where !retainedRange.contains(index) {
                pageLayer.removeFromSuperlayer()
                pageLayers[index] = nil
            }

            for index in range where pageLayers[index] == nil {
                let pageLayer = makePageLayer(for: index)
                pageLayers[index] = pageLayer
                layer?.addSublayer(pageLayer)
            }

            layoutPageLayers()
            onPageChanged?(range.lowerBound)
        }

        private func setupClickGesture() {
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            addGestureRecognizer(clickGesture)
        }

        @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let viewPoint = gesture.location(in: self)
            guard let hit = pageHit(at: viewPoint) else { return }

            if let document, document.pages.indices.contains(hit.pageIndex) {
                dispatchHitResult(hitTester.hit(page: document.pages[hit.pageIndex], point: hit.point))
                return
            }

            guard let documentActor else { return }
            Task { [weak self] in
                do {
                    guard let page = try await documentActor.page(at: hit.pageIndex) else { return }
                    let result = HwpHitTester().hit(page: page, point: hit.point)
                    await MainActor.run {
                        self?.dispatchHitResult(result)
                    }
                } catch {
                    return
                }
            }
        }

        private func dispatchHitResult(_ result: HwpHitResult?) {
            guard let result else { return }
            if case let .hyperlink(url, _) = result {
                onHyperlinkTapped?(url)
            }
        }

        private func pageHit(at viewPoint: CGPoint) -> (pageIndex: Int, point: CGPoint)? {
            for (index, pageLayer) in pageLayers {
                let layerPoint = pageLayer.convert(viewPoint, from: layer)
                guard pageLayer.bounds.contains(layerPoint) else { continue }
                return (index, layerPoint)
            }
            return nil
        }

        private func retainedPageRange(for visibleRange: Range<Int>) -> Range<Int> {
            max(0, visibleRange.lowerBound - 2) ..< max(visibleRange.upperBound, visibleRange.upperBound + 2)
        }

        private func makePageLayer(for index: Int) -> HwpPageLayer {
            let pageLayer = HwpPageLayer()
            let pageSize = sizeForPage(at: index)
            pageLayer.pageHeight = pageSize.height
            pageLayer.bounds = CGRect(origin: .zero, size: pageSize)
            pageLayer.backgroundColor = NSColor.white.cgColor
            pageLayer.shadowColor = NSColor.black.cgColor
            pageLayer.shadowOpacity = 0.12
            pageLayer.shadowRadius = 4
            pageLayer.shadowOffset = CGSize(width: 0, height: -1)
            return pageLayer
        }

        private func layoutPageLayers() {
            for (index, pageLayer) in pageLayers {
                let pageSize = sizeForPage(at: index)
                pageLayer.pageHeight = pageSize.height
                pageLayer.bounds = CGRect(origin: .zero, size: pageSize)
                pageLayer.setAffineTransform(CGAffineTransform(scaleX: zoomScale, y: zoomScale))
                pageLayer.position = pageOrigin(for: index, pageSize: pageSize)
            }
        }

        private func pageOrigin(for index: Int, pageSize: CGSize) -> CGPoint {
            let scaledWidth = pageSize.width * zoomScale
            let scaledHeight = pageSize.height * zoomScale
            let xCenter = max((bounds.width - scaledWidth) / 2, 0) + scaledWidth / 2
            let yCenter = CGFloat(index) * (scaledHeight + pageSpacing) + scaledHeight / 2
            return CGPoint(x: xCenter, y: yCenter)
        }

        private func sizeForPage(at index: Int) -> CGSize {
            guard let document, document.pages.indices.contains(index) else { return defaultPageSize }
            return document.pages[index].size
        }
    }
#endif
