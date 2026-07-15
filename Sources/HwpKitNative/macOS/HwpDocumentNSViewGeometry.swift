#if os(macOS)
    import AppKit
    import CoreGraphics
    import HwpKitCore

    // MARK: - 콘텐츠 지오메트리 (문서 좌표계 — magnification과 무관)

    extension HwpDocumentNSView {
        func rebuildPageOrigins() {
            var origins: [CGFloat] = []
            var originY: CGFloat = 0
            var maxRowWidth = defaultPageSize.width
            for index in 0 ..< (document?.pages.count ?? 0) {
                origins.append(originY)
                originY += rowHeight(at: index) + pageGap
                maxRowWidth = max(maxRowWidth, rowWidth(at: index))
            }
            pageOriginsY = origins
            cachedContentWidth = maxRowWidth
        }

        func updateContentSize() {
            let pageCount = document?.pages.count ?? 0
            let totalHeight = (0 ..< pageCount).reduce(CGFloat(0)) { partial, index in
                partial + rowHeight(at: index) + (index == pageCount - 1 ? 0 : pageGap)
            }
            let size = CGSize(
                width: max(contentWidth(), defaultPageSize.width),
                height: max(totalHeight, rowHeight(at: 0))
            )
            documentContentView.frame = CGRect(origin: .zero, size: size)
        }

        /// 메모 패널이 페이지 오른쪽 바깥에 그려지므로 콘텐츠 폭에 패널 폭을
        /// 포함해야 클립 뷰에 잘리지 않는다. rebuildPageOrigins에서 캐시된 값을
        /// 돌려줘 스크롤마다 전 페이지를 다시 훑지 않는다 (#27).
        func contentWidth() -> CGFloat {
            cachedContentWidth
        }

        func rowWidth(at index: Int) -> CGFloat {
            let pageWidth = sizeForPage(at: index).width
            guard let document, document.pages.indices.contains(index),
                  let panel = document.pages[index].memoPanel
            else { return pageWidth }
            return pageWidth + panel.width
        }

        /// 메모 패널이 페이지보다 길면 그 높이로 행을 잡아 다음 행과 겹치거나
        /// 마지막 페이지 오버플로가 스크롤 밖으로 나가지 않게 한다 (#4).
        func rowHeight(at index: Int) -> CGFloat {
            let pageHeight = sizeForPage(at: index).height
            guard let document, document.pages.indices.contains(index),
                  let panel = document.pages[index].memoPanel
            else { return pageHeight }
            return max(pageHeight, panel.contentHeight)
        }

        func frameForPage(at index: Int) -> CGRect {
            let size = sizeForPage(at: index)
            // 문서가 없거나 범위 밖이면 (플레이스홀더 경로) 균등 간격으로
            // 누적 배치해 어떤 경로에서도 페이지가 겹치지 않게 한다.
            let originY = pageOriginsY.indices.contains(index)
                ? pageOriginsY[index]
                : CGFloat(index) * (defaultPageSize.height + pageGap)
            let originX = max((contentWidth() - rowWidth(at: index)) / 2, 0)
            return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
        }

        func frameCount() -> Int {
            pageOriginsY.count
        }

        /// 콘텐츠 좌표의 점을 가장 가까운 페이지로 클램프해 (페이지 인덱스,
        /// 페이지 로컬 점)으로 변환한다. `pageHit`과 달리 페이지 사이
        /// 간격·여백에서도 항상 결과를 준다 (드래그 선택용).
        func pagePosition(nearest contentPoint: CGPoint) -> (pageIndex: Int, point: CGPoint)? {
            guard let document, !document.pages.isEmpty else { return nil }
            let pageCount = document.pages.count
            // pageOriginsY 오름차순 — y가 속하거나 가장 가까운 페이지를 찾는다
            var low = 0
            var high = pageCount - 1
            var candidate = pageCount - 1
            while low <= high {
                let mid = (low + high) / 2
                if frameForPage(at: mid).maxY >= contentPoint.y {
                    candidate = mid
                    high = mid - 1
                } else {
                    low = mid + 1
                }
            }
            let frame = frameForPage(at: candidate)
            return (candidate, CGPoint(
                x: contentPoint.x - frame.minX,
                y: contentPoint.y - frame.minY
            ))
        }

        /// `documentVisibleRect`는 magnification이 반영된 문서 좌표계라
        /// 줌 상태와 무관하게 페이지 프레임과 직접 교차 검사할 수 있다.
        func visiblePageRange() -> Range<Int> {
            guard let document, !document.pages.isEmpty else { return 0 ..< 0 }
            let pageCount = document.pages.count
            let visible = scrollView.documentVisibleRect
            guard visible.height > 0 else { return 0 ..< min(pageCount, 1) }

            // pageOriginsY는 오름차순 — 첫 가시 페이지를 이진 탐색한다
            // (legacy 1,030쪽 문서에서 스크롤 프레임마다 호출되므로)
            var low = 0
            var high = pageCount - 1
            var first = pageCount
            while low <= high {
                let mid = (low + high) / 2
                if frameForPage(at: mid).maxY > visible.minY {
                    first = mid
                    high = mid - 1
                } else {
                    low = mid + 1
                }
            }
            guard first < pageCount else { return (pageCount - 1) ..< pageCount }

            var last = first
            while last + 1 < pageCount, frameForPage(at: last + 1).minY < visible.maxY {
                last += 1
            }
            return first ..< (last + 1)
        }

        func sizeForPage(at index: Int) -> CGSize {
            guard let document, document.pages.indices.contains(index) else {
                return defaultPageSize
            }
            return document.pages[index].size
        }
    }
#endif
