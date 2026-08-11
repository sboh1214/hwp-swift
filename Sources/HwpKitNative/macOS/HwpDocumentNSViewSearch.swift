#if canImport(AppKit)
    import AppKit
    import CoreGraphics
    import HwpKitCore

    public extension HwpDocumentNSView {
        /// 검색 하이라이트를 다시 그린다.
        ///
        /// 딕셔너리가 **두 벌**인 이유: 헬퍼가 오버레이를 페이지당 하나 재사용하는
        /// 구조라, 전체 매치와 현재 매치를 같은 딕셔너리로 두 번 칠하면 두 번째
        /// 호출이 첫 번째의 path를 덮어쓴다.
        internal func updateSearchOverlays() {
            noteSearchOverlayRebuild()
            let style = searchController?.style ?? .default
            HwpDocumentViewSupport.updateHighlightOverlays(
                pageLayers: pageLayers,
                overlayLayers: &searchMatchLayers,
                highlightRects: { [weak self] page in
                    self?.searchController?.highlightRects(forPage: page) ?? []
                },
                fillColor: style.matchColor.cgColor,
                zPosition: HwpOverlayZ.searchMatch
            )
            HwpDocumentViewSupport.updateHighlightOverlays(
                pageLayers: pageLayers,
                overlayLayers: &currentSearchMatchLayers,
                highlightRects: { [weak self] page in
                    self?.searchController?.currentMatchRects(forPage: page) ?? []
                },
                fillColor: style.currentMatchColor.cgColor,
                zPosition: HwpOverlayZ.currentSearchMatch
            )
        }

        // 검색 컨트롤러를 이 뷰에 배선한다. `searchController` 대입이 부른다.

        /// 스캔이 채운 단위 캐시를 되돌릴 범위 — 페이지 레이어 보존 창과 같다.
        internal func searchRetainedPageRange() -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0 else { return 0 ..< 0 }
            return retainedPageRange(for: visiblePageRange()).clamped(to: 0 ..< pageCount)
        }

        internal func wireSearchController() {
            guard let searchController else {
                searchMatchLayers.values.forEach { $0.removeFromSuperlayer() }
                searchMatchLayers.removeAll()
                currentSearchMatchLayers.values.forEach { $0.removeFromSuperlayer() }
                currentSearchMatchLayers.removeAll()
                return
            }
            searchController.attach(to: selectionController)
            searchController.retainedPageRange = { [weak self] in
                self?.searchRetainedPageRange() ?? 0 ..< 0
            }
            searchController.onMatchesChanged = { [weak self] in
                self?.updateSearchOverlays()
            }
            searchController.onCurrentMatchChanged = { [weak self] match in
                guard let self else { return }
                // 스크롤이 같은 페이지 범위 안에서 끝나면
                // `clipViewBoundsDidChange`가 조기 반환하므로(가시 범위 무변화)
                // 오버레이 갱신이 저절로 오지 않는다 — 그때만 직접 부른다.
                // `scrollToMatch`가 스스로 `updateVisiblePages`를 돌린 경우까지
                // 부르면 페이지별 매치 전량 필터와 CGPath 재구성을 탐색마다
                // 두 번 한다.
                let refreshedByScroll = match.map { self.scrollToMatch($0) } ?? false
                if !refreshedByScroll {
                    updateSearchOverlays()
                }
            }
            updateSearchOverlays()
        }

        /// 매치가 **보이도록** 스크롤한다.
        ///
        /// 목표 오프셋을 페이지 범위로 클램프해 **매치가 놓인 페이지가 첫 가시
        /// 페이지가 되도록** 보장한다. 그래야 `currentVisiblePage()`와 뒤이은
        /// 페이지 바인딩 동기화가 매치 페이지를 가리켜, SwiftUI 쪽 `currentPage`
        /// 왕복이 스크롤을 원래 자리로 되튕기지 않는다.
        /// - Returns: `updateVisiblePages` 를 돌려 오버레이까지 다시 칠했는가.
        ///   호출부가 중복 재구축을 건너뛰는 데 쓴다.
        @discardableResult
        func scrollToMatch(_ match: HwpSearchMatch) -> Bool {
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0, match.pageIndex < pageCount else { return false }
            guard let rect = searchController?
                .rects(for: match)
                .min(by: { $0.minY < $1.minY })
            else {
                scrollToPage(at: match.pageIndex)
                return false
            }
            let pageFrame = frameForPage(at: match.pageIndex)
            let matchInContent = rect.offsetBy(dx: pageFrame.minX, dy: pageFrame.minY)
            let viewportHeight = scrollView.documentVisibleRect.height
            let inset = Swift.min(viewportHeight * 0.3, 120)
            let desired = pageFrame.minY + rect.minY - inset
            let lowest = pageFrame.minY
            let highest = Swift.max(pageFrame.minY, pageFrame.maxY - viewportHeight)
            let targetY = Swift.min(Swift.max(desired, lowest), highest)

            scrollView.contentView.scroll(
                to: NSPoint(x: horizontalOffset(toReveal: matchInContent), y: targetY)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateVisiblePages(range: visiblePageRange())
            return true
        }

        /// 매치를 가로로 화면 안에 들이는 오프셋 (iOS와 같은 규칙).
        ///
        /// 이미 보이면 현재 오프셋을 그대로 둔다 — 매치마다 재조정하면 같은
        /// 단에서 다음 매치로 넘어갈 때 화면이 좌우로 흔들린다.
        internal func horizontalOffset(toReveal rect: CGRect) -> CGFloat {
            let visible = scrollView.documentVisibleRect
            guard visible.width > 0 else { return visible.minX }
            if rect.minX >= visible.minX, rect.maxX <= visible.maxX {
                return visible.minX
            }
            let contentWidth = documentContentView.bounds.width
            let highest = Swift.max(0, contentWidth - visible.width)
            return Swift.min(Swift.max(0, rect.midX - visible.width / 2), highest)
        }
    }
#endif
