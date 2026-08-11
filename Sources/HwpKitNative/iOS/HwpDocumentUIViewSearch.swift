#if canImport(UIKit)
    import CoreGraphics
    import HwpKitCore
    import UIKit

    public extension HwpDocumentUIView {
        /// 검색 하이라이트를 다시 그린다 (macOS와 대칭).
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

        /// 스캔이 채운 단위 캐시를 되돌릴 범위 — 페이지 레이어 보존 창과 같다.
        internal func searchRetainedPageRange() -> Range<Int> {
            guard let document, !document.pages.isEmpty else { return 0 ..< 0 }
            return expandedRange(visiblePageRange()).clamped(to: 0 ..< document.pages.count)
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
                // 스크롤 경로가 이미 다시 칠했으면 건너뛴다 (macOS와 같은 규약).
                let refreshedByScroll = match.map { self.scrollToMatch($0) } ?? false
                if !refreshedByScroll {
                    updateSearchOverlays()
                }
            }
            updateSearchOverlays()
        }

        /// 매치가 보이도록 스크롤한다.
        ///
        /// 매치 페이지가 첫 가시 페이지가 되도록 페이지 범위로 클램프한다 —
        /// 그래야 `currentVisiblePage()`가 매치 페이지를 가리켜 SwiftUI 쪽
        /// 페이지 바인딩 왕복이 스크롤을 되튕기지 않는다.
        ///
        /// 첫 레이아웃 전(`bounds`가 비고 초기 센터링이 예약된 상태)에는
        /// `scrollToPage(at:)`가 목표 페이지를 예약만 하고 돌아간다 — 그 경로를
        /// 그대로 태운다.
        /// - Returns: `updateVisiblePages` 를 돌려 오버레이까지 다시 칠했는가
        ///   (macOS와 같은 계약 — 호출부가 중복 재구축을 건너뛴다).
        @discardableResult
        func scrollToMatch(_ match: HwpSearchMatch) -> Bool {
            guard let document, !document.pages.isEmpty,
                  match.pageIndex < document.pages.count else { return false }
            guard !scrollView.bounds.isEmpty,
                  let rect = searchController?
                  .currentMatchRects(forPage: match.pageIndex)
                  .min(by: { $0.minY < $1.minY })
            else {
                scrollToPage(at: match.pageIndex)
                return false
            }
            let pageFrame = frameForPage(at: match.pageIndex)
            let matchInContent = CGRect(
                x: pageFrame.minX + rect.minX,
                y: pageFrame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
            let pageInScroll = contentView.convert(pageFrame, to: scrollView)
            let matchInScroll = contentView.convert(matchInContent, to: scrollView)
            let viewportHeight = scrollView.bounds.height
            let inset = Swift.min(viewportHeight * 0.3, 120)
            let desired = matchInScroll.minY - inset
            let lowest = pageInScroll.minY
            let highest = Swift.max(pageInScroll.minY, pageInScroll.maxY - viewportHeight)
            let targetY = clampedContentOffsetY(
                Swift.min(Swift.max(desired, lowest), highest)
            )

            scrollView.setContentOffset(
                CGPoint(x: horizontalOffset(toReveal: matchInScroll), y: targetY),
                animated: false
            )
            updateVisiblePages(range: visiblePageRange())
            return true
        }

        /// 매치를 가로로 화면 안에 들이는 오프셋.
        ///
        /// 이미 보이면 **현재 오프셋을 그대로 둔다** — 매치마다 가로 위치를
        /// 재조정하면 같은 단에서 다음 매치로 넘어갈 때 화면이 좌우로 흔들린다.
        /// 보이지 않을 때만 매치를 뷰포트 가운데로 가져온다.
        internal func horizontalOffset(toReveal rect: CGRect) -> CGFloat {
            let current = scrollView.contentOffset.x
            let width = scrollView.bounds.width
            guard width > 0 else { return current }
            let visible = current ..< (current + width)
            if rect.minX >= visible.lowerBound, rect.maxX <= visible.upperBound {
                return current
            }
            return clampedContentOffsetX(rect.midX - width / 2)
        }
    }
#endif
