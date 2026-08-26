#if os(iOS)
    import HwpKitCore
    import UIKit
    import UniformTypeIdentifiers

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
            selectionInteraction.editMenuInteraction = editMenu
            configureSelectionHandles()
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
                selectionInteraction.autoscrollViewportPoint = gesture.location(in: self)
                updateSelectionAutoscroll()
                guard let position = selectionPosition(at: location) else { return }
                selectionController.extend(to: position)
            case .ended, .cancelled:
                stopSelectionAutoscroll()
                guard !clearCollapsedSelection() else { return }
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

        func updateSelectionAutoscroll() {
            guard let point = selectionInteraction.autoscrollViewportPoint,
                  Self.autoscrollStep(
                      forLocationY: point.y, boundsHeight: bounds.height
                  ) != 0
            else {
                stopSelectionAutoscroll()
                return
            }
            guard selectionInteraction.autoscrollLink == nil else { return }
            let link = CADisplayLink(
                target: self,
                selector: #selector(selectionAutoscrollTick(_:))
            )
            link.add(to: .main, forMode: .common)
            selectionInteraction.autoscrollLink = link
        }

        func stopSelectionAutoscroll() {
            selectionInteraction.autoscrollLink?.invalidate()
            selectionInteraction.autoscrollLink = nil
            selectionInteraction.autoscrollViewportPoint = nil
        }

        /// 끝점이 반대 끝점 위에 정확히 겹치면 범위가 비어 `hasSelection`이
        /// false인데 선택 객체만 남아 오버레이 갱신이 계속 돈다 — macOS
        /// `mouseUp`(`HwpDocumentNSViewSelection.swift`)과 같은 정리다.
        /// 실제로 지웠으면 true.
        @discardableResult
        func clearCollapsedSelection() -> Bool {
            guard selectionController.selection?.isCollapsed == true else { return false }
            selectionController.clear()
            return true
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

        /// 가로판. 넓은 페이지(줌·좁은 화면)에서 검색 매치를 화면 안으로
        /// 들이는 데 쓴다 — 세로만 맞추면 매치가 가로로 화면 밖에 남아,
        /// 사용자에게는 카운터만 바뀌고 아무 일도 안 일어난 것처럼 보인다.
        func clampedContentOffsetX(_ x: CGFloat) -> CGFloat {
            let inset = scrollView.adjustedContentInset
            let minX = -inset.left
            let scrollableX = scrollView.contentSize.width - scrollView.bounds.width
            let maxX = max(minX, scrollableX + inset.right)
            return min(max(minX, x), maxX)
        }

        @objc private func selectionAutoscrollTick(_: CADisplayLink) {
            guard let point = selectionInteraction.autoscrollViewportPoint else {
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

        /// 핸들 드래그(`HwpDocumentUIViewSelectionHandles.swift`)도 부르므로
        /// internal이다 — 직접 다시 구현하면 아래 페이지 이진 탐색·gap 최근접
        /// 판정이 갈라져 macOS와 좌표 규약이 어긋난다.
        func selectionPosition(at contentPoint: CGPoint) -> HwpTextPosition? {
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
            // 페이지 프레임은 y 오름차순 — 첫 (maxY ≥ 점) 페이지를 이진 탐색한다.
            // 만 단위 문서에서 롱프레스/오토스크롤 틱마다 0부터 선형 스캔하지
            // 않는다 (visiblePageRange와 대칭, R64 #2).
            var candidate = pageCount - 1
            var low = 0
            var high = pageCount - 1
            while low <= high {
                let mid = (low + high) / 2
                if selectionPageFrame(at: mid).maxY >= contentPoint.y {
                    candidate = mid
                    high = mid - 1
                } else {
                    low = mid + 1
                }
            }
            // 점이 candidate 상단보다 위면 (페이지 사이 gap) 인접 두 페이지 거리를
            // 비교해 가까운 쪽을 골라 선택 끝점 점프를 막는다 (macOS와 동일, R52 #1).
            if candidate > 0, contentPoint.y < selectionPageFrame(at: candidate).minY {
                let distanceToPrevious = contentPoint.y - selectionPageFrame(at: candidate - 1).maxY
                let distanceToCurrent = selectionPageFrame(at: candidate).minY - contentPoint.y
                if distanceToPrevious < distanceToCurrent {
                    candidate -= 1
                }
            }
            let frame = selectionPageFrame(at: candidate)
            return (candidate, CGPoint(
                x: contentPoint.x - frame.minX,
                y: contentPoint.y - frame.minY
            ))
        }

        /// 핸들 드래그 `.ended`도 부르므로 internal이다.
        func presentEditMenuIfNeeded(at point: CGPoint) {
            guard selectionController.hasSelection else { return }
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
            selectionInteraction.editMenuInteraction?.presentEditMenu(with: configuration)
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
            guard let attributed = selectionController.selectedAttributedText() else { return }
            // 평문과 RTF를 한 항목의 두 표현형으로 싣는다 (#118). 평문은
            // attributed의 `.string`에서 얻는다 — `selectedText()`를 따로 부르면
            // 같은 값을 얻으려고 선택 전체를 한 번 더 순회한다. RTF 직렬화가
            // 실패해도 평문 복사는 살아야 하므로 RTF는 조건 추가다.
            var item: [String: Any] = [
                UTType.utf8PlainText.identifier: attributed.string,
            ]
            if let rtf = HwpSelectionRTF.rtfData(from: attributed) {
                item[UTType.rtf.identifier] = rtf
            }
            pasteboard.items = [item]
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
            // 끝점 핸들은 페이지 레이어가 아니라 뷰 본체에 붙지만, 갱신 시점은
            // 하이라이트와 정확히 같아야 한다 (#84).
            updateSelectionHandles()
        }
    }
#endif
