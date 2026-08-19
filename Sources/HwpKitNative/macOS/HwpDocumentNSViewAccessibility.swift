#if os(macOS)
    import AppKit
    import HwpKitCore

    /// 합성 텍스트 접근성 요소 (#79). 프레임은 **질의 시점**에 콘텐츠 뷰
    /// 좌표를 화면 좌표로 변환한다 — 스크롤·magnification 이 요소를 다시
    /// 만들지 않아도 VoiceOver 가 언제나 현재 위치를 받는다.
    final class HwpTextAccessibilityElement: NSAccessibilityElement {
        /// 콘텐츠 뷰 로컬 top-down rect (페이지/패널 레이어 frame origin 반영).
        /// `HwpFlippedContentView` 가 flipped 라 페이지 좌표계를 그대로 쓴다.
        var contentRect: CGRect = .zero
        weak var contentView: NSView?

        override func accessibilityFrame() -> NSRect {
            guard let contentView, let window = contentView.window else { return .zero }
            return window.convertToScreen(contentView.convert(contentRect, to: nil))
        }
    }

    extension HwpDocumentNSView {
        /// 가시 페이지의 합성 AX 요소를 레이어 가상화 (`updateVisiblePages`) 와
        /// 동기로 재생성·청소한다. 문서 교체는 didSet 이 store 를 전량 비워
        /// stale 라벨을 막고, 여기는 실체화된 페이지만 다시 만든다.
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
            // 콘텐츠 뷰가 AX 그룹으로 요소를 낸다 — 대입은 재생성 여부와
            // 무관하게 매번 한다 (prune 만 돈 호출도 목록이 줄어야 한다).
            documentContentView.setAccessibilityElement(true)
            documentContentView.setAccessibilityRole(.group)
            documentContentView.setAccessibilityChildren(accessibilityStore.flattenedInPageOrder)
            evictAccessibilityUnitCache()
        }

        /// AX 합성이 채운 단위 캐시를 유지 창으로 상한한다 — 축출 훅은 검색이
        /// 소유하므로 (#75) 검색이 없을 때만 직접 부른다. 없으면 스크롤만으로
        /// 1,030쪽 문서의 단위 전개 전량이 상주한다 (선택·검색은 캐시 미스 시
        /// 재계산하므로 정확성 무영향). 검색이 붙어 있으면 updateVisiblePages
        /// 끝의 evictUnitsOutsideRetainedRange 가 같은 창으로 자른다.
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
        ) -> [HwpTextAccessibilityElement] {
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
        ) -> HwpTextAccessibilityElement {
            let element = HwpTextAccessibilityElement()
            element.setAccessibilityElement(true)
            // AppKit 에는 헤딩 role 이 없어 (iOS `.header` trait 대응 부재)
            // 개요 제목도 staticText 로 낸다 — 낭독 대상은 value 다.
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityValue(unit.label)
            element.setAccessibilityParent(documentContentView)
            element.contentView = documentContentView
            element.contentRect = unit.rect.offsetBy(dx: origin.x, dy: origin.y)
            return element
        }
    }
#endif
