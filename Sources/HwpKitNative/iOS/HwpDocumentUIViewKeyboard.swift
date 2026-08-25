#if os(iOS)
    import HwpKitCore
    import UIKit

    // MARK: - 하드웨어 키보드 페이지 이동 (#120)

    // PageUp/Down·Home/End 를 쪽 단위 이동으로 해석한다. `UIKeyCommand`는
    // 뷰가 first responder 체인에 있을 때만 발화하므로 전역 단축키 규약
    // (#75·`HwpSearchBar`)과 충돌하지 않는다 — 포커스 획득 경로는 탭·롱프레스
    // 두 사용자 제스처뿐이다 (`handleTap`·`handleLongPress`). 호스트 검색
    // 필드가 포커스를 가진 동안 이 키들이 죽는 것은 결함이 아니라 그 규약의
    // 값이다.

    extension HwpDocumentUIView {
        override public var keyCommands: [UIKeyCommand]? {
            let inherited = super.keyCommands ?? []
            guard isKeyboardPageNavigationEnabled, document?.pages.isEmpty == false
            else { return inherited }
            let commands = [
                (UIKeyCommand.inputPageUp, #selector(pageUpKeyPressed)),
                (UIKeyCommand.inputPageDown, #selector(pageDownKeyPressed)),
                (UIKeyCommand.inputHome, #selector(homeKeyPressed)),
                (UIKeyCommand.inputEnd, #selector(endKeyPressed)),
            ].map { input, action in
                let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
                // 시스템(스크롤 뷰 키보드 스크롤)이 같은 키를 뷰포트 단위로
                // 굴리지 않도록 쪽 단위 해석이 이긴다.
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
            return commands + inherited
        }

        // 토글은 발행(`keyCommands`)뿐 아니라 **실행 시점에도** 선다. 발행만
        // 게이트하면 동작이 "UIKit이 명령을 언제 다시 묻는가"에 의존하는데,
        // `keyCommands`에는 짝이 되는 무효화 API가 없어 그 시점이 계약이 아니다.
        // macOS가 이벤트마다 토글을 보는 것(`handlePageNavigationKey`)과 같다.

        @objc func pageUpKeyPressed() {
            movePage(by: -1)
        }

        @objc func pageDownKeyPressed() {
            movePage(by: 1)
        }

        @objc func homeKeyPressed() {
            guard isKeyboardPageNavigationEnabled else { return }
            scrollToPage(at: 0)
        }

        @objc func endKeyPressed() {
            guard isKeyboardPageNavigationEnabled else { return }
            scrollToPage(at: (document?.pages.count ?? 0) - 1)
        }

        /// 목표 인덱스의 유효 범위 클램프·빈 문서 가드는 `scrollToPage`가
        /// 이미 소유한다 (#4) — macOS `movePage(by:)`와 같은 계약.
        private func movePage(by delta: Int) {
            guard isKeyboardPageNavigationEnabled else { return }
            scrollToPage(at: currentVisiblePage() + delta)
        }

        /// 탭이 포커스를 가져와야 문서를 연 직후에도 하드웨어 키보드로 쪽을
        /// 넘길 수 있다 (`handleTap`이 부른다). first responder는 탭·롱프레스
        /// 같은 사용자 제스처로만 잡는다 — 문서 대입·창 부착에서 스스로 잡으면
        /// 호스트 검색 필드의 포커스를 뺏는 전역 동작이 된다.
        func grabKeyboardFocusOnUserTap() {
            guard isKeyboardPageNavigationEnabled else { return }
            becomeFirstResponder()
        }
    }
#endif
