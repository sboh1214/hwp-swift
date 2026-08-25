#if os(iOS)
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import UIKit
    import XCTest

    /// iOS 하드웨어 키보드 페이지 이동 (#120) — `keyCommands` 노출 조건과 액션
    /// 셀렉터의 쪽 단위 이동을 본다. first responder 라우팅 자체는 UIKit 몫이라
    /// 자동화 밖이고 (시뮬레이터 QA), 여기서는 명령 목록과 동작을 잠근다.
    @MainActor
    final class HwpDocumentUIViewKeyboardTests: XCTestCase {
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

        private func makeView(pageCount: Int = 4) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(
                frame: CGRect(x: 0, y: 0, width: 800, height: 600)
            )
            view.document = makeDocument(pageCount: pageCount)
            view.layoutIfNeeded()
            return view
        }

        // MARK: - keyCommands 노출 조건

        func testKeyCommandsCoverPageUpDownHomeEnd() {
            let view = makeView()

            let inputs = (view.keyCommands ?? []).compactMap(\.input)

            expect(inputs).to(contain(
                UIKeyCommand.inputPageUp,
                UIKeyCommand.inputPageDown,
                UIKeyCommand.inputHome,
                UIKeyCommand.inputEnd
            ))
        }

        /// 시스템 스크롤 뷰의 뷰포트 단위 키 처리보다 쪽 단위 해석이 이겨야 한다.
        func testKeyCommandsTakePriorityOverSystemBehavior() {
            let view = makeView()

            let commands = view.keyCommands ?? []

            expect(commands).toNot(beEmpty())
            expect(commands.allSatisfy(\.wantsPriorityOverSystemBehavior)) == true
        }

        func testDisabledToggleRemovesKeyCommands() {
            let view = makeView()
            view.isKeyboardPageNavigationEnabled = false

            expect(view.keyCommands ?? []).to(beEmpty())
        }

        func testNoDocumentExposesNoKeyCommands() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

            expect(view.keyCommands ?? []).to(beEmpty())
        }

        // MARK: - 액션 셀렉터 (쪽 단위 이동)

        func testPageDownActionAdvancesOnePage() {
            let view = makeView()

            view.pageDownKeyPressed()

            expect(view.currentVisiblePage()) == 1
        }

        func testPageUpActionGoesBackOnePageAndStopsAtFirst() {
            let view = makeView()
            view.scrollToPage(at: 2)

            view.pageUpKeyPressed()
            expect(view.currentVisiblePage()) == 1

            view.pageUpKeyPressed()
            view.pageUpKeyPressed()
            expect(view.currentVisiblePage()) == 0
        }

        func testHomeAndEndActionsJumpToDocumentEdges() {
            let view = makeView()

            view.endKeyPressed()
            expect(view.currentVisiblePage()) == 3

            view.homeKeyPressed()
            expect(view.currentVisiblePage()) == 0
        }

        func testPageDownActionStopsAtLastPage() {
            let view = makeView()
            view.endKeyPressed()
            let before = view.currentVisiblePage()

            view.pageDownKeyPressed()

            expect(view.currentVisiblePage()) == before
        }

        /// 액션은 문서가 없어도 트랩 없이 무동작이다 — 클램프·빈 문서 가드는
        /// `scrollToPage`가 소유한다 (#4).
        func testActionsAreSafeWithoutADocument() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

            view.pageUpKeyPressed()
            view.pageDownKeyPressed()
            view.homeKeyPressed()
            view.endKeyPressed()

            expect(view.currentVisiblePage()) == 0
        }
    }
#endif
