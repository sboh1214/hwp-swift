#if os(macOS)
    import AppKit
    import HwpKitCore

    // MARK: - 키보드 페이지 이동 (#120)

    // PageUp/Down·Home/End 를 쪽 단위 이동으로 해석한다. 진입은 두 갈래다:
    // `keyDown`(`HwpDocumentNSViewSelection.swift` — Cmd+C·Cmd+A 안전망 분기
    // **뒤**에서 `handlePageNavigationKey`를 부른다)과 NSResponder 표준 액션
    // 오버라이드. 표준 액션을 함께 두는 이유는 호스트 메뉴·`doCommand(by:)`
    // 라우팅이 같은 동작에 닿게 하기 위해서다. 뷰가 first responder일 때만
    // 이벤트가 오므로 전역 단축키 규약(#75·`HwpSearchBar`)과 충돌하지 않는다.

    public extension HwpDocumentNSView {
        override func pageUp(_: Any?) {
            movePage(by: -1)
        }

        override func pageDown(_: Any?) {
            movePage(by: 1)
        }

        override func scrollPageUp(_: Any?) {
            movePage(by: -1)
        }

        override func scrollPageDown(_: Any?) {
            movePage(by: 1)
        }

        override func scrollToBeginningOfDocument(_: Any?) {
            scrollToPage(at: 0)
        }

        override func scrollToEndOfDocument(_: Any?) {
            scrollToPage(at: (document?.pages.count ?? 0) - 1)
        }

        /// `keyDown`의 페이지 이동 분기 — 처리했으면 true, 아니면 false를 줘
        /// 이벤트가 responder 체인(호스트)으로 흘러가게 한다. 수식키가 붙은
        /// 조합(Cmd+End·Shift+PageDown 등)과 쪽이 없는 문서의 키는 호스트
        /// 몫으로 남긴다 — 아무것도 안 할 이벤트를 "처리했다"고 삼키지 않고,
        /// 수식키 경계는 iOS `UIKeyCommand`(수식키 없음 매칭)와 같다.
        internal func handlePageNavigationKey(with event: NSEvent) -> Bool {
            guard isKeyboardPageNavigationEnabled,
                  document?.pages.isEmpty == false,
                  event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
                  let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first
            else { return false }
            switch Int(scalar.value) {
            case NSPageUpFunctionKey:
                pageUp(nil)
            case NSPageDownFunctionKey:
                pageDown(nil)
            case NSHomeFunctionKey:
                scrollToBeginningOfDocument(nil)
            case NSEndFunctionKey:
                scrollToEndOfDocument(nil)
            default:
                return false
            }
            return true
        }

        /// 목표 인덱스의 유효 범위 클램프는 `scrollToPage`가 이미 소유한다 (#24)
        /// — 빈 문서 가드까지 그쪽에 있어 표준 액션은 언제 불려도 트랩이 없다.
        private func movePage(by delta: Int) {
            scrollToPage(at: currentVisiblePage() + delta)
        }
    }
#endif
