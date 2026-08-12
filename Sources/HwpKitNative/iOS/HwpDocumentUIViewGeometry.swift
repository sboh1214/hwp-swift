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

        func expandedRange(_ range: Range<Int>) -> Range<Int> {
            guard !range.isEmpty else { return range }
            let pageCount = document?.pages.count ?? 0
            let lower = max(0, range.lowerBound - 2)
            let upper = min(pageCount, range.upperBound + 2)
            return lower ..< upper
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
