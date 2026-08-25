#if os(iOS)
    import CoreGraphics
    import Foundation
    import HwpKitCore
    import UIKit

    /// iOS 뷰의 페이지 지오메트리 — 가시 범위·보존 창·페이지 프레임.
    ///
    /// macOS의 `HwpDocumentNSViewGeometry.swift`와 대칭으로 **internal**이다.
    /// `public extension` 으로 두면 무수식자 멤버가 전부 public 이 되어, 뷰
    /// 본체에서 `private` 이던 가상화 세부가 그대로 공개 API 가 된다.
    extension HwpDocumentUIView {
        func visiblePageRange() -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0 else { return 0 ..< 0 }

            // Convert into content-view coordinates so zooming is accounted for.
            let visibleRect = scrollView.bounds.isEmpty
                ? CGRect(origin: scrollView.contentOffset, size: bounds.size)
                : scrollView.convert(scrollView.bounds, to: contentView)
            // pageOriginsY는 오름차순 — 스크롤 콜백마다 전 페이지를 훑지 않도록
            // 첫 가시 페이지를 이진 탐색한다 (macOS와 대칭, #26).
            var low = 0
            var high = pageCount - 1
            var first = pageCount
            while low <= high {
                let mid = (low + high) / 2
                // 종이 maxY가 아니라 행(종이+메모 패널) 하단으로 판정한다 (#6).
                if frameForPage(at: mid).minY + rowHeight(at: mid) > visibleRect.minY {
                    first = mid
                    high = mid - 1
                } else {
                    low = mid + 1
                }
            }
            // 뷰포트가 마지막 페이지보다 아래(하단 러버밴드/축소)면 마지막
            // 페이지를 유지한다 — page 0을 반환하면 currentPage가 1로 튄다.
            // macOS와 대칭 (#12).
            guard first < pageCount else { return (pageCount - 1) ..< pageCount }
            var last = first
            while last + 1 < pageCount, frameForPage(at: last + 1).minY < visibleRect.maxY {
                last += 1
            }
            return first ..< (last + 1)
        }

        /// 뷰 본체에서 옮겨 왔다 (#120) — 본체가 `type_body_length` error
        /// 임계(400)에 붙어 있어 저장 프로퍼티를 더할 때 헬퍼를 확장으로 빼
        /// 순감시키는 관례다 (`Sources/HwpKitNative/AGENTS.md`).
        func clampedPageRange(_ range: Range<Int>) -> Range<Int> {
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, min(range.lowerBound, pageCount))
            let upper = max(lower, min(range.upperBound, pageCount))
            return lower ..< upper
        }

        func expandedRange(_ range: Range<Int>) -> Range<Int> {
            guard !range.isEmpty else { return range }
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, range.lowerBound - 2)
            let upper = min(pageCount, range.upperBound + 2)
            return lower ..< upper
        }

        /// 스케일된 콘텐츠가 뷰포트보다 작으면 contentInset으로 중앙 정렬한다 —
        /// UIScrollView는 자동 센터링을 안 해 좌상단에 붙는다 (macOS
        /// HwpCenteringClipView와 맞춤). 콘텐츠가 크면 inset 0이라 스크롤 불변.
        /// 줌으로 대소 관계가 바뀔 때도 갱신하므로 헬퍼로 분리한다 (#2, P2).
        func updateCenteringInset() {
            let scaled = scrollView.contentSize
            let insetX = max(0, (scrollView.bounds.width - scaled.width) / 2)
            let insetY = max(0, (scrollView.bounds.height - scaled.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: insetY, left: insetX,
                bottom: max(insetY, trailingScrollExtent(contentHeight: scaled.height)),
                right: insetX
            )
        }

        /// 마지막 쪽도 **첫 가시 쪽**이 될 수 있게 남기는 아래 여유.
        ///
        /// 없으면 문서 전체 최대 오프셋이 마지막 쪽 minY 보다 작아, 매치로
        /// 점프해도 앞 쪽이 첫 가시가 되고 그 쪽이 `currentPage` 로 보고된다
        /// (#75 리뷰). 마지막 쪽이 뷰포트보다 낮을 때만 — 축소했거나 짧은
        /// 쪽일 때다 — 생기고, 모자란 만큼만 준다. 콘텐츠가 뷰포트보다 작으면
        /// 센터링 인셋이 이미 그 역할을 하므로 0이다.
        private func trailingScrollExtent(contentHeight: CGFloat) -> CGFloat {
            let pageCount = document?.pages.count ?? 0
            guard pageCount > 0, contentHeight > scrollView.bounds.height else { return 0 }
            let lastRow = rowHeight(at: pageCount - 1) * scrollView.zoomScale
            return max(0, scrollView.bounds.height - lastRow)
        }

        func frameForPage(at index: Int) -> CGRect {
            let originY = pageOriginsY[safe: index] ?? 0
            // 구역별 용지 폭/메모 패널 폭이 달라 좁은 행은 콘텐츠 폭 안에서
            // 행별로 중앙 정렬한다 — macOS frameForPage와 대칭 (#8).
            let originX = max((contentView.bounds.width - rowWidth(at: index)) / 2, 0)
            return CGRect(origin: CGPoint(x: originX, y: originY), size: pageSize(at: index))
        }
    }
#endif
