#if os(macOS)
    import AppKit
    import CoreGraphics
    import HwpKitCore

    // MARK: - fit 배율 (#78)

    extension HwpDocumentNSView {
        /// 배율을 뷰포트에 맞춘다 — 즉시 적용했으면 true.
        ///
        /// 문서가 없거나 뷰포트·캔버스가 아직 실측되지 않았으면(창에 붙기 전)
        /// 예약만 하고 false를 돌려준다. 예약분은 첫 실측 `layout()`과 문서 대입
        /// 끝에서 적용된다 — iOS `pendingInitialCentering`과 같은 형태다. 조용히
        /// 무시하면 호스트가 "문서를 열자마자 폭 맞춤"을 걸어 둘 수 없다.
        ///
        /// **문서 가드가 따로 있는 이유**: 0쪽 문서에서도 캔버스에 하한(595)이
        /// 서므로 산식만으로는 "유령 A4"에 맞춘 배율이 성공으로 나간다. 원샷이라
        /// 재적용 경로가 없어, 진짜 문서가 도착해도 그 배율이 그대로 남는다.
        ///
        /// 기준 폭은 **문서 전체 스크롤 캔버스**(`documentContentView`)다. 현재
        /// 페이지 폭으로 잡으면 더 넓은 구역이 하나라도 있을 때 현재 쪽만 맞고
        /// 가로 스크롤은 남는다. 이 캔버스는 `updateContentSize()`가 건 595pt
        /// 하한을 포함하므로 폭이 그보다 좁은 문서에서는 iOS보다 작은 배율이
        /// 나온다 — fit 의 계약이 "가로 스크롤이 사라진다"인 이상 실제로 스크롤되는
        /// 것을 기준으로 삼는 쪽이 맞다.
        @discardableResult
        public func applyFitZoom(_ fit: HwpZoomFit) -> Bool {
            guard let document, !document.pages.isEmpty else {
                pendingFitZoom = fit
                return false
            }
            let pageIndex = currentVisiblePage()
            guard let scale = HwpDocumentViewSupport.fitZoomScale(
                content: CGSize(
                    width: documentContentView.frame.width,
                    height: rowHeight(at: pageIndex)
                ),
                viewport: scrollView.contentSize,
                fit: fit,
                range: zoomRange
            ) else {
                pendingFitZoom = fit
                return false
            }
            pendingFitZoom = nil
            zoomScale = scale
            // 쪽 맞춤은 그 쪽이 **통째로 보인다**는 약속이라 배율만으로는 반쪽이다 —
            // 배율을 바꾸면 쪽 경계가 뷰포트 밖으로 밀릴 수 있어 그 쪽 위로 옮긴다.
            // 폭 맞춤은 스크롤을 건드리지 않는다 (배율 setter가 뷰포트 중심을 유지).
            if fit == .page {
                scrollToPage(at: pageIndex)
            }
            return true
        }

        /// 예약된 fit 을 실측 레이아웃에서 한 번 적용한다. 아직도 못 맞추면
        /// `applyFitZoom` 이 다시 예약하므로 다음 레이아웃에서 재시도한다.
        func applyPendingFitZoom() {
            guard let fit = pendingFitZoom else { return }
            applyFitZoom(fit)
        }

        /// 스크롤 뷰가 실제로 허용하는 배율 범위 — `0.25...5.0`의 사본을 늘리지
        /// 않는다.
        ///
        /// `NSScrollView`의 두 한계는 공개 프로퍼티라 호스트가 무엇이든 넣을 수
        /// 있고 `ClosedRange` 생성은 `lower <= upper` 위반에 **트랩**한다. 뒤집힌
        /// 값은 정렬로, 비-finite 는 `Swift.min/max`가 NaN 을 그대로 통과시키므로
        /// 리셋 기본값 하나로 접어 막는다 (공개 수치 인자는 트랩하지 않는다는 규약).
        var zoomRange: ClosedRange<CGFloat> {
            let lower = scrollView.minMagnification
            let upper = scrollView.maxMagnification
            guard lower.isFinite, upper.isFinite else { return 1.0 ... 1.0 }
            return min(lower, upper) ... max(lower, upper)
        }
    }
#endif
