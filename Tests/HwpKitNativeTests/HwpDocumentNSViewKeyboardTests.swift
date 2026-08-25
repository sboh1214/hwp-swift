#if os(macOS)
    import AppKit
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    /// macOS 키보드 페이지 이동 (#120) — `keyDown` 라우팅과 NSResponder 표준
    /// 액션이 같은 쪽 단위 이동에 닿는지, 그리고 토글·수식키·빈 문서가 이벤트를
    /// 삼키지 않고 responder 체인으로 돌려주는지를 본다.
    @MainActor
    final class HwpDocumentNSViewKeyboardTests: XCTestCase {
        private func makeDocument(pageCount: Int = 4) -> HwpDocument {
            let pages = (0 ..< pageCount).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [],
                    pageNumber: index + 1
                )
            }
            return HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: pageCount),
                unsupportedElements: []
            )
        }

        private func makeView(pageCount: Int = 4) -> HwpDocumentNSView {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = makeDocument(pageCount: pageCount)
            return view
        }

        private func keyEvent(
            _ functionKey: Int, modifierFlags: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            let characters = try String(XCTUnwrap(UnicodeScalar(functionKey)))
            return try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            ))
        }

        // MARK: - keyDown 라우팅

        func testPageDownKeyAdvancesOnePage() throws {
            let view = makeView()

            view.keyDown(with: try keyEvent(NSPageDownFunctionKey))

            expect(view.currentVisiblePage()) == 1
        }

        func testPageUpKeyGoesBackOnePage() throws {
            let view = makeView()
            view.scrollToPage(at: 2)

            view.keyDown(with: try keyEvent(NSPageUpFunctionKey))

            expect(view.currentVisiblePage()) == 1
        }

        func testPageUpKeyStaysOnFirstPage() throws {
            let view = makeView()

            view.keyDown(with: try keyEvent(NSPageUpFunctionKey))

            expect(view.currentVisiblePage()) == 0
        }

        func testHomeAndEndKeysJumpToDocumentEdges() throws {
            let view = makeView()

            view.keyDown(with: try keyEvent(NSEndFunctionKey))
            expect(view.currentVisiblePage()) == 3

            view.keyDown(with: try keyEvent(NSHomeFunctionKey))
            expect(view.currentVisiblePage()) == 0
        }

        func testPageDownKeyStopsAtLastPage() throws {
            let view = makeView()
            view.scrollToPage(at: 3)
            let before = view.currentVisiblePage()

            view.keyDown(with: try keyEvent(NSPageDownFunctionKey))

            expect(view.currentVisiblePage()) == before
        }

        // MARK: - 삼키지 않는 경우 (responder 체인으로 반환)

        /// 호스트가 토글을 끄면 분기가 이벤트를 처리하지 않는다 — `keyDown`을
        /// 직접 부르면 미처리 이벤트가 `super`(창 없는 responder 체인)로 가므로
        /// 반환값이 있는 내부 분기로 판정한다.
        func testDisabledToggleLeavesTheKeyToTheHost() throws {
            let view = makeView()
            view.isKeyboardPageNavigationEnabled = false
            let event = try keyEvent(NSPageDownFunctionKey)

            expect(view.handlePageNavigationKey(with: event)) == false
            expect(view.currentVisiblePage()) == 0
        }

        /// Cmd+End·Shift+PageDown 같은 수식키 조합은 호스트 몫이다 — Shift는
        /// 선택 확장 관례가 있는 키라 특히 삼키면 안 된다 (적대 리뷰 확정).
        func testModifiedKeysAreLeftToTheHost() throws {
            let view = makeView()

            for modifiers in [NSEvent.ModifierFlags.command, .option, .control, .shift] {
                let event = try keyEvent(NSEndFunctionKey, modifierFlags: modifiers)
                expect(view.handlePageNavigationKey(with: event)) == false
            }
            expect(view.currentVisiblePage()) == 0
        }

        /// 쪽이 없는 문서에서는 아무것도 안 할 키를 "처리했다"고 삼키지 않는다.
        func testEmptyDocumentDoesNotSwallowPageKeys() throws {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            let event = try keyEvent(NSPageDownFunctionKey)

            expect(view.handlePageNavigationKey(with: event)) == false
        }

        // MARK: - NSResponder 표준 액션 (호스트 메뉴·doCommand 라우팅 통로)

        func testStandardResponderActionsNavigatePages() {
            let view = makeView()

            view.pageDown(nil)
            expect(view.currentVisiblePage()) == 1

            view.pageUp(nil)
            expect(view.currentVisiblePage()) == 0

            view.scrollToEndOfDocument(nil)
            expect(view.currentVisiblePage()) == 3

            view.scrollToBeginningOfDocument(nil)
            expect(view.currentVisiblePage()) == 0

            view.scrollPageDown(nil)
            expect(view.currentVisiblePage()) == 1

            view.scrollPageUp(nil)
            expect(view.currentVisiblePage()) == 0
        }

        /// 표준 액션은 문서가 없어도 트랩 없이 무동작이다.
        func testStandardResponderActionsAreSafeWithoutADocument() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()

            view.pageDown(nil)
            view.pageUp(nil)
            view.scrollToBeginningOfDocument(nil)
            view.scrollToEndOfDocument(nil)

            expect(view.currentVisiblePage()) == 0
        }
    }
#endif
