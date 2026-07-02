#if os(iOS)
    import CoreGraphics
    import Foundation
    import HwpKitCore
    import UIKit

    public final class HwpDocumentUIView: UIView, UIScrollViewDelegate {
        public var document: HwpDocument? {
            didSet {
                updateContentSize()
                updateVisiblePages(range: 0 ..< min(document?.pages.count ?? 0, 3))
                notifyUnsupportedElements()
            }
        }

        public var documentActor: HwpDocumentActor?
        public var imageCache: HwpImageCache
        public var zoomScale: CGFloat = 1.0 {
            didSet {
                if scrollView.zoomScale != zoomScale {
                    scrollView.zoomScale = zoomScale
                }
            }
        }

        public var onHyperlinkTapped: ((String) -> Void)?
        public var onUnsupportedElement: ((HwpUnsupportedElement) -> Void)?
        public var onPageChanged: ((Int) -> Void)?

        var pageLayers: [Int: HwpPageLayer] = [:]

        private let scrollView = UIScrollView()
        private let contentView = UIView()
        private let hitTester = HwpHitTester()
        private let pageGap: CGFloat = 24
        private let defaultPageSize = CGSize(width: 595, height: 842)

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
            }

            for index in keepRange where pageLayers[index] == nil {
                let layer = HwpPageLayer()
                layer.frame = frameForPage(at: index)
                layer.pageHeight = layer.frame.height
                contentView.layer.addSublayer(layer)
                pageLayers[index] = layer
            }

            for (index, layer) in pageLayers {
                layer.frame = frameForPage(at: index)
                layer.pageHeight = layer.frame.height
            }

            if let firstVisible = validRange.first {
                onPageChanged?(firstVisible)
            }
        }

        public func viewForZooming(in _: UIScrollView) -> UIView? {
            contentView
        }

        public func scrollViewDidScroll(_: UIScrollView) {
            updateVisiblePages(range: visiblePageRange())
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            updateVisiblePages(range: visiblePageRange())
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
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
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

        private func updateContentSize() {
            let pageCount = max(document?.pages.count ?? 0, pageLayers.keys.max().map { $0 + 1 } ?? 0)
            let largestWidth = (0 ..< pageCount)
                .map { pageSize(at: $0).width }
                .max() ?? defaultPageSize.width
            let totalHeight = (0 ..< pageCount).reduce(CGFloat(0)) { partial, index in
                partial + pageSize(at: index).height + (index == pageCount - 1 ? 0 : pageGap)
            }
            let contentSize = CGSize(width: largestWidth, height: totalHeight)
            contentView.frame = CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize
        }

        private func visiblePageRange() -> Range<Int> {
            let pageCount = max(document?.pages.count ?? 0, pageLayers.keys.max().map { $0 + 1 } ?? 0)
            guard pageCount > 0 else { return 0 ..< 0 }

            let visibleRect = scrollView.bounds.isEmpty
                ? CGRect(origin: scrollView.contentOffset, size: bounds.size)
                : CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
            let visibleIndices = (0 ..< pageCount).filter { frameForPage(at: $0).intersects(visibleRect) }
            guard let first = visibleIndices.first, let last = visibleIndices.last else {
                return 0 ..< min(pageCount, 1)
            }
            return first ..< (last + 1)
        }

        private func clampedPageRange(_ range: Range<Int>) -> Range<Int> {
            let upperBound = max(document?.pages.count ?? 0, range.upperBound)
            let lower = max(0, min(range.lowerBound, upperBound))
            let upper = max(lower, min(range.upperBound, upperBound))
            return lower ..< upper
        }

        private func expandedRange(_ range: Range<Int>) -> Range<Int> {
            guard !range.isEmpty else { return range }
            let pageCount = max(document?.pages.count ?? 0, range.upperBound)
            let lower = max(0, range.lowerBound - 2)
            let upper = min(pageCount, range.upperBound + 2)
            return lower ..< upper
        }

        private func frameForPage(at index: Int) -> CGRect {
            let originY = (0 ..< index).reduce(CGFloat(0)) { partial, pageIndex in
                partial + pageSize(at: pageIndex).height + pageGap
            }
            return CGRect(origin: CGPoint(x: 0, y: originY), size: pageSize(at: index))
        }

        private func pageSize(at index: Int) -> CGSize {
            document?.pages[safe: index]?.size ?? defaultPageSize
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
