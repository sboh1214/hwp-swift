#if os(macOS)
    import AppKit
    import HwpKitCore

    // MARK: - 텍스트 드래그 선택 + 복사

    public extension HwpDocumentNSView {
        override var acceptsFirstResponder: Bool {
            true
        }

        // MARK: 마우스 입력 — 하이퍼링크 click recognizer는 이동 없는

        // 클릭에서만 발화하므로 드래그 선택과 자연 공존한다.

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            guard let position = selectionPosition(for: event) else {
                selectionController.clear()
                super.mouseDown(with: event)
                return
            }
            if event.clickCount >= 2 {
                selectionController.selectWord(at: position)
            } else {
                selectionController.clear()
                selectionController.begin(at: position)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            // 뷰포트 밖 드래그는 클립 뷰가 스크롤을 따라온다
            documentContentView.autoscroll(with: event)
            guard let position = selectionPosition(for: event) else { return }
            selectionController.extend(to: position)
        }

        override func mouseUp(with event: NSEvent) {
            if let selection = selectionController.selection, selection.isCollapsed {
                selectionController.clear()
            }
            super.mouseUp(with: event)
        }

        private func selectionPosition(for event: NSEvent) -> HwpTextPosition? {
            let contentPoint = documentContentView.convert(event.locationInWindow, from: nil)
            guard let (pageIndex, pagePoint) = pagePosition(nearest: contentPoint)
            else { return nil }
            return selectionController.geometry?
                .position(nearest: pagePoint, pageIndex: pageIndex)
        }

        // MARK: 복사

        @objc func copy(_: Any?) {
            copySelectionToPasteboard()
        }

        @discardableResult
        internal func copySelectionToPasteboard() -> Bool {
            guard let text = selectionController.selectedText() else { return false }
            pasteboard.clearContents()
            // 평문 표현형은 그대로 두고 같은 항목에 RTF를 병기한다 (#118).
            // 직렬화가 실패해도 평문 복사는 살아야 하므로 RTF는 조건 추가다.
            pasteboard.setString(text, forType: .string)
            if let attributed = selectionController.selectedAttributedText(),
               let rtf = HwpSelectionRTF.rtfData(from: attributed)
            {
                pasteboard.setData(rtf, forType: .rtf)
            }
            return true
        }

        // MARK: 전체 선택 — NSResponder 표준 액션 (Edit 메뉴가 있는 호스트는

        // 자동 라우팅, 없는 호스트는 keyDown Cmd+A 보험)

        override func selectAll(_: Any?) {
            selectionController.selectAll()
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c",
               copySelectionToPasteboard()
            {
                return
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "a"
            {
                selectAll(nil)
                return
            }
            // Cmd 분기 **뒤**다 — 페이지 이동은 무수식 키만 받으므로 순서가
            // 동작을 바꾸지는 않지만, 위 두 분기의 안전망 성격(주석 참조)을
            // 유지하려고 배치를 고정한다 (#120, 구현은 Keyboard 확장).
            if handlePageNavigationKey(with: event) {
                return
            }
            super.keyDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard selectionController.hasSelection else { return super.menu(for: event) }
            let menu = NSMenu()
            menu.addItem(
                withTitle: NSLocalizedString("Copy", comment: ""),
                action: #selector(copy(_:)),
                keyEquivalent: ""
            )
            return menu
        }

        // MARK: 하이라이트 오버레이 — 페이지 레이어의 sublayer로 부착해

        // 조상 flip 기하를 상속한다 (top-down rect 직접 대입, 자체 flip 금지)

        internal func updateSelectionOverlays() {
            HwpDocumentViewSupport.updateSelectionOverlays(
                pageLayers: pageLayers,
                selectionLayers: &selectionLayers,
                highlightRects: selectionController.highlightRects(forPage:),
                fillColor: NSColor.selectedTextBackgroundColor
                    .withAlphaComponent(0.4).cgColor
            )
        }
    }
#endif
