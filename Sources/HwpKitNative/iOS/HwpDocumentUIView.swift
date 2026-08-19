#if os(iOS)
    import CoreGraphics
    import Foundation
    import HwpKitCore
    import UIKit

    public final class HwpDocumentUIView: UIView, UIScrollViewDelegate {
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
                    // 조기 반환하는 분기이고 문서 대입은 자기 자신에게 레이아웃을 걸지
                    // 않으므로, 이 호출이 빠지면 예약된 맞춤이 무관한 리사이즈까지
                    // 잠든다 (교체 didSet 끝의 같은 호출과 한 쌍이다).
                    applyPendingFitZoom()
                    updateVisiblePages(range: visiblePageRange())
                    if new.unsupportedElements != old.unsupportedElements {
                        notifyUnsupportedElements()
                    }
                    return
                }
                // nil-token 문서가 구조적으로 같으면 (같은 콘텐츠 재전달 또는
                // 색·폰트만 다른 render-only 변경): 스크롤·이미지 provider를
                // 유지한 채 가시 레이어만 새 문서 paintList로 현재 범위에서 다시
                // 만든다 — setContentOffset(.zero)가 없어 페이지가 1로 튀는
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
                // 전체 교체는 새 문서를 맨 위(센터링 원점)에서 연다. SwiftUI 경로는
                // makeUIView가 bounds 0일 때 대입해 이 시점 인셋이 0 → 즉시 적용이
                // no-op이므로, 첫 non-zero layoutSubviews에서 재적용하도록 예약한다
                // (bounds가 이미 있으면 아래 호출이 즉시 적용, R39 #2·R40 #1).
                pendingInitialCentering = true
                // 옛 문서의 예약 페이지는 버린다 — 남기면 교체 문서를 그 페이지에서
                // 열어 "맨 위에서 연다"는 계약이 깨진다. 교체 후 새 요청이 오면
                // scrollToPage가 다시 채운다 (R71 #2).
                pendingInitialPageIndex = nil
                applyPendingInitialCentering()
                selectionController.document = document
                updateVisiblePages(range: 0 ..< min(document?.pages.count ?? 0, 3))
                // 옛 문서를 향한 fit 예약은 버린다 — 남기면 A 에서 건 맞춤이
                // 나중에 B 의 배율을 뺏는다 (iOS `pendingInitialPageIndex` 가 같은
                // 이유로 교체 때 버려진다, R71 #2). 다만 **쪽이 하나도 없던 상태**에서
                // 온 요청은 이 문서를 향한 "열자마자 맞춤"이라 살려 둔다.
                //
                // 그리고 그 자리에서 바로 적용한다: 문서 대입은 자기 자신에게
                // 레이아웃을 걸지 않으므로(자식 프레임만 바뀐다) 그냥 두면 예약이
                // 다음 리사이즈까지 잠든다. 캔버스는 위 `updateContentSize()` 로
                // 이미 확정됐다.
                if oldValue?.pages.isEmpty == false {
                    pendingFitZoom = nil
                }
                applyPendingFitZoom()
                notifyUnsupportedElements()
            }
        }

        public private(set) var imageCache: HwpImageCache
        public var zoomScale: CGFloat = 1.0 {
            didSet {
                // 네이티브 한계로 클램프한 값만 보관한다 — 클램프 전 값이 남으면
                // HwpKit의 범위 정규화가 그것을 실제 배율로 오인해 (이미 상한이라
                // 스크롤 뷰가 안 바뀌면 echo도 없다) 바인딩과 렌더가 영구히
                // 어긋난다. macOS는 magnification을 읽는 computed라 무관.
                // 비-finite는 직전 값을 유지한다 (R72 #3).
                let clamped = zoomScale.isFinite
                    ? Swift.min(
                        Swift.max(zoomScale, scrollView.minimumZoomScale),
                        scrollView.maximumZoomScale
                    )
                    : oldValue
                if clamped != zoomScale {
                    zoomScale = clamped
                }
                if scrollView.zoomScale != clamped {
                    scrollView.zoomScale = clamped
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
        /// 마지막으로 통지한 페이지 — 스크롤·레이아웃·줌이 같은 페이지를
        /// 반복 통지하지 않도록 dedup한다 (#5).
        private var lastReportedPage = -1
        /// 마지막으로 적용한 가시 범위 (macOS `activeVisibleRange` 와 대칭).
        /// `scrollToMatch` 가 스크롤 전후로 이 값을 비교해 **스크롤 콜백이 이미
        /// 갱신했는지** 판정하므로 읽기는 internal 이다.
        private(set) var activeVisibleRange: Range<Int> = 0 ..< 0

        /// 검색 오버레이를 다시 만든 횟수 — 테스트 전용 관측점 (macOS와 대칭).
        private(set) var searchOverlayRebuildCount = 0

        func noteSearchOverlayRebuild() {
            searchOverlayRebuildCount &+= 1
        }

        public var onZoomChanged: ((CGFloat) -> Void)?

        var pageLayers: [Int: HwpPageLayer] = [:]
        /// 메모 (댓글) 풍선 패널 레이어 — 페이지 오른쪽 바깥 (한글.app 편집 뷰)
        var memoPanelLayers: [Int: HwpPageLayer] = [:]
        /// 페이지별 텍스트 선택 하이라이트 (페이지 레이어의 sublayer)
        var selectionLayers: [Int: CAShapeLayer] = [:]

        /// 페이지별 검색 하이라이트 — 전체 매치와 현재 매치를 **각자** 딕셔너리로
        /// 둔다. 헬퍼가 페이지당 오버레이 하나를 재사용하므로 한 벌로 두 번
        /// 칠하면 두 번째가 첫 번째를 덮는다.
        var searchMatchLayers: [Int: CAShapeLayer] = [:]
        var currentSearchMatchLayers: [Int: CAShapeLayer] = [:]

        /// 텍스트 롱프레스 선택 상태 (플랫폼 중립 컨트롤러)
        public let selectionController = HwpSelectionController()

        /// 문서 검색 세션 주입 (#75). macOS와 같은 계약 — 재대입은 멱등이고,
        /// 뷰 해체(`dismantleUIView`)가 nil을 넣어 세션을 뗀다.
        /// SwiftUI wrapper가 매 갱신마다 대입하므로, 이 가드가 없으면
        /// 재배선 → 재스캔 → 관찰자 통지 → 뷰 갱신 루프가 타이핑 없이도 돈다.
        /// 떼는 대상이 **자기 것뿐**인 이유도 macOS와 같다.
        public var searchController: HwpSearchController? {
            didSet {
                guard oldValue !== searchController else { return }
                if let oldValue, oldValue.isAttached(to: selectionController) {
                    oldValue.detach()
                    HwpDocumentViewSupport.removeSearchHooks(from: oldValue)
                }
                wireSearchController()
            }
        }

        /// 선택 제스처의 일시 상태 — 편집 메뉴, 엣지 오토스크롤(롱프레스 정지
        /// 시 .changed가 오지 않아 CADisplayLink로 밀어준다), 끝점 핸들과 그랩
        /// 오프셋. 값 타입 하나로 **묶어야만** 하는 이유는
        /// `HwpSelectionInteractionState`의 주석에 있다 (SwiftLint
        /// `type_body_length` error 임계). 다루는 곳은 Selection extension 둘이다.
        var selectionInteraction = HwpSelectionInteractionState()

        let scrollView = UIScrollView()
        let contentView = UIView()
        private let hitTester = HwpHitTester()
        let pageGap: CGFloat = 24
        let defaultPageSize = CGSize(width: 595, height: 842)
        /// Prefix sums of page Y origins so frame lookups are O(1) during scrolling.
        var pageOriginsY: [CGFloat] = []
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

        deinit {
            HwpDocumentViewSupport.detachSearchSessionOnTeardown(
                searchController, from: selectionController
            )
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            updateContentSize()
            applyPendingInitialCentering()
            // 뷰포트·캔버스가 확정된 **뒤**라야 fit 배율을 낼 수 있고, 초기 센터링
            // 다음이어야 쪽 맞춤의 스크롤이 센터링에 덮이지 않는다 (#78).
            applyPendingFitZoom()
            updateVisiblePages(range: visiblePageRange())
        }

        public func updateVisiblePages(range: Range<Int>) {
            activeVisibleRange = range
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
                HwpDocumentViewSupport.decoratePageLayer(
                    layer, contentsScale: effectiveContentsScale
                )
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
                        // 콘텐츠 높이로 만든 패널 레이어 높이를 유지한다 (레이아웃 갱신이
                        // 페이지 높이로 되돌려 #8 오버플로 패널이 다시 클립되지 않게).
                        height: panelLayer.frame.height
                    )
                }
            }
            // 가시(±2) 페이지가 참조하는 이미지를 pin해 캐시 축출→재요청 사이클을
            // 막는다 (macOS와 대칭, #2).
            imageProvider?.setPinnedImages(
                HwpDocumentViewSupport.imageReferences(in: document, pageRange: keepRange)
            )
            // 프로그래매틱 네비가 기존 오프셋으로 클램프돼 scrollViewDidScroll이
            // 안 오는 경우에도 페이지 변경을 알린다. 마지막 통지와 같으면 생략해
            // 스크롤·레이아웃·줌의 중복 통지를 없앤다 (macOS와 대칭, #5).
            if let first = validRange.first {
                reportPageChange(first)
            }
            updateSelectionOverlays()
            updateSearchOverlays()
            // 오버레이를 그린 **뒤** 축출한다 (macOS와 대칭) — 방금 그린 페이지는
            // 유지 범위 안이라 살아남는다.
            searchController?.evictUnitsOutsideRetainedRange()
        }

        /// 페이지에 메모 패널이 있으면 오른쪽 바깥에 투명 레이어로 그린다.
        private func makeMemoPanelLayer(
            for index: Int,
            pageFrame: CGRect
        ) -> HwpPageLayer? {
            HwpDocumentViewSupport.makeMemoPanelLayer(
                document: document,
                pageIndex: index,
                pageFrame: pageFrame,
                contentsScale: effectiveContentsScale
            )
        }

        /// Scrolls so the given page's top edge is at the top of the viewport.
        public func scrollToPage(at index: Int) {
            // 범위 밖 요청(짧은 문서로 교체된 뒤 남은 큰 인덱스)을 조용히 무시하지
            // 않고 가장 가까운 유효 페이지로 클램프한다 — macOS와 대칭 (#4).
            guard let document, !document.pages.isEmpty else { return }
            let index = max(0, min(index, document.pages.count - 1))
            // bounds가 아직 0이면(SwiftUI makeUIView 시점) offset 계산이 무의미하고,
            // 예약된 초기 센터링이 첫 실측 레이아웃에서 이 요청을 덮는다 — 목표
            // 페이지를 예약해 그 레이아웃에서 복원한다 (R70 #1).
            if scrollView.bounds.isEmpty, pendingInitialCentering {
                pendingInitialPageIndex = index
                return
            }
            pendingInitialPageIndex = nil
            let target = contentView.convert(frameForPage(at: index), to: scrollView)
            let offsetY = clampedContentOffsetY(target.minY)
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: offsetY),
                animated: false
            )
            // 스크롤 후 실제 가시 범위로 갱신 — 한 페이지 범위는 큰 뷰포트/저배율에서
            // 여전히 보이는 쪽을 blank로 만든다 (macOS와 대칭, #1).
            updateVisiblePages(range: visiblePageRange())
        }

        /// The first page currently intersecting the viewport.
        public func currentVisiblePage() -> Int {
            visiblePageRange().first ?? 0
        }

        public func viewForZooming(in _: UIScrollView) -> UIView? {
            contentView
        }

        public func scrollViewDidScroll(_: UIScrollView) {
            // updateVisiblePages가 페이지 변경을 (dedup으로) 통지하므로 여기서
            // 다시 부르지 않는다 — 스크롤마다 동일 통지 2회를 없앤다 (#5).
            let range = visiblePageRange()
            // 핸들은 줌 대상 밖(스크롤 뷰의 형제)에 살아 스크롤을 따라 움직이지
            // 않는다 — 아래 가시 범위 가드 **앞에서** 다시 잡아야 한다 (#84).
            updateSelectionHandles()
            // 가시 범위가 그대로면 실체화도 재도색도 할 일이 없다 — 페이지
            // 레이어는 스크롤과 함께 움직인다. 검색 오버레이 재구축은 페이지마다
            // 매치 전량(상한 5,000)을 훑어 CGPath를 새로 만들므로 이 가드가
            // 없으면 그 비용을 매 틱 메인 액터에서 문다 (macOS
            // `clipViewBoundsDidChange` 와 같은 가드). 줌은 프레임이 바뀌므로
            // `scrollViewDidZoom` 은 가드 없이 그대로 둔다.
            guard range != activeVisibleRange else { return }
            updateVisiblePages(range: range)
        }

        /// 마지막 통지 페이지와 다를 때만 onPageChanged를 발화한다 (#5).
        private func reportPageChange(_ page: Int) {
            guard page != lastReportedPage else { return }
            lastReportedPage = page
            onPageChanged?(page)
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            updateVisiblePages(range: visiblePageRange())
            // 줌으로 "콘텐츠 < 뷰포트" 여부가 바뀌면 센터링 inset도 갱신한다 —
            // updateContentSize만으로는 이전 배율 여백이 남는다 (P2).
            updateCenteringInset()
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
            if window == nil {
                // CADisplayLink는 target을 보유한다 — 창에서 빠지면 반드시 해제
                stopSelectionAutoscroll()
            }
        }

        /// Retina 해상도 + 줌 배율에 맞춰 레이어 래스터 해상도를 갱신한다.
        /// 기본 contentsScale(1.0)로 두면 Retina에서 흐릿하게 렌더된다.
        private var effectiveContentsScale: CGFloat {
            let screenScale = window?.screen.scale ?? traitCollection.displayScale
            let base = screenScale > 0 ? screenScale : 2
            return HwpDocumentViewSupport.effectiveContentsScale(
                base: base, zoomScale: zoomScale
            )
        }

        func updateLayerContentsScale() {
            // 메모 패널 레이어도 함께 재래스터 (macOS와 통일)
            HwpDocumentViewSupport.updateContentsScale(
                of: Array(pageLayers.values), Array(memoPanelLayers.values),
                scale: effectiveContentsScale
            )
            // 오버레이는 부착 때 부모 배율을 물려받으므로 여기서 다시 칠하지
            // 않으면 줌이 끝난 뒤에도 옛 배율로 남는다 (macOS와 같은 규약).
            updateSelectionOverlays()
            updateSearchOverlays()
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

        private func rebuildPageOrigins() {
            var origins: [CGFloat] = []
            var originY: CGFloat = 0
            for index in 0 ..< (document?.pages.count ?? 0) {
                origins.append(originY)
                originY += rowHeight(at: index) + pageGap
            }
            pageOriginsY = origins
        }

        /// 메모 패널이 페이지보다 길면 그 높이로 행을 잡아 다음 행과 겹치거나
        /// 마지막 페이지 오버플로가 스크롤 밖으로 나가지 않게 한다 (#4).
        func rowHeight(at index: Int) -> CGFloat {
            let pageHeight = pageSize(at: index).height
            guard let panel = document?.pages[safe: index]?.memoPanel else { return pageHeight }
            return max(pageHeight, panel.contentHeight)
        }

        private func updateContentSize() {
            let pageCount = document?.pages.count ?? 0
            let largestWidth = (0 ..< pageCount)
                .map { rowWidth(at: $0) }
                .max() ?? defaultPageSize.width
            let totalHeight = (0 ..< pageCount).reduce(CGFloat(0)) { partial, index in
                partial + rowHeight(at: index) + (index == pageCount - 1 ? 0 : pageGap)
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
            let scaledWidth = contentSize.width * scale
            let scaledHeight = contentSize.height * scale
            scrollView.contentSize = CGSize(width: scaledWidth, height: scaledHeight)
            updateCenteringInset()
        }

        /// 아직 못 맞춘 fit 명령 (#78). 뷰포트가 실측되기 전(SwiftUI `makeUIView`)
        /// 이거나 문서에 쪽이 아직 없을 때 온 요청을 담아, 첫 실측 레이아웃 또는
        /// 문서 대입에서 적용한다 — 아래 초기 센터링 예약과 같은 형태다. 조용히
        /// 버리면 호스트가 "열자마자 폭 맞춤"을 걸 수 없다.
        var pendingFitZoom: HwpZoomFit?
        /// 문서 교체 후 첫 non-zero 레이아웃에서 센터링 원점을 1회 적용하기 위한
        /// 예약 — 적용 후 해제해 이후 사용자 스크롤을 덮지 않는다 (R40 #1).
        private var pendingInitialCentering = false
        /// 예약된 초기 목표 페이지 (0-based). bounds가 0인 동안 들어온 명시
        /// 페이지 요청을 담아 첫 실측 레이아웃에서 그 페이지로 복원한다 —
        /// 없으면 센터링 원점으로 간다 (R70 #1).
        private var pendingInitialPageIndex: Int?

        /// bounds가 실측(non-zero)일 때만 예약된 초기 위치로 한 번 옮긴다.
        /// 명시 페이지 요청이 예약돼 있으면 센터링 원점 대신 그 페이지로 간다 —
        /// 센터링이 요청을 덮으면 currentPage 바인딩까지 1로 되돌아간다 (R70 #1).
        private func applyPendingInitialCentering() {
            guard pendingInitialCentering, !scrollView.bounds.isEmpty else { return }
            pendingInitialCentering = false
            if let pageIndex = pendingInitialPageIndex {
                pendingInitialPageIndex = nil
                scrollToPage(at: pageIndex)
                return
            }
            let inset = scrollView.adjustedContentInset
            scrollView.setContentOffset(
                CGPoint(x: -inset.left, y: -inset.top), animated: false
            )
        }

        private func clampedPageRange(_ range: Range<Int>) -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, min(range.lowerBound, pageCount))
            let upper = max(lower, min(range.upperBound, pageCount))
            return lower ..< upper
        }

        /// 선택 확장 (좌표 클램프)용 노출 — 렌더 배치와 같은 프레임
        func selectionPageFrame(at index: Int) -> CGRect {
            frameForPage(at: index)
        }

        func pageSize(at index: Int) -> CGSize {
            document?.pages[safe: index]?.size ?? defaultPageSize
        }

        /// 메모 패널은 페이지 오른쪽 바깥에 그려지므로 콘텐츠 폭에 패널 폭을
        /// 포함해야 스크롤 뷰가 패널을 잘리지 않고 드러낸다 (macOS rowWidth와 대칭).
        func rowWidth(at index: Int) -> CGFloat {
            let pageWidth = pageSize(at: index).width
            guard let panel = document?.pages[safe: index]?.memoPanel else { return pageWidth }
            return pageWidth + panel.width
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
#endif
