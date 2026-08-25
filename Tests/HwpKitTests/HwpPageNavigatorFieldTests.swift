#if os(macOS)
    import AppKit
    @testable import HwpKit
    import Nimble
    import SwiftUI
    import XCTest

    /// 쪽 번호 입력 필드(#120)의 SwiftUI 글루 계약 — 초안 동기화, 커밋 전 중간
    /// 값 격리, Enter 커밋, 포커스 상실 되돌림.
    ///
    /// 판정 로직(`commitPageEntry(_:)`)은 `HwpToolsTests`가 뷰 인스턴스로 직접
    /// 부르지만, 그것을 필드에 잇는 `onAppear`/`onChange`/`onSubmit` 글루는
    /// `private`이라 `@testable`로도 닿지 않는다. 그래서 실제로 렌더해 관찰한다
    /// (`HwpSearchIntegrationTests`와 같은 `NSHostingView` 호스팅 관례).
    @MainActor
    final class HwpPageNavigatorFieldTests: XCTestCase {
        /// SwiftUI가 body를 재평가하도록 **관찰 가능한** 소스를 쓴다 —
        /// `Binding(get:set:)`은 변경을 알릴 통로가 없어 `onChange`가 뜨지 않는다.
        private final class PageBox: ObservableObject {
            @Published var page: Int
            init(_ page: Int) {
                self.page = page
            }
        }

        private struct Host: View {
            @ObservedObject var box: PageBox
            let totalPages: Int
            var body: some View {
                HwpPageNavigator(currentPage: $box.page, totalPages: totalPages)
            }
        }

        private struct Rendered {
            let window: NSWindow
            let hosting: NSHostingView<Host>
            let field: NSTextField
        }

        private func pump(_ seconds: TimeInterval = 0.2) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }

        /// 창에 넣되 **화면에 올리지는 않는다** — 포커스 전환에 필요한 것은 창의
        /// first responder 상태뿐이라, WindowServer에 기대는
        /// `makeKeyAndOrderFront`를 부르면 헤드리스 CI에 불필요한 의존이 생긴다.
        private func render(page: Int, totalPages: Int = 5) throws -> (PageBox, Rendered) {
            let box = PageBox(page)
            let hosting = NSHostingView(rootView: Host(box: box, totalPages: totalPages))
            hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 60)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled],
                backing: .buffered,
                defer: true
            )
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            pump()
            let field = try XCTUnwrap(hosting.firstTextFieldSubview())
            return (box, Rendered(window: window, hosting: hosting, field: field))
        }

        /// 필드를 first responder로 만들고 그 필드 편집기를 준다 — 타이핑은
        /// `stringValue` 직접 대입이 아니라 편집기를 거쳐야 바인딩까지 간다.
        private func focus(_ rendered: Rendered) throws -> NSText {
            expect(rendered.window.makeFirstResponder(rendered.field)) == true
            pump()
            return try XCTUnwrap(rendered.field.currentEditor())
        }

        // MARK: - 초안 동기화

        /// `onAppear`가 초안을 현재 쪽으로 맞춘다 — 안 돌면 초기값 `""`이 그대로
        /// 보여 문서를 연 직후 필드가 비어 있다.
        func testFieldStartsAtTheCurrentPage() throws {
            let (_, rendered) = try render(page: 1)

            expect(rendered.field.stringValue) == "1"

            withExtendedLifetime(rendered) {}
        }

        /// 편집 중이 아니면 외부 쪽 변경(스크롤·프로그래매틱 이동)이 필드에 온다.
        func testExternalPageChangeUpdatesTheFieldWhileNotEditing() throws {
            let (box, rendered) = try render(page: 1)

            box.page = 3
            rendered.hosting.layoutSubtreeIfNeeded()
            pump()

            expect(rendered.field.stringValue) == "3"

            withExtendedLifetime(rendered) {}
        }

        // MARK: - 커밋 통로는 Enter 하나

        /// 이 기능의 핵심 계약 — 타이핑 도중의 중간 값이 바인딩에 새면 글자마다
        /// 문서가 스크롤된다. 그래서 초안을 뷰가 들고 있다.
        func testTypingDoesNotLeakIntoTheBindingBeforeCommit() throws {
            let (box, rendered) = try render(page: 1)
            let editor = try focus(rendered)

            editor.selectAll(nil)
            editor.insertText("4")
            pump()

            expect(rendered.field.stringValue) == "4"
            expect(box.page) == 1

            withExtendedLifetime(rendered) {}
        }

        func testReturnCommitsTheTypedPage() throws {
            let (box, rendered) = try render(page: 1)
            let editor = try focus(rendered)

            editor.selectAll(nil)
            editor.insertText("4")
            editor.insertNewline(nil)
            pump()

            expect(box.page) == 4

            withExtendedLifetime(rendered) {}
        }

        /// 범위를 넘긴 입력은 마지막 쪽으로 클램프된다. 초안 정규화("999" → "5")는
        /// `commitPageField`가 직접 하므로 바인딩이 안 바뀌는 경우에도 선다.
        func testReturnClampsBeyondTheLastPage() throws {
            let (box, rendered) = try render(page: 1, totalPages: 5)
            let editor = try focus(rendered)

            editor.selectAll(nil)
            editor.insertText("999")
            editor.insertNewline(nil)
            pump()

            expect(box.page) == 5
            expect(rendered.field.stringValue) == "5"

            withExtendedLifetime(rendered) {}
        }

        /// 숫자가 아닌 입력은 바인딩을 건드리지 않고 초안만 현재 쪽으로 되돌린다.
        func testReturnWithNonNumericInputRevertsTheDraft() throws {
            let (box, rendered) = try render(page: 2)
            let editor = try focus(rendered)

            editor.selectAll(nil)
            editor.insertText("abc")
            editor.insertNewline(nil)
            pump()

            expect(box.page) == 2
            expect(rendered.field.stringValue) == "2"

            withExtendedLifetime(rendered) {}
        }

        // MARK: - 포커스 상실은 커밋이 아니라 되돌림

        /// 다른 곳을 탭했을 뿐인데 문서가 스크롤되면 안 된다.
        func testLosingFocusRevertsInsteadOfCommitting() throws {
            let (box, rendered) = try render(page: 2)
            let editor = try focus(rendered)

            editor.selectAll(nil)
            editor.insertText("5")
            pump()
            expect(rendered.field.stringValue) == "5"

            _ = rendered.window.makeFirstResponder(nil)
            pump()

            expect(box.page) == 2
            expect(rendered.field.stringValue) == "2"

            withExtendedLifetime(rendered) {}
        }
    }

    private extension NSView {
        func firstTextFieldSubview() -> NSTextField? {
            if let match = self as? NSTextField {
                return match
            }
            for subview in subviews {
                if let match = subview.firstTextFieldSubview() {
                    return match
                }
            }
            return nil
        }
    }
#endif
