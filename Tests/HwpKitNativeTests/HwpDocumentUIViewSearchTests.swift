#if os(iOS)
    import CoreGraphics
    import CoreText
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import UIKit
    import XCTest

    /// iOS 검색 하이라이트(#75) — macOS 대응 스위트와 같은 계약을 건다.
    /// 육안 확인에서 현재 매치(주황)가 안 그려지는 것을 발견해 신설했다.
    @MainActor
    final class HwpDocumentUIViewSearchTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private static func document(pageTexts: [String]) -> HwpDocument {
            HwpDocument(
                pages: pageTexts.enumerated().map { index, text in
                    HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [AnyHwpBlock(
                            frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                            kind: .text,
                            attributedString: NSAttributedString(
                                string: text,
                                attributes: [
                                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                                ]
                            )
                        )],
                        pageNumber: index + 1
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: pageTexts.count),
                unsupportedElements: []
            )
        }

        private static func makeView(pageTexts: [String]) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
            view.layoutIfNeeded()
            view.document = Self.document(pageTexts: pageTexts)
            view.layoutIfNeeded()
            return view
        }

        private static func attachedSearch(
            _ view: HwpDocumentUIView, query: String
        ) -> HwpSearchController {
            let controller = HwpSearchController()
            controller.publishInterval = .zero
            view.searchController = controller
            controller.search(text: query)
            return controller
        }

        /// 이것이 육안에서 깨진 계약이다 — **콜백만으로** 현재 매치 오버레이가
        /// 그려져야 한다. `updateSearchOverlays()`를 테스트가 직접 부르면
        /// 배선 누락이 가려진다 (실제로 그렇게 가려져 있었다).
        func testCurrentMatchOverlayIsDrawnWithoutManualRefresh() async {
            let view = Self.makeView(pageTexts: ["alpha beta alpha"])
            let search = Self.attachedSearch(view, query: "alpha")

            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))

            expect(search.currentMatchIndex) == 0
            expect(search.currentMatchRects(forPage: 0)).toNot(beEmpty())
            expect(view.currentSearchMatchLayers[0]).toNot(beNil())
            expect(view.currentSearchMatchLayers[0]?.path?.isEmpty) == false
            expect(view.currentSearchMatchLayers[0]?.superlayer) === view.pageLayers[0]
        }

        func testMatchAndCurrentMatchUseSeparateLayersAndColors() async {
            let view = Self.makeView(pageTexts: ["alpha beta alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            view.updateSearchOverlays()

            expect(view.searchMatchLayers[0]) !== view.currentSearchMatchLayers[0]
            expect(view.searchMatchLayers[0]?.fillColor)
                != view.currentSearchMatchLayers[0]?.fillColor
        }

        func testOverlayZOrderIsExplicit() async {
            let view = Self.makeView(pageTexts: ["alpha beta alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            view.updateSearchOverlays()

            let match = view.searchMatchLayers[0]?.zPosition ?? 0
            let current = view.currentSearchMatchLayers[0]?.zPosition ?? 0
            expect(match) < current
        }

        func testClearingControllerRemovesOverlays() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.updateSearchOverlays()
            expect(view.searchMatchLayers).toNot(beEmpty())

            view.searchController = nil

            expect(view.searchMatchLayers).to(beEmpty())
            expect(view.currentSearchMatchLayers).to(beEmpty())
        }

        /// macOS와 같은 계약 — 스크롤 경로가 이미 칠했으면 다시 만들지 않는다.
        func testNavigationRebuildsOverlaysOnce() async {
            let view = Self.makeView(pageTexts: ["alpha alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            let before = view.searchOverlayRebuildCount

            search.next()

            expect(view.searchOverlayRebuildCount - before) == 1
        }

        /// 문서 끝 매치도 **첫 가시 쪽**이 돼야 한다. 마지막 쪽이 뷰포트보다
        /// 낮으면(축소·짧은 쪽) 문서 전체 클램프가 페이지-로컬 목표를 끌어내려
        /// 앞 쪽이 첫 가시가 되고 그 쪽이 `currentPage` 로 보고된다 (#75 리뷰 6차).
        func testScrollToMatchOnLastPageKeepsItFirstVisibleWhenZoomedOut() async {
            let view = Self.makeView(pageTexts: ["alpha", "alpha", "alpha"])
            view.zoomScale = 0.5
            view.layoutIfNeeded()
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(3), timeout: .seconds(2))

            search.select(matchIndex: 2)

            expect(view.visiblePageRange().lowerBound) == 2
        }

        // MARK: - 해체·색·배율 (#75 리뷰, macOS와 같은 계약)

        func testClearingControllerDetachesSession() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            expect(search.isAttached(to: view.selectionController)) == true

            view.searchController = nil

            expect(search.isAttached(to: view.selectionController)) == false
        }

        /// 옛 뷰의 해체가 이미 새 뷰에 붙은 세션을 끊으면 안 된다.
        func testTeardownLeavesSessionAlreadyAttachedElsewhere() async {
            let oldView = Self.makeView(pageTexts: ["alpha"])
            let newView = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(oldView, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            newView.searchController = search
            expect(search.isAttached(to: newView.selectionController)) == true

            oldView.searchController = nil

            expect(search.isAttached(to: newView.selectionController)) == true
        }

        /// 직접 사용 경로엔 `dismantle*` 훅이 없어 여기서만 세션을 끊을 수 있다.
        func testDeinitDetachesSessionForDirectNativeUse() async {
            let search = HwpSearchController()
            search.publishInterval = .zero
            var view: HwpDocumentUIView? = Self.makeView(pageTexts: ["alpha"])
            guard let selection = view?.selectionController else {
                fail("Expected selection controller")
                return
            }
            view?.searchController = search
            expect(search.isAttached(to: selection)) == true

            view = nil

            await expect(search.isAttached(to: selection))
                .toEventually(beFalse(), timeout: .seconds(2))
        }

        /// `updateSearchOverlays()`를 부르지 않는다 — 부르면 통지 누락이 가려진다.
        func testStyleChangeRepaintsOverlaysWithoutManualRefresh() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            let previous = view.searchMatchLayers[0]?.fillColor
            expect(previous).toNot(beNil())

            search.style = HwpSearchHighlightStyle(
                matchColor: HwpRGBColor(red: 0, green: 1, blue: 0, alpha: 0.5),
                currentMatchColor: HwpRGBColor(red: 0, green: 0, blue: 1, alpha: 0.5)
            )

            expect(view.searchMatchLayers[0]?.fillColor) != previous
        }

        /// 줌이 끝나면 페이지만이 아니라 오버레이도 새 배율로 다시 칠해야 한다.
        func testOverlayScaleFollowsPageLayerAfterScaleChange() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.pageLayers[0]?.contentsScale = 1
            view.searchMatchLayers[0]?.contentsScale = 1

            view.updateLayerContentsScale()

            let pageScale = view.pageLayers[0]?.contentsScale ?? 0
            expect(pageScale) > 1
            expect(view.searchMatchLayers[0]?.contentsScale) == pageScale
        }

        /// 가시 범위가 그대로인 스크롤 틱은 재구축을 건너뛴다 — 안 그러면
        /// 페이지마다 매치 전량을 훑어 CGPath를 다시 만드는 일을 매 틱 문다.
        /// 축출 훅 호출 수가 `updateVisiblePages` 가 돌았는지의 관측점이다.
        func testUnchangedScrollTickSkipsOverlayRebuild() async {
            let view = Self.makeView(pageTexts: ["alpha", "alpha", "alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(3), timeout: .seconds(2))
            var evictions = 0
            search.retainedPageRange = {
                evictions += 1
                return 0 ..< 3
            }

            view.scrollView.contentOffset = CGPoint(x: 0, y: 900)
            view.scrollViewDidScroll(view.scrollView)
            let afterMove = evictions
            // 범위가 실제로 바뀌었는지까지 이 단언이 함께 잡는다
            expect(afterMove) >= 1

            view.scrollViewDidScroll(view.scrollView)

            expect(evictions) == afterMove
        }

        // MARK: - 가로 노출 (육안 확인에서 발견한 결함)

        /// 페이지가 뷰포트보다 넓으면 세로만 맞춰서는 매치가 화면 밖에 남는다.
        /// 시뮬레이터 육안 확인에서 "카운터만 바뀌고 아무 일도 안 일어나는"
        /// 상태로 드러났고, 세로 전용 스크롤이라 어떤 기존 테스트도 못 잡았다.
        func testHorizontalOffsetRevealsMatchOutsideViewport() {
            let view = Self.makeView(pageTexts: ["alpha"])
            view.layoutIfNeeded()
            let width = view.scrollView.bounds.width
            let contentWidth = view.scrollView.contentSize.width
            // 뷰포트(400)보다는 넓은 페이지(595)여야 가로로 스크롤할 여지가 있다
            expect(contentWidth) > width
            // 콘텐츠 **안**이면서 뷰포트 밖 — 콘텐츠를 벗어난 좌표는 애초에
            // 스크롤로 도달할 수 없으므로 계약의 대상이 아니다
            let offScreen = CGRect(x: contentWidth - 60, y: 10, width: 40, height: 20)

            let revealed = view.horizontalOffset(toReveal: offScreen)

            expect(revealed) > view.scrollView.contentOffset.x
            // 매치가 새 뷰포트 안에 들어온다
            expect(offScreen.minX) >= revealed
            expect(offScreen.maxX) <= revealed + width
        }

        /// 이미 보이는 매치는 가로 위치를 **건드리지 않는다** — 매치마다
        /// 재조정하면 같은 단에서 다음 매치로 넘어갈 때 화면이 좌우로 흔들린다.
        func testHorizontalOffsetLeavesVisibleMatchAlone() {
            let view = Self.makeView(pageTexts: ["alpha"])
            view.layoutIfNeeded()
            let current = view.scrollView.contentOffset.x
            let onScreen = CGRect(x: current + 10, y: 10, width: 40, height: 20)

            expect(view.horizontalOffset(toReveal: onScreen)) == current
        }

        /// macOS와 같은 계약 — 공개 API라 현재 매치가 아닌 매치가 들어올 수
        /// 있고, 현재 매치의 기하로 해석하면 다른 쪽 매치는 rect를 못 찾아
        /// 쪽 상단 폴백(반환값 false)으로 떨어진다 (#75 리뷰 8차).
        func testScrollToMatchResolvesSuppliedMatchOnAnotherPage() async {
            let view = Self.makeView(
                pageTexts: ["alpha here", "filler", "filler", "alpha far"]
            )
            view.layoutIfNeeded()
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            expect(search.currentMatchIndex) == 0

            let far = search.matches[1]
            expect(far.pageIndex) == 3

            expect(view.scrollToMatch(far)) == true
            expect(view.scrollView.contentOffset.y) > 0
        }

        /// macOS와 같은 계약 — 쪽을 넘으면 `setContentOffset` 이 동기로
        /// `scrollViewDidScroll` 을 태워 이미 갱신하므로, 그 뒤 무조건 부르면
        /// 재구축이 두 번이 된다 (#75 리뷰 11차).
        func testCrossPageNavigationRebuildsOverlaysOnce() async {
            let view = Self.makeView(
                pageTexts: ["alpha here", "filler", "filler", "alpha far"]
            )
            view.layoutIfNeeded()
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            let before = view.searchOverlayRebuildCount

            search.next()

            expect(view.scrollView.contentOffset.y) > 0
            expect(view.searchOverlayRebuildCount - before) == 1
        }

        func testSearchDoesNotTouchSelectionState() async {
            let view = Self.makeView(pageTexts: ["alpha beta"])
            let search = Self.attachedSearch(view, query: "alpha")

            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

            expect(view.selectionController.selection).to(beNil())
            expect(view.selectionLayers).to(beEmpty())
        }
    }
#endif
