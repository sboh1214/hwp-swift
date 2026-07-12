#if os(iOS)
    import CoreGraphics
    import Foundation
    import HwpKitCore
    import UIKit

    public final class HwpDocumentUIView: UIView, UIScrollViewDelegate {
        public var document: HwpDocument? {
            didSet {
                guard document != oldValue else { return }
                pageLayers.values.forEach { $0.removeFromSuperlayer() }
                pageLayers.removeAll()
                memoPanelLayers.values.forEach { $0.removeFromSuperlayer() }
                memoPanelLayers.removeAll()
                rebuildImageProvider()
                rebuildPageOrigins()
                updateContentSize()
                selectionController.document = document
                updateVisiblePages(range: 0 ..< min(document?.pages.count ?? 0, 3))
                notifyUnsupportedElements()
            }
        }

        public private(set) var imageCache: HwpImageCache
        public var zoomScale: CGFloat = 1.0 {
            didSet {
                if scrollView.zoomScale != zoomScale {
                    scrollView.zoomScale = zoomScale
                    // 프로그램적 (버튼) 줌은 scrollViewDidEndZooming이 발화하지
                    // 않으므로 여기서 즉시 재래스터한다. 핀치 경로는
                    // scrollViewDidZoom이 zoomScale을 동기화해 이 분기에 들어오지
                    // 않는다 — 라이브 핀치 중 프레임당 재드로잉 없음 (macOS 대칭).
                    updateLayerContentsScale()
                }
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

        /// 텍스트 롱프레스 선택 상태 (플랫폼 중립 컨트롤러)
        public let selectionController = HwpSelectionController()
        var editMenuInteraction: UIEditMenuInteraction?

        private let scrollView = UIScrollView()
        let contentView = UIView()
        private let hitTester = HwpHitTester()
        private let pageGap: CGFloat = 24
        private let defaultPageSize = CGSize(width: 595, height: 842)
        /// Prefix sums of page Y origins so frame lookups are O(1) during scrolling.
        private var pageOriginsY: [CGFloat] = []
        private var imageProvider: HwpPageImageProvider?

        override public init(frame: CGRect) {
            imageCache = HwpImageCache()
            super.init(frame: frame)
            configureViewHierarchy()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            updateContentSize()
            updateVisiblePages(range: visiblePageRange())
        }

        public func updateVisiblePages(range: Range<Int>) {
            let validRange = clampedPageRange(range)
            let keepRange = expandedRange(validRange)
            let keepSet = Set(keepRange)

            for (index, layer) in pageLayers where !keepSet.contains(index) {
                layer.removeFromSuperlayer()
                pageLayers.removeValue(forKey: index)
                memoPanelLayers[index]?.removeFromSuperlayer()
                memoPanelLayers.removeValue(forKey: index)
            }

            for index in keepRange where pageLayers[index] == nil {
                let layer = HwpPageLayer()
                layer.frame = frameForPage(at: index)
                layer.pageHeight = layer.frame.height
                layer.backgroundColor = PlatformColor.white.cgColor
                layer.shadowColor = PlatformColor.black.cgColor
                layer.shadowOpacity = 0.12
                layer.shadowRadius = 4
                layer.shadowOffset = CGSize(width: 0, height: -1)
                layer.contentsScale = effectiveContentsScale
                layer.imageProvider = imageProvider
                layer.paintList = paintListForPage(at: index)
                contentView.layer.addSublayer(layer)
                pageLayers[index] = layer
                if let panelLayer = makeMemoPanelLayer(for: index, pageFrame: layer.frame) {
                    memoPanelLayers[index] = panelLayer
                    contentView.layer.addSublayer(panelLayer)
                }
            }

            for (index, layer) in pageLayers {
                let frame = frameForPage(at: index)
                if layer.frame != frame {
                    layer.frame = frame
                    layer.pageHeight = frame.height
                }
                if layer.paintList == nil {
                    layer.paintList = paintListForPage(at: index)
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
            updateSelectionOverlays()
        }

        /// 페이지에 메모 패널이 있으면 오른쪽 바깥에 투명 레이어로 그린다.
        private func makeMemoPanelLayer(
            for index: Int,
            pageFrame: CGRect
        ) -> HwpPageLayer? {
            guard let document, document.pages.indices.contains(index),
                  let panel = document.pages[index].memoPanel
            else { return nil }
            let panelLayer = HwpPageLayer()
            panelLayer.frame = CGRect(
                x: pageFrame.maxX,
                y: pageFrame.minY,
                width: panel.width,
                height: pageFrame.height
            )
            panelLayer.pageHeight = pageFrame.height
            panelLayer.contentsScale = effectiveContentsScale
            panelLayer.paintList = panel.paintList
            return panelLayer
        }

        /// Scrolls so the given page's top edge is at the top of the viewport.
        public func scrollToPage(at index: Int) {
            guard let document, document.pages.indices.contains(index) else { return }
            let target = contentView.convert(frameForPage(at: index), to: scrollView)
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let offsetY = max(0, min(target.minY, maxOffsetY))
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: offsetY),
                animated: false
            )
            updateVisiblePages(range: index ..< (index + 1))
        }

        /// The first page currently intersecting the viewport.
        public func currentVisiblePage() -> Int {
            visiblePageRange().first ?? 0
        }

        public func viewForZooming(in _: UIScrollView) -> UIView? {
            contentView
        }

        public func scrollViewDidScroll(_: UIScrollView) {
            let range = visiblePageRange()
            updateVisiblePages(range: range)
            if let firstVisible = range.first {
                onPageChanged?(firstVisible)
            }
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            updateVisiblePages(range: visiblePageRange())
            onZoomChanged?(scrollView.zoomScale)
        }

        public func scrollViewDidEndZooming(
            _: UIScrollView,
            with _: UIView?,
            atScale _: CGFloat
        ) {
            // 핀치가 끝난 시점에 확대 배율만큼 래스터 해상도를 올려 선명하게 다시 그린다.
            updateLayerContentsScale()
        }

        override public func didMoveToWindow() {
            super.didMoveToWindow()
            updateLayerContentsScale()
        }

        /// Retina 해상도 + 줌 배율에 맞춰 레이어 래스터 해상도를 갱신한다.
        /// 기본 contentsScale(1.0)로 두면 Retina에서 흐릿하게 렌더된다.
        private var effectiveContentsScale: CGFloat {
            let screenScale = window?.screen.scale ?? traitCollection.displayScale
            let base = screenScale > 0 ? screenScale : 2
            return min(base * max(1, zoomScale), base * 4)
        }

        private func updateLayerContentsScale() {
            let scale = effectiveContentsScale
            for layer in pageLayers.values where layer.contentsScale != scale {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
            }
        }

        private func configureViewHierarchy() {
            scrollView.delegate = self
            scrollView.minimumZoomScale = 0.25
            scrollView.maximumZoomScale = 5.0
            scrollView.zoomScale = zoomScale
            scrollView.alwaysBounceVertical = true
            scrollView.backgroundColor = .systemBackground

            contentView.backgroundColor = .clear
            contentView.isUserInteractionEnabled = true

            addSubview(scrollView)
            scrollView.addSubview(contentView)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            contentView.addGestureRecognizer(tapGesture)
            configureSelectionInteractions()
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            if selectionController.hasSelection {
                selectionController.clear()
                return
            }
            let location = gesture.location(in: contentView)
            guard let (pageIndex, point) = pagePoint(containing: location),
                  let page = document?.pages[safe: pageIndex],
                  let hit = hitTester.hit(page: page, point: point)
            else { return }

            if case let .hyperlink(url, _) = hit {
                onHyperlinkTapped?(url)
            }
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

        private func rebuildPageOrigins() {
            var origins: [CGFloat] = []
            var originY: CGFloat = 0
            for index in 0 ..< (document?.pages.count ?? 0) {
                origins.append(originY)
                originY += pageSize(at: index).height + pageGap
            }
            pageOriginsY = origins
        }

        private func updateContentSize() {
            let pageCount = document?.pages.count ?? 0
            let largestWidth = (0 ..< pageCount)
                .map { pageSize(at: $0).width }
                .max() ?? defaultPageSize.width
            let totalHeight = (0 ..< pageCount).reduce(CGFloat(0)) { partial, index in
                partial + pageSize(at: index).height + (index == pageCount - 1 ? 0 : pageGap)
            }
            let contentSize = CGSize(width: largestWidth, height: totalHeight)
            // The content view may carry a zoom transform, so set bounds/center
            // (frame is undefined under a non-identity transform) and keep the
            // scroll view's content size in zoomed coordinates.
            contentView.bounds = CGRect(origin: .zero, size: contentSize)
            let scale = scrollView.zoomScale
            contentView.center = CGPoint(
                x: contentSize.width * scale / 2,
                y: contentSize.height * scale / 2
            )
            scrollView.contentSize = CGSize(
                width: contentSize.width * scale,
                height: contentSize.height * scale
            )
        }

        private func visiblePageRange() -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0 else { return 0 ..< 0 }

            // Convert into content-view coordinates so zooming is accounted for.
            let visibleRect = scrollView.bounds.isEmpty
                ? CGRect(origin: scrollView.contentOffset, size: bounds.size)
                : scrollView.convert(scrollView.bounds, to: contentView)
            let visibleIndices = (0 ..< pageCount).filter {
                frameForPage(at: $0).intersects(visibleRect)
            }
            guard let first = visibleIndices.first, let last = visibleIndices.last else {
                return 0 ..< min(pageCount, 1)
            }
            return first ..< (last + 1)
        }

        private func clampedPageRange(_ range: Range<Int>) -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, min(range.lowerBound, pageCount))
            let upper = max(lower, min(range.upperBound, pageCount))
            return lower ..< upper
        }

        private func expandedRange(_ range: Range<Int>) -> Range<Int> {
            guard !range.isEmpty else { return range }
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, range.lowerBound - 2)
            let upper = min(pageCount, range.upperBound + 2)
            return lower ..< upper
        }

        /// 선택 확장 (좌표 클램프)용 노출 — 렌더 배치와 같은 프레임
        func selectionPageFrame(at index: Int) -> CGRect {
            frameForPage(at: index)
        }

        private func frameForPage(at index: Int) -> CGRect {
            let originY = pageOriginsY[safe: index] ?? 0
            return CGRect(origin: CGPoint(x: 0, y: originY), size: pageSize(at: index))
        }

        private func pageSize(at index: Int) -> CGSize {
            document?.pages[safe: index]?.size ?? defaultPageSize
        }

        private func paintListForPage(at index: Int) -> HwpPaintList? {
            document?.pages[safe: index]?.paintList
        }

        private func pagePoint(containing location: CGPoint) -> (Int, CGPoint)? {
            for (index, layer) in pageLayers where layer.frame.contains(location) {
                let pageOrigin = layer.frame.origin
                return (index, CGPoint(x: location.x - pageOrigin.x, y: location.y - pageOrigin.y))
            }
            return nil
        }
    }

    private extension Array {
        subscript(safe index: Int) -> Element? {
            guard indices.contains(index) else { return nil }
            return self[index]
        }
    }
#endif
