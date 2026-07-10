#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import HwpKitCore

    public final class HwpDocumentNSView: NSView {
        public var document: HwpDocument? {
            didSet {
                guard document != oldValue else { return }
                pageLayers.values.forEach { $0.removeFromSuperlayer() }
                pageLayers.removeAll()
                memoPanelLayers.values.forEach { $0.removeFromSuperlayer() }
                memoPanelLayers.removeAll()
                rebuildImageProvider()
                needsLayout = true
                notifyUnsupportedElements()
            }
        }

        public var documentActor: HwpDocumentActor?
        public private(set) var imageCache: HwpImageCache
        public var zoomScale: CGFloat = 1.0 {
            didSet {
                zoomScale = max(zoomScale, 0.05)
                updateLayerContentsScale()
                layoutPageLayers()
            }
        }

        public var onHyperlinkTapped: ((String) -> Void)?
        public var onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
        public var onPageChanged: ((Int) -> Void)?

        var pageLayers: [Int: HwpPageLayer] = [:]
        /// 메모 (댓글) 풍선 패널 레이어 — 페이지 오른쪽 바깥 (한글.app 편집 뷰)
        var memoPanelLayers: [Int: HwpPageLayer] = [:]

        private let hitTester = HwpHitTester()
        private let defaultPageSize = CGSize(width: 595, height: 842)
        private let pageSpacing: CGFloat = 16
        private var activeVisibleRange: Range<Int> = 0 ..< 0
        private var imageProvider: HwpPageImageProvider?

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

        /// Page layers are laid out top-down; without flipping, AppKit's y-up
        /// coordinate space would stack pages bottom-to-top.
        override public var isFlipped: Bool {
            true
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            wantsLayer = true
            layer?.masksToBounds = false
            updateLayerContentsScale()
        }

        override public func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            updateLayerContentsScale()
        }

        /// Retina 해상도 + 줌 배율에 맞춰 레이어 래스터 해상도를 갱신한다.
        /// 기본 contentsScale(1.0)로 두면 Retina에서 흐릿하게 렌더된다.
        private var effectiveContentsScale: CGFloat {
            let backing = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
            return min(backing * max(1, zoomScale), backing * 4)
        }

        private func updateLayerContentsScale() {
            let scale = effectiveContentsScale
            for pageLayer in pageLayers.values where pageLayer.contentsScale != scale {
                pageLayer.contentsScale = scale
                pageLayer.setNeedsDisplay()
            }
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
                memoPanelLayers.values.forEach { $0.removeFromSuperlayer() }
                memoPanelLayers.removeAll()
                return
            }

            let retainedRange = retainedPageRange(for: range)
            for (index, pageLayer) in pageLayers where !retainedRange.contains(index) {
                pageLayer.removeFromSuperlayer()
                pageLayers[index] = nil
                memoPanelLayers[index]?.removeFromSuperlayer()
                memoPanelLayers[index] = nil
            }

            for index in range where pageLayers[index] == nil {
                let pageLayer = makePageLayer(for: index)
                pageLayers[index] = pageLayer
                layer?.addSublayer(pageLayer)
                if let panelLayer = makeMemoPanelLayer(for: index) {
                    memoPanelLayers[index] = panelLayer
                    layer?.addSublayer(panelLayer)
                }
            }

            layoutPageLayers()
            onPageChanged?(range.lowerBound)
        }

        private func notifyUnsupportedElements() {
            document?.unsupportedElements.forEach { onUnsupportedElement?($0) }
        }

        private func rebuildImageProvider() {
            guard let document, !document.imageStore.isEmpty else {
                imageProvider = nil
                return
            }
            // binItemId는 문서-로컬 키이므로 문서마다 새 캐시를 쓴다
            // (이전 문서의 동일 키 이미지 재사용 방지).
            imageCache = HwpImageCache()
            let provider = HwpPageImageProvider(store: document.imageStore, cache: imageCache)
            provider.onImageResolved = { [weak self] key in
                DispatchQueue.main.async {
                    guard let self else { return }
                    for layer in self.pageLayers.values
                        where layer.containsImageReference(key)
                    {
                        layer.setNeedsDisplay()
                    }
                }
            }
            imageProvider = provider
        }

        private func setupClickGesture() {
            let clickGesture = NSClickGestureRecognizer(
                target: self,
                action: #selector(handleClick(_:))
            )
            addGestureRecognizer(clickGesture)
        }

        @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let viewPoint = gesture.location(in: self)
            guard let hit = pageHit(at: viewPoint) else { return }

            if let document, document.pages.indices.contains(hit.pageIndex) {
                let result = hitTester.hit(page: document.pages[hit.pageIndex], point: hit.point)
                dispatchHitResult(result)
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
            max(0, visibleRange.lowerBound - 2) ..< (visibleRange.upperBound + 2)
        }

        private func makePageLayer(for index: Int) -> HwpPageLayer {
            let pageLayer = HwpPageLayer()
            let pageSize = sizeForPage(at: index)
            pageLayer.pageHeight = pageSize.height
            pageLayer.bounds = CGRect(origin: .zero, size: pageSize)
            pageLayer.backgroundColor = PlatformColor.white.cgColor
            pageLayer.shadowColor = PlatformColor.black.cgColor
            pageLayer.shadowOpacity = 0.12
            pageLayer.shadowRadius = 4
            pageLayer.shadowOffset = CGSize(width: 0, height: -1)
            pageLayer.contentsScale = effectiveContentsScale
            pageLayer.imageProvider = imageProvider
            pageLayer.paintList = paintListForPage(at: index)
            return pageLayer
        }

        /// 페이지에 메모 패널이 있으면 오른쪽 바깥에 투명 레이어로 그린다.
        private func makeMemoPanelLayer(for index: Int) -> HwpPageLayer? {
            guard let document, document.pages.indices.contains(index),
                  let panel = document.pages[index].memoPanel
            else { return nil }
            let pageSize = sizeForPage(at: index)
            let panelLayer = HwpPageLayer()
            panelLayer.pageHeight = pageSize.height
            panelLayer.bounds = CGRect(
                origin: .zero,
                size: CGSize(width: panel.width, height: pageSize.height)
            )
            panelLayer.backgroundColor = nil
            panelLayer.contentsScale = effectiveContentsScale
            panelLayer.paintList = panel.paintList
            return panelLayer
        }

        private func paintListForPage(at index: Int) -> HwpPaintList? {
            guard let document, document.pages.indices.contains(index) else { return nil }
            return document.pages[index].paintList
        }

        private func layoutPageLayers() {
            for (index, pageLayer) in pageLayers {
                let pageSize = sizeForPage(at: index)
                pageLayer.pageHeight = pageSize.height
                pageLayer.bounds = CGRect(origin: .zero, size: pageSize)
                pageLayer.setAffineTransform(CGAffineTransform(scaleX: zoomScale, y: zoomScale))
                pageLayer.position = pageOrigin(for: index, pageSize: pageSize)
                if let panelLayer = memoPanelLayers[index] {
                    panelLayer.setAffineTransform(
                        CGAffineTransform(scaleX: zoomScale, y: zoomScale)
                    )
                    // 페이지 오른쪽 모서리에 이어 붙인다
                    panelLayer.position = CGPoint(
                        x: pageLayer.position.x
                            + (pageSize.width + panelLayer.bounds.width) / 2 * zoomScale,
                        y: pageLayer.position.y
                    )
                }
            }
        }

        private func pageOrigin(for index: Int, pageSize: CGSize) -> CGPoint {
            let scaledWidth = pageSize.width * zoomScale
            let scaledHeight = pageSize.height * zoomScale
            let xCenter = max((bounds.width - scaledWidth) / 2, 0) + scaledWidth / 2
            // The view has no scroll surface, so pages are positioned relative to
            // the requested visible range: the anchor page sits at the top and
            // retained neighbors flow above/below it.
            let relativeIndex = CGFloat(index - activeVisibleRange.lowerBound)
            let yCenter = relativeIndex * (scaledHeight + pageSpacing) + scaledHeight / 2
            return CGPoint(x: xCenter, y: yCenter)
        }

        private func sizeForPage(at index: Int) -> CGSize {
            guard let document, document.pages.indices.contains(index) else {
                return defaultPageSize
            }
            return document.pages[index].size
        }
    }
#endif
