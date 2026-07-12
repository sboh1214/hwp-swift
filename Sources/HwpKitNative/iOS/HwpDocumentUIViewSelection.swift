#if os(iOS)
    import HwpKitCore
    import UIKit

    // MARK: - 텍스트 롱프레스 선택 + 복사

    extension HwpDocumentUIView {
        override public var canBecomeFirstResponder: Bool { true }

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
                guard let position = selectionPosition(at: location) else { return }
                selectionController.extend(to: position)
            case .ended, .cancelled:
                presentEditMenuIfNeeded(at: location)
            default:
                break
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
