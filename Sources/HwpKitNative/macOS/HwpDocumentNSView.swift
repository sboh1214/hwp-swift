#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import HwpKitCore

    public final class HwpDocumentNSView: NSView {
        /// 문서 대입 세대 — 지연 통지가 예약 시점 문서가 아직 현재인지 대조한다.
        /// loadToken은 직접 구성 문서에서 nil이라 교체·clear를 구분하지 못한다 (#3).
        /// 동일 문서 재대입은 세대 불변 — 정당한 pending 통지를 폐기하지 않는다.
        private var documentGeneration: UInt64 = 0
        public var document: HwpDocument? {
            didSet {
                if oldValue != document {
                    documentGeneration &+= 1
                }
                // 렌더 동일성 가드: loadToken이 있으면(로더 산출) 구조 동등성으로
                // 스킵하지만, 토큰이 없으면(직접 구성) 구조가 같아도 렌더가 다를 수
                // 있어 스킵하지 않는다 (#6). 프로그레시브는 아래에서 처리한다.
                let hasRenderIdentity = document == nil || document?.metadata.loadToken != nil
                if hasRenderIdentity, document == oldValue {
                    return
                }
                // 프로그레시브 스냅샷 (같은 loadToken + 페이지 증가): 기존
                // 레이어·스크롤 위치를 유지하고 크기·가시 범위만 늘린다.
                if let old = oldValue, let new = document,
                   HwpDocumentViewSupport.isProgressiveUpdate(from: old, to: new)
                {
                    rebuildPageOrigins()
                    updateContentSize()
                    // 같은 로드 스냅샷이므로 활성 선택을 지우지 않고 지오메트리만 갱신 (#5)
                    selectionController.setDocument(document, preservingSelection: true)
                    updateVisiblePages(range: visiblePageRange())
                    if new.unsupportedElements != old.unsupportedElements {
                        notifyUnsupportedElements()
                    }
                    return
                }
                // nil-token 문서가 구조적으로 같으면 (같은 콘텐츠 재전달 또는
                // 색·폰트만 다른 render-only 변경): 스크롤·이미지 provider를
                // 유지한 채 가시 레이어만 새 문서 paintList로 현재 범위에서 다시
                // 만든다 — 전체 리셋의 scroll(to:.zero)가 없어 페이지가 1로 튀는
                // 루프가 안 생긴다 (#6/#2). imageStore는 == 비교에 포함돼 동일.
                if document == oldValue {
                    pageLayers.values.forEach { $0.removeFromSuperlayer() }
                    pageLayers.removeAll()
                    memoPanelLayers.values.forEach { $0.removeFromSuperlayer() }
                    memoPanelLayers.removeAll()
                    selectionController.setDocument(document, preservingSelection: true)
                    updateVisiblePages(range: visiblePageRange())
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
        /// 최대 행(페이지+메모 패널) 폭 캐시 — frameForPage가 스크롤마다 전
        /// 페이지 폭을 다시 훑지 않도록 지오메트리 재구성 시 한 번만 계산한다 (#27).
        var cachedContentWidth: CGFloat = 595
        private var imageProvider: HwpPageImageProvider?
        private var lastReportedZoom: CGFloat = 1.0
        private var lastReportedPage = -1

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

            // 보존 창 (가시 ±2)을 미리 실체화한다 — 가시 범위만 만들면 인접
            // 페이지가 뷰포트 진입 후에야 생성돼 스크롤 중 플레이스홀더가
            // 번쩍인다 (iOS keepRange와 대칭, R31 #4). 문서가 없으면 페이지
            // 수를 몰라 프리페치 없이 가시 범위만 만든다.
            let pageCount = document?.pages.count ?? 0
            let materializedRange = pageCount > 0
                ? retainedRange.clamped(to: 0 ..< pageCount)
                : range
            for index in materializedRange where pageLayers[index] == nil {
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
            // 가시(±2) 페이지가 참조하는 이미지를 pin해 캐시 축출→재요청 사이클을
            // 막는다 (#2).
            imageProvider?.setPinnedImages(
                HwpDocumentViewSupport.imageReferences(in: document, pageRange: retainedRange)
            )
            reportPageChange(range.lowerBound)
        }

        /// 마지막 통지 페이지와 다를 때만 onPageChanged를 발화한다 — 문서 교체·
        /// scrollToPage(at:)가 clip-view bounds 통지 + 명시 refresh 양쪽으로
        /// updateVisiblePages를 불러 같은 페이지를 2번 통지하는 것을 막는다
        /// (iOS와 동일 가드, #2).
        private func reportPageChange(_ page: Int) {
            guard page != lastReportedPage else { return }
            lastReportedPage = page
            onPageChanged?(page)
        }

        /// Scrolls so the given page's top edge is at the top of the viewport.
        public func scrollToPage(at index: Int) {
            // 문서 교체로 낡은(큰) 페이지 인덱스가 남아도 존재하지 않는 페이지를
            // 만들지 않도록 유효 범위로 클램프한다 (#24).
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0 else { return }
            let clamped = max(0, min(index, pageCount - 1))
            let target = frameForPage(at: clamped)
            scrollView.contentView.scroll(
                to: NSPoint(x: scrollView.documentVisibleRect.minX, y: target.minY)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            // 스크롤 후 실제 가시 범위로 갱신한다 — 한 페이지 범위로 갱신하면
            // 25% 줌·큰 뷰포트가 5쪽 넘게 보일 때 여전히 보이는 쪽들이 ±2 유지창
            // 밖으로 밀려 blank가 된다 (#1).
            updateVisiblePages(range: visiblePageRange())
        }

        /// The first page currently intersecting the viewport.
        public func currentVisiblePage() -> Int {
            visiblePageRange().first ?? 0
        }

        private func notifyUnsupportedElements() {
            // document 대입은 SwiftUI representable 업데이트 중에 올 수 있다 —
            // 콜백이 @State에 쓰면 state-during-update 위반이므로 업데이트 밖에서
            // 발화한다 (P2). 대입 시점의 문서를 캡처하되, 발화 전 그새 다른
            // 문서로 교체됐으면(loadToken 불일치) stale 경고를 폐기한다 (#5).
            let document = document
            let generation = documentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, documentGeneration == generation else { return }
                HwpDocumentViewSupport.notifyUnsupportedElements(
                    in: document, to: onUnsupportedElement
                )
            }
        }

        private func rebuildImageProvider() {
            // 옛 provider의 진행 중 디코드를 취소해 강참조·대형 디코드 누적을 끊는다 (#3).
            imageProvider?.cancelOutstanding()
            guard let built = HwpDocumentViewSupport.makeImageProvider(
                document: document,
                onLayersNeedingDisplay: { [weak self] in
                    self.map { Array($0.pageLayers.values) } ?? []
                }
            ) else {
                imageProvider = nil
                // 이미지 없는 문서로 교체 시 이전 문서 디코드 이미지(최대 256MB)를
                // 새 빈 캐시로 교체해 즉시 해제한다 (P1).
                imageCache = HwpImageCache()
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
                        // 콘텐츠 높이로 만든 패널 레이어 높이를 유지한다 (레이아웃 갱신이
                        // 페이지 높이로 되돌려 #8 오버플로 패널이 다시 클립되지 않게).
                        height: panelLayer.frame.height
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
