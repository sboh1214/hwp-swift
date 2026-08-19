#if os(iOS)
    import CoreGraphics
    import HwpKitCore
    import UIKit

    // MARK: - fit 배율 (#78)

    /// macOS `HwpDocumentNSViewZoom.swift`와 대칭 — 산식은 두 플랫폼이
    /// `HwpDocumentViewSupport.fitZoomScale` 하나를 공유하고, 여기서는 그 산식에
    /// 넘길 캔버스·뷰포트를 고르는 일만 한다.
    extension HwpDocumentUIView {
        /// 배율을 뷰포트에 맞춘다 — 즉시 적용했으면 true.
        ///
        /// SwiftUI `makeUIView`는 bounds 0에서 배선하므로 이 경로가 실제로 밟힌다:
        /// 그때 온 요청은 예약만 하고 첫 실측 `layoutSubviews`에서 적용된다.
        /// 문서가 없을 때도 마찬가지다 — 0쪽 문서에서 `updateContentSize()`가
        /// 캔버스에 `defaultPageSize.width` 하한을 세우므로, 가드가 없으면 산식이
        /// "유령 A4"에 맞춘 배율을 성공으로 돌려주고 진짜 문서가 도착해도 원샷이라
        /// 다시 맞추지 않는다 (macOS 와 같은 가드).
        ///
        /// 뷰포트로 `scrollView.bounds` 가 아니라 **뷰 본체의 `bounds`** 를 쓴다.
        /// 스크롤 뷰는 제약도 오토리사이즈 마스크도 없이 `layoutSubviews` 에서만
        /// 프레임을 받으므로, 크기가 바뀐 직후 레이아웃 전에 들어온 요청은 낡은
        /// 폭으로 "성공"해 재시도조차 돌지 않는다. 본체 bounds 는 프레임 대입과
        /// 동시에 갱신되고 스크롤 뷰는 언제나 그것을 가득 채운다
        /// (`visiblePageRange()` 도 같은 폴백을 쓴다).
        ///
        /// 기준 폭은 **문서 전체 스크롤 캔버스**(`contentView.bounds`)다 —
        /// 현재 쪽 폭으로 잡으면 더 넓은 구역이 하나라도 있을 때 가로 스크롤이
        /// 남는다. 캔버스 폭은 `updateContentSize()`가 메모 패널까지 포함해 잡는다.
        /// macOS와 달리 여기에는 595pt 하한이 없어, 그보다 좁은 문서에서는 두
        /// 플랫폼의 배율이 갈린다 (각자 실제로 스크롤되는 것에 맞춘 결과다).
        @discardableResult
        public func applyFitZoom(_ fit: HwpZoomFit) -> Bool {
            guard let document, !document.pages.isEmpty else {
                pendingFitZoom = fit
                return false
            }
            let pageIndex = currentVisiblePage()
            guard let scale = HwpDocumentViewSupport.fitZoomScale(
                content: CGSize(
                    width: contentView.bounds.width,
                    height: rowHeight(at: pageIndex)
                ),
                viewport: bounds.size,
                fit: fit,
                range: zoomRange
            ) else {
                pendingFitZoom = fit
                return false
            }
            pendingFitZoom = nil
            zoomScale = scale
            // 쪽 맞춤은 그 쪽이 **통째로 보인다**는 약속이라 배율만으로는 반쪽이다.
            // 폭 맞춤은 스크롤을 건드리지 않는다 (macOS와 같은 규약).
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
        /// 않는다. 뒤집힌 한계는 정렬로, 비-finite 는 리셋 기본값으로 접어
        /// `ClosedRange` 생성 트랩을 막는다 (macOS 와 같은 규약).
        var zoomRange: ClosedRange<CGFloat> {
            let lower = scrollView.minimumZoomScale
            let upper = scrollView.maximumZoomScale
            guard lower.isFinite, upper.isFinite else { return 1.0 ... 1.0 }
            return min(lower, upper) ... max(lower, upper)
        }
    }
#endif
