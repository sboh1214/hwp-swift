#if os(iOS)
    import HwpKitCore
    import UIKit

    extension HwpDocumentUIView {
        /// 가시 페이지의 합성 AX 요소를 레이어 가상화 (`updateVisiblePages`) 와
        /// 동기로 재생성·청소한다 (macOS 와 같은 계약). 문서 교체는 didSet 이
        /// store 를 전량 비워 stale 라벨을 막는다.
        ///
        /// 프레임은 `accessibilityFrameInContainerSpace` 로 컨테이너
        /// (`contentView`) 좌표에 두므로 스크롤·줌 변환은 UIKit 이 질의
        /// 시점에 반영한다 — zoomScale 역보정 산식이 필요 없다 (줌 transform 은
        /// `viewForZooming` 인 contentView 에 걸린다).
        func updateAccessibilityElements() {
            accessibilityStore.prune(keeping: pageLayers.keys)
            for (pageIndex, pageLayer) in pageLayers
                where accessibilityStore.elements(
                    forPage: pageIndex, anchoredTo: pageLayer.frame
                ) == nil
            {
                accessibilityStore.setElements(
                    makeAccessibilityElements(pageIndex: pageIndex, pageFrame: pageLayer.frame),
                    forPage: pageIndex,
                    anchoredTo: pageLayer.frame
                )
            }
            // 대입은 재생성 여부와 무관하게 매번 한다 (prune 만 돈 호출도
            // 목록이 줄어야 한다).
            contentView.accessibilityElements = accessibilityStore.flattenedInPageOrder
            evictAccessibilityUnitCache()
        }

        /// AX 합성이 채운 단위 캐시를 유지 창으로 상한한다 — 축출 훅은 검색이
        /// 소유하므로 (#75) 검색이 없을 때만 직접 부른다 (macOS 와 같은 계약,
        /// 근거는 그쪽 주석).
        private func evictAccessibilityUnitCache() {
            guard searchController == nil,
                  let geometry = selectionController.geometry,
                  let lower = pageLayers.keys.min(),
                  let upper = pageLayers.keys.max()
            else { return }
            geometry.evictUnits(keeping: lower ..< (upper + 1))
        }

        private func makeAccessibilityElements(
            pageIndex: Int, pageFrame: CGRect
        ) -> [UIAccessibilityElement] {
            let models = HwpDocumentAccessibility.units(
                document: document,
                pageIndex: pageIndex,
                bodyUnits: selectionController.geometry?.units(forPage: pageIndex)
            )
            var elements = models.page.map { makeElement($0, offsetBy: pageFrame.origin) }
            if let panelFrame = memoPanelLayers[pageIndex]?.frame {
                elements += models.memo.map { makeElement($0, offsetBy: panelFrame.origin) }
            }
            return elements
        }

        private func makeElement(
            _ unit: HwpAccessibilityUnit, offsetBy origin: CGPoint
        ) -> UIAccessibilityElement {
            let element = UIAccessibilityElement(accessibilityContainer: contentView)
            element.accessibilityLabel = unit.label
            // 개요 제목은 헤딩 트레이트 — VoiceOver 로터 "제목" 탐색 재료 (#77).
            element.accessibilityTraits = unit.isHeading
                ? [.staticText, .header]
                : .staticText
            element.accessibilityFrameInContainerSpace =
                unit.rect.offsetBy(dx: origin.x, dy: origin.y)
            return element
        }
    }
#endif
