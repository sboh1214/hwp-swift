#if os(iOS)
    import HwpKitCore
    import UIKit

    // MARK: - 텍스트 롱프레스 선택 + 복사

    extension HwpDocumentUIView {
        override public var canBecomeFirstResponder: Bool {
            true
        }

        func configureSelectionInteractions() {
            let longPress = UILongPressGestureRecognizer(
                target: self, action: #selector(handleLongPress(_:))
            )
            contentView.addGestureRecognizer(longPress)
            let editMenu = UIEditMenuInteraction(delegate: nil)
            contentView.addInteraction(editMenu)
            editMenuInteraction = editMenu
            selectionController.onSelectionChanged = { [weak self] in
                self?.updateSelectionOverlays()
            }
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: contentView)
            switch gesture.state {
            case .began:
                becomeFirstResponder()
                guard let position = selectionPosition(at: location) else { return }
                selectionController.selectWord(at: position)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .changed:
                // 손가락이 뷰포트 엣지 존에 머물면 정지 상태에서도 스크롤이
                // 이어지도록 뷰포트 좌표를 기억하고 링크를 돌린다
                selectionAutoscrollViewportPoint = gesture.location(in: self)
                updateSelectionAutoscroll()
                guard let position = selectionPosition(at: location) else { return }
                selectionController.extend(to: position)
            case .ended, .cancelled:
                stopSelectionAutoscroll()
                presentEditMenuIfNeeded(at: location)
            default:
                break
            }
        }

        // MARK: 엣지 오토스크롤 — 화면 밖으로 선택 확장

        /// 뷰포트 상/하단 엣지 존 (44pt) 침투 깊이에 비례한 프레임당 스크롤
        /// 스텝. 존 밖은 0, 최대 ±12pt. 순수 함수 — 유닛 테스트 대상.
        static func autoscrollStep(
            forLocationY locationY: CGFloat,
            boundsHeight: CGFloat
        ) -> CGFloat {
            let zone: CGFloat = 44
            let maxStep: CGFloat = 12
            guard boundsHeight > zone * 2 else { return 0 }
            if locationY < zone {
                return -maxStep * min(1, (zone - locationY) / zone)
            }
            if locationY > boundsHeight - zone {
                return maxStep * min(1, (locationY - (boundsHeight - zone)) / zone)
            }
            return 0
        }

        private func updateSelectionAutoscroll() {
            guard let point = selectionAutoscrollViewportPoint,
                  Self.autoscrollStep(
                      forLocationY: point.y, boundsHeight: bounds.height
                  ) != 0
            else {
                stopSelectionAutoscroll()
                return
            }
            guard selectionAutoscrollLink == nil else { return }
            let link = CADisplayLink(
                target: self,
                selector: #selector(selectionAutoscrollTick(_:))
            )
            link.add(to: .main, forMode: .common)
            selectionAutoscrollLink = link
        }

        func stopSelectionAutoscroll() {
            selectionAutoscrollLink?.invalidate()
            selectionAutoscrollLink = nil
            selectionAutoscrollViewportPoint = nil
        }

        /// 인셋(안전영역+센터링) 반영 세로 오프셋 클램프. 유효 범위는
        /// [-adjustedContentInset.top, contentSize.height − bounds.height + bottom] —
        /// zero-based 클램프는 센터링된 짧은 문서를 센터 밖으로 밀거나 참 top에
        /// 못 닿게 한다 (R40 #2).
        func clampedContentOffsetY(_ y: CGFloat) -> CGFloat {
            let inset = scrollView.adjustedContentInset
            let minY = -inset.top
            let scrollableY = scrollView.contentSize.height - scrollView.bounds.height
            let maxY = max(minY, scrollableY + inset.bottom)
            return min(max(minY, y), maxY)
        }

        @objc private func selectionAutoscrollTick(_: CADisplayLink) {
            guard let point = selectionAutoscrollViewportPoint else {
                stopSelectionAutoscroll()
                return
            }
            let step = Self.autoscrollStep(
                forLocationY: point.y, boundsHeight: bounds.height
            )
            guard step != 0 else {
                stopSelectionAutoscroll()
                return
            }
            let targetY = clampedContentOffsetY(scrollView.contentOffset.y + step)
            guard targetY != scrollView.contentOffset.y else { return }
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: targetY)
            // 정지한 손가락 아래의 새 콘텐츠 좌표로 선택을 계속 확장한다
            // (convert가 줌 transform을 반영한다)
            let contentPoint = contentView.convert(point, from: self)
            if let position = selectionPosition(at: contentPoint) {
                selectionController.extend(to: position)
            }
        }

        private func selectionPosition(at contentPoint: CGPoint) -> HwpTextPosition? {
            guard let (pageIndex, pagePoint) = pagePositionNearest(contentPoint)
            else { return nil }
            return selectionController.geometry?
                .position(nearest: pagePoint, pageIndex: pageIndex)
        }

        /// 콘텐츠 좌표를 가장 가까운 페이지로 클램프 (페이지 gap에서도 결과 보장)
        private func pagePositionNearest(
            _ contentPoint: CGPoint
        ) -> (pageIndex: Int, point: CGPoint)? {
            guard let document, !document.pages.isEmpty else { return nil }
            let pageCount = document.pages.count
            var candidate = pageCount - 1
            for index in 0 ..< pageCount where selectionPageFrame(at: index).maxY >= contentPoint.y {
                candidate = index
                break
            }
            let frame = selectionPageFrame(at: candidate)
            return (candidate, CGPoint(
                x: contentPoint.x - frame.minX,
                y: contentPoint.y - frame.minY
            ))
        }

        private func presentEditMenuIfNeeded(at point: CGPoint) {
            guard selectionController.hasSelection else { return }
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
            editMenuInteraction?.presentEditMenu(with: configuration)
        }

        // MARK: 복사

        override public func canPerformAction(
            _ action: Selector, withSender sender: Any?
        ) -> Bool {
            if action == #selector(copy(_:)) {
                return selectionController.hasSelection
            }
            if action == #selector(selectAll(_:)) {
                return document != nil
            }
            return super.canPerformAction(action, withSender: sender)
        }

        override public func copy(_: Any?) {
            guard let text = selectionController.selectedText() else { return }
            UIPasteboard.general.string = text
        }

        /// 편집 메뉴 Select All / 하드웨어 키보드 Cmd+A
        override public func selectAll(_: Any?) {
            selectionController.selectAll()
        }

        // MARK: 하이라이트 오버레이 — 페이지 레이어의 sublayer (페이지 로컬 rect)

        func updateSelectionOverlays() {
            HwpDocumentViewSupport.updateSelectionOverlays(
                pageLayers: pageLayers,
                selectionLayers: &selectionLayers,
                highlightRects: selectionController.highlightRects(forPage:),
                fillColor: UIColor.systemBlue.withAlphaComponent(0.3).cgColor
            )
        }
    }
#endif
