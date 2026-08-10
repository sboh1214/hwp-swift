#if os(macOS)
    import AppKit
    import CoreText
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    /// macOS 검색 하이라이트(#75) — 딕셔너리 2벌 분리·z-순서·색 갱신·청소·스크롤.
    @MainActor
    final class HwpDocumentNSViewSearchTests: XCTestCase {
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

        private static func makeView(pageTexts: [String]) -> HwpDocumentNSView {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = Self.document(pageTexts: pageTexts)
            return view
        }

        private static func attachedSearch(
            _ view: HwpDocumentNSView, query: String
        ) -> HwpSearchController {
            let controller = HwpSearchController()
            controller.publishInterval = .zero
            view.searchController = controller
            controller.search(text: query)
            return controller
        }

        // MARK: - 딕셔너리 2벌 분리

        /// 헬퍼가 페이지당 오버레이 하나를 재사용하므로, 한 벌로 두 번 칠하면
        /// 두 번째 호출이 첫 번째의 path를 덮는다.
        func testMatchAndCurrentMatchUseSeparateLayers() async {
            let view = Self.makeView(pageTexts: ["alpha beta alpha"])
            let search = Self.attachedSearch(view, query: "alpha")

            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))
            view.updateSearchOverlays()

            expect(view.searchMatchLayers[0]).toNot(beNil())
            expect(view.currentSearchMatchLayers[0]).toNot(beNil())
            expect(view.searchMatchLayers[0]) !== view.currentSearchMatchLayers[0]
            expect(view.searchMatchLayers[0]?.fillColor)
                != view.currentSearchMatchLayers[0]?.fillColor
        }

        /// z를 명시하지 않으면 첫 부착 순서가 그대로 고착돼, 가상화로
        /// 재실체화한 페이지만 겹침 색이 뒤바뀐다.
        func testOverlayZOrderIsExplicitAndSelectionStaysOnTop() async {
            let view = Self.makeView(pageTexts: ["alpha beta alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(2), timeout: .seconds(2))

            view.selectionController.begin(at: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ))
            view.selectionController.extend(to: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 5
            ))
            view.updateSearchOverlays()

            let match = view.searchMatchLayers[0]?.zPosition ?? 0
            let current = view.currentSearchMatchLayers[0]?.zPosition ?? 0
            let selection = view.selectionLayers[0]?.zPosition ?? 0
            expect(match) < current
            expect(current) < selection
        }

        /// 문서를 교체해도 오버레이 딕셔너리가 비워지지 않아 레이어가 재사용된다
        /// — 생성 분기에서만 색을 대입하면 옛 색이 그대로 남는다.
        func testReusedOverlayPicksUpNewFillColor() async {
            let view = Self.makeView(pageTexts: ["alpha beta"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.updateSearchOverlays()
            let reusedLayer = view.searchMatchLayers[0]
            let original = reusedLayer?.fillColor

            search.style = HwpSearchHighlightStyle(
                matchColor: HwpRGBColor(red: 0, green: 1, blue: 0, alpha: 1),
                currentMatchColor: HwpRGBColor(red: 0, green: 0, blue: 1, alpha: 1)
            )
            view.updateSearchOverlays()

            expect(view.searchMatchLayers[0]) === reusedLayer
            expect(view.searchMatchLayers[0]?.fillColor) != original
        }

        func testOverlayInheritsPageLayerContentsScale() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.updateSearchOverlays()

            expect(view.searchMatchLayers[0]?.contentsScale)
                == view.pageLayers[0]?.contentsScale
        }

        // MARK: - 청소

        func testClearingControllerRemovesAllSearchOverlays() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.updateSearchOverlays()
            expect(view.searchMatchLayers).toNot(beEmpty())

            view.searchController = nil

            expect(view.searchMatchLayers).to(beEmpty())
            expect(view.currentSearchMatchLayers).to(beEmpty())
        }

        func testQueryWithNoMatchesRemovesOverlays() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            view.updateSearchOverlays()
            expect(view.searchMatchLayers[0]).toNot(beNil())

            search.search(text: "zebra")
            await expect(search.matchCount).toEventually(equal(0), timeout: .seconds(2))
            view.updateSearchOverlays()

            expect(view.searchMatchLayers[0]).to(beNil())
            expect(view.currentSearchMatchLayers[0]).to(beNil())
        }

        // MARK: - 매치 노출 스크롤

        /// 매치 페이지가 **첫 가시 페이지**여야 페이지 바인딩 왕복이 스크롤을
        /// 되튕기지 않는다.
        func testScrollToMatchMakesMatchPageTheFirstVisiblePage() async {
            let view = Self.makeView(
                pageTexts: (0 ..< 8).map { $0 == 5 ? "needle here" : "filler \($0)" }
            )
            let search = Self.attachedSearch(view, query: "needle")

            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

            expect(view.currentVisiblePage()) == 5
        }

        func testScrollToMatchIsNoOpForOutOfRangePage() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

            let stale = HwpSearchMatch(selection: HwpTextSelection(
                anchor: HwpTextPosition(
                    pageIndex: 99, blockIndex: 0, unitIndex: 0, characterOffset: 0
                ),
                focus: HwpTextPosition(
                    pageIndex: 99, blockIndex: 0, unitIndex: 0, characterOffset: 1
                )
            ))
            view.scrollToMatch(stale)

            expect(view.currentVisiblePage()) == 0
        }

        // MARK: - 재대입 멱등

        /// 가드가 없으면 SwiftUI wrapper의 매 갱신이 재배선 → 재스캔 →
        /// 관찰자 통지 → 뷰 갱신 루프를 돌린다.
        func testReassigningSameControllerIsIdempotent() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            let revisionBefore = search.revision

            view.searchController = search
            view.searchController = search

            expect(search.revision) == revisionBefore
            expect(search.matchCount) == 1
        }

        // MARK: - 해체·색·배율 (#75 리뷰)

        /// 호스트가 붙든 컨트롤러는 뷰보다 오래 산다 — 해체 때 떼지 않으면
        /// 선택 컨트롤러를, 그것이 다시 문서 전체를 붙든다.
        func testClearingControllerDetachesSession() async {
            let view = Self.makeView(pageTexts: ["alpha"])
            let search = Self.attachedSearch(view, query: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            expect(search.isAttached(to: view.selectionController)) == true

            view.searchController = nil

            expect(search.isAttached(to: view.selectionController)) == false
        }

        /// SwiftUI는 새 뷰를 먼저 만들고 옛 뷰를 나중에 해체할 수 있다.
        /// 그때 옛 뷰가 무조건 떼면 이미 새 뷰에 붙은 세션이 끊긴다.
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

        /// 색만 바뀌면 매치·현재 매치 콜백이 오지 않는다 — 테스트가
        /// `updateSearchOverlays()`를 부르면 그 통지 누락이 가려진다.
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

        /// 오버레이는 부착 때 부모 배율을 물려받을 뿐이라, 배율 갱신이 페이지만
        /// 바꾸고 끝나면 줌 뒤에도 옛 배율로 남아 흐려진다.
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

        // MARK: - 가로 노출 (육안 확인에서 발견한 결함)

        /// iOS와 같은 계약 — 페이지가 뷰포트보다 넓으면 세로만 맞춰서는
        /// 매치가 화면 밖에 남는다.
        /// 페이지(595pt)보다 좁은 뷰여야 가로 스크롤 여지가 생긴다.
        private static func makeNarrowView() -> HwpDocumentNSView {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = Self.document(pageTexts: ["alpha"])
            view.layoutSubtreeIfNeeded()
            return view
        }

        func testHorizontalOffsetRevealsMatchOutsideViewport() {
            let view = Self.makeNarrowView()
            let visible = view.scrollView.documentVisibleRect
            let offScreen = CGRect(x: visible.maxX + 200, y: 10, width: 60, height: 20)

            let revealed = view.horizontalOffset(toReveal: offScreen)

            expect(revealed) > visible.minX
            expect(offScreen.minX) >= revealed
            expect(offScreen.maxX) <= revealed + visible.width
        }

        func testHorizontalOffsetLeavesVisibleMatchAlone() {
            let view = Self.makeNarrowView()
            let visible = view.scrollView.documentVisibleRect
            let onScreen = CGRect(x: visible.minX + 10, y: 10, width: 40, height: 20)

            expect(view.horizontalOffset(toReveal: onScreen)) == visible.minX
        }

        // MARK: - 선택과의 독립

        /// 검색이 선택 상태를 건드리면 Cmd+C 대상이 검색 매치로 바뀐다.
        func testSearchDoesNotTouchSelectionState() async {
            let view = Self.makeView(pageTexts: ["alpha beta"])
            let search = Self.attachedSearch(view, query: "alpha")

            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

            expect(view.selectionController.selection).to(beNil())
            expect(view.selectionController.hasSelection) == false
            expect(view.selectionLayers).to(beEmpty())
        }
    }
#endif
