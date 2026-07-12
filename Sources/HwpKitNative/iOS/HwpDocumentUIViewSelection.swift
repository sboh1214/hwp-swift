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
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let targetY = min(maxOffsetY, max(0, scrollView.contentOffset.y + step))
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
            return super.canPerformAction(action, withSender: sender)
        }

        override public func copy(_: Any?) {
            guard let text = selectionController.selectedText() else { return }
            UIPasteboard.general.string = text
        }

        // MARK: 하이라이트 오버레이 — 페이지 레이어의 sublayer (페이지 로컬 rect)

        func updateSelectionOverlays() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (pageIndex, pageLayer) in pageLayers {
                let rects = selectionController.highlightRects(forPage: pageIndex)
                if rects.isEmpty {
                    selectionLayers[pageIndex]?.removeFromSuperlayer()
                    selectionLayers[pageIndex] = nil
                    continue
                }
                let overlay = selectionLayers[pageIndex] ?? {
                    let layer = CAShapeLayer()
                    layer.fillColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
                    selectionLayers[pageIndex] = layer
                    return layer
                }()
                if overlay.superlayer !== pageLayer {
                    overlay.removeFromSuperlayer()
                    pageLayer.addSublayer(overlay)
                }
                overlay.frame = pageLayer.bounds
                let path = CGMutablePath()
                for rect in rects {
                    path.addRect(rect)
                }
                overlay.path = path
            }
            for (pageIndex, overlay) in selectionLayers where pageLayers[pageIndex] == nil {
                overlay.removeFromSuperlayer()
                selectionLayers[pageIndex] = nil
            }
            CATransaction.commit()
        }
    }
#endif
