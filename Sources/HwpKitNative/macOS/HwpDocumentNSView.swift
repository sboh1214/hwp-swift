#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import HwpKitCore

    public final class HwpDocumentNSView: NSView {
        public var document: HwpDocument? {
            didSet {
                guard document != oldValue else { return }
                // 프로그레시브 스냅샷 (같은 loadToken + 페이지 증가): 기존
                // 레이어·스크롤 위치를 유지하고 크기·가시 범위만 늘린다.
                if let old = oldValue, let new = document,
                   HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)
                {
                    rebuildPageOrigins()
                    updateContentSize()
                    selectionController.document = document
                    updateVisiblePages(range: visiblePageRange())
                    if new.unsupportedElements != old.unsupportedElements {
                        notifyUnsupportedElements()
                    }
                    return
                }
                pageLayers.values.forEach { $0.removeFromSuperlayer() }
                pageLayers.removeAll()
                memoPanelLayers.values.forEach { $0.removeFromSuperlayer() }
                memoPanelLayers.removeAll()
                rebuildImageProvider()
                rebuildPageOrigins()
                updateContentSize()
                selectionController.document = document
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                updateVisiblePages(range: 0 ..< min(document?.pages.count ?? 0, 3))
                notifyUnsupportedElements()
            }
        }

        public private(set) var imageCache: HwpImageCache

        /// 스크롤 뷰 magnification이 단일 진실 — 별도 배율 상태를 두지 않아
        /// 핀치와 버튼 줌이 어긋날 수 없다.
        public var zoomScale: CGFloat {
            get { scrollView.magnification }
            set {
                let clamped = min(
                    max(newValue, scrollView.minMagnification),
                    scrollView.maxMagnification
                )
                guard abs(scrollView.magnification - clamped) > 0.0001 else { return }
                let visible = scrollView.documentVisibleRect
                scrollView.setMagnification(
                    clamped,
                    centeredAt: CGPoint(x: visible.midX, y: visible.midY)
                )
                updateLayerContentsScale()
            }
        }

        public var onHyperlinkTapped: ((String) -> Void)?
        public var onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
        public var onPageChanged: ((Int) -> Void)?
        public var onZoomChanged: ((CGFloat) -> Void)?

        var pageLayers: [Int: HwpPageLayer] = [:]
        /// 메모 (댓글) 풍선 패널 레이어 — 페이지 오른쪽 바깥 (한글.app 편집 뷰)
        var memoPanelLayers: [Int: HwpPageLayer] = [:]
        /// 페이지별 텍스트 선택 하이라이트 (페이지 레이어의 sublayer)
        var selectionLayers: [Int: CAShapeLayer] = [:]

        /// 텍스트 드래그 선택 상태 (플랫폼 중립 컨트롤러)
        public let selectionController = HwpSelectionController()
        /// 복사 대상 페이스트보드 — 테스트 주입용
        var pasteboard: NSPasteboard = .general

        let scrollView = NSScrollView()
        let documentContentView = HwpFlippedContentView()

        private let hitTester = HwpHitTester()
        let defaultPageSize = CGSize(width: 595, height: 842)
        let pageGap: CGFloat = 24
        private var activeVisibleRange: Range<Int> = 0 ..< 0
        /// Prefix sums of page Y origins so frame lookups stay O(1) while scrolling.
        var pageOriginsY: [CGFloat] = []
        private var imageProvider: HwpPageImageProvider?
        private var lastReportedZoom: CGFloat = 1.0

        override public init(frame: NSRect = .zero) {
            imageCache = HwpImageCache()
            super.init(frame: frame)
            configureViewHierarchy()
            selectionController.onSelectionChanged = { [weak self] in
                self?.updateSelectionOverlays()
            }
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func configureViewHierarchy() {
            scrollView.frame = bounds
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.allowsMagnification = true
            scrollView.minMagnification = 0.25
            scrollView.maxMagnification = 5.0
            // 줌 상태에서 트랙패드 대각 패닝 허용
            scrollView.usesPredominantAxisScrolling = false
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .windowBackgroundColor
            scrollView.contentView = HwpCenteringClipView()
            scrollView.documentView = documentContentView
            addSubview(scrollView)

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            // 라이브 핀치 중에는 래스터 확대만 하고 (프레임당 재드로잉 방지),
            // 핀치가 끝난 시점에 배율만큼 해상도를 올려 선명하게 다시 그린다.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveMagnifyDidEnd(_:)),
                name: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView
            )

            setupClickGesture()
        }

        @objc private func clipViewBoundsDidChange(_: Notification) {
            syncZoomFromMagnification()
            let range = visiblePageRange()
            guard range != activeVisibleRange else { return }
            updateVisiblePages(range: range)
        }

        @objc private func liveMagnifyDidEnd(_: Notification) {
            updateLayerContentsScale()
        }

        /// 핀치 (magnification 변화)를 SwiftUI 바인딩으로 알린다.
        private func syncZoomFromMagnification() {
            let magnification = scrollView.magnification
            guard abs(magnification - lastReportedZoom) > 0.0001 else { return }
            lastReportedZoom = magnification
            onZoomChanged?(magnification)
        }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
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
            return HwpDocumentViewSupport.effectiveContentsScale(
                base: backing, zoomScale: zoomScale
            )
        }

        private func updateLayerContentsScale() {
            HwpDocumentViewSupport.updateContentsScale(
                of: Array(pageLayers.values), Array(memoPanelLayers.values),
                scale: effectiveContentsScale
            )
        }

        override public func layout() {
            super.layout()
            // 창 리사이즈로 뷰포트가 변하면 가시 범위가 낡을 수 있다
            let range = visiblePageRange()
            if !range.isEmpty, range != activeVisibleRange {
                updateVisiblePages(range: range)
            }
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
                documentContentView.layer?.addSublayer(pageLayer)
                if let panelLayer = makeMemoPanelLayer(for: index) {
                    memoPanelLayers[index] = panelLayer
                    documentContentView.layer?.addSublayer(panelLayer)
                }
            }

            layoutPageLayers()
            updateSelectionOverlays()
            onPageChanged?(range.lowerBound)
        }

        /// Scrolls so the given page's top edge is at the top of the viewport.
        public func scrollToPage(at index: Int) {
            guard frameCount() > 0 || document != nil else { return }
            let target = frameForPage(at: index)
            scrollView.contentView.scroll(
                to: NSPoint(x: scrollView.documentVisibleRect.minX, y: target.minY)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateVisiblePages(range: index ..< (index + 1))
        }

        /// The first page currently intersecting the viewport.
        public func currentVisiblePage() -> Int {
            visiblePageRange().first ?? 0
        }

        private func notifyUnsupportedElements() {
            HwpDocumentViewSupport.notifyUnsupportedElements(
                in: document, to: onUnsupportedElement
            )
        }

        private func rebuildImageProvider() {
            guard let built = HwpDocumentViewSupport.makeImageProvider(
                document: document,
                onLayersNeedingDisplay: { [weak self] in
                    self.map { Array($0.pageLayers.values) } ?? []
                }
            ) else {
                imageProvider = nil
                return
            }
            imageCache = built.cache
            imageProvider = built.provider
        }

        private func setupClickGesture() {
            let clickGesture = NSClickGestureRecognizer(
                target: self,
                action: #selector(handleClick(_:))
            )
            documentContentView.addGestureRecognizer(clickGesture)
        }

        @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let contentPoint = gesture.location(in: documentContentView)
            guard let hit = pageHit(at: contentPoint) else { return }

            guard let document, document.pages.indices.contains(hit.pageIndex) else { return }
            let result = hitTester.hit(page: document.pages[hit.pageIndex], point: hit.point)
            dispatchHitResult(result)
        }

        private func dispatchHitResult(_ result: HwpHitResult?) {
            guard let result else { return }
            if case let .hyperlink(url, _) = result {
                onHyperlinkTapped?(url)
            }
        }

        private func pageHit(at contentPoint: CGPoint) -> (pageIndex: Int, point: CGPoint)? {
            for (index, pageLayer) in pageLayers where pageLayer.frame.contains(contentPoint) {
                let origin = pageLayer.frame.origin
                return (index, CGPoint(
                    x: contentPoint.x - origin.x,
                    y: contentPoint.y - origin.y
                ))
            }
            return nil
        }

        private func retainedPageRange(for visibleRange: Range<Int>) -> Range<Int> {
            max(0, visibleRange.lowerBound - 2) ..< (visibleRange.upperBound + 2)
        }

        private func makePageLayer(for index: Int) -> HwpPageLayer {
            let pageLayer = HwpPageLayer()
            let frame = frameForPage(at: index)
            pageLayer.frame = frame
            pageLayer.pageHeight = frame.height
            HwpDocumentViewSupport.decoratePageLayer(
                pageLayer, contentsScale: effectiveContentsScale
            )
            pageLayer.imageProvider = imageProvider
            pageLayer.paintList = paintListForPage(at: index)
            return pageLayer
        }

        /// 페이지에 메모 패널이 있으면 오른쪽 바깥에 투명 레이어로 그린다.
        private func makeMemoPanelLayer(for index: Int) -> HwpPageLayer? {
            HwpDocumentViewSupport.makeMemoPanelLayer(
                document: document,
                pageIndex: index,
                pageFrame: frameForPage(at: index),
                contentsScale: effectiveContentsScale
            )
        }

        private func paintListForPage(at index: Int) -> HwpPaintList? {
            guard let document, document.pages.indices.contains(index) else { return nil }
            return document.pages[index].paintList
        }

        private func layoutPageLayers() {
            // 수동 addSublayer 레이어는 프레임 대입이 기본 애니메이션된다
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, pageLayer) in pageLayers {
                let frame = frameForPage(at: index)
                if pageLayer.frame != frame {
                    pageLayer.frame = frame
                    pageLayer.pageHeight = frame.height
                }
                if pageLayer.paintList == nil {
                    pageLayer.paintList = paintListForPage(at: index)
                }
                if let panelLayer = memoPanelLayers[index] {
                    panelLayer.frame = CGRect(
                        x: frame.maxX,
                        y: frame.minY,
                        width: panelLayer.frame.width,
                        height: frame.height
                    )
                }
            }
            CATransaction.commit()
        }
    }

    /// 페이지 레이어 지오메트리를 top-down으로 유지하기 위한 flipped
    /// documentView. AppKit 기본 y-up 좌표라면 페이지가 아래에서 위로 쌓인다.
    final class HwpFlippedContentView: NSView {
        override var isFlipped: Bool {
            true
        }

        override init(frame: NSRect = .zero) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
#endif
