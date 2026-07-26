#if os(iOS)
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    @MainActor
    final class HwpDocumentUIViewTests: XCTestCase {
        private func makeDocument(pageCount: Int = 1) -> HwpDocument {
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

        func testInitializesWithNoPageLayers() {
            let view = HwpDocumentUIView(frame: .zero)

            expect(view.pageLayers).to(beEmpty())
        }

        func testUpdateVisiblePagesAddsLayers() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 7)

            view.updateVisiblePages(range: 0 ..< 3)

            // 요청 범위 ±2 페이지를 미리 만든다
            expect(view.pageLayers.keys.sorted()) == [0, 1, 2, 3, 4]
        }

        func testAutoscrollStepZonesAndClamp() {
            let height: CGFloat = 600
            let step = { (y: CGFloat) in
                HwpDocumentUIView.autoscrollStep(forLocationY: y, boundsHeight: height)
            }

            // 존 밖 (중앙) — 스크롤 없음
            expect(step(300)) == 0
            expect(step(44)) == 0
            expect(step(556)) == 0
            // 상단 존 — 음수 (위로), 침투 비례
            expect(step(22)) == -6
            expect(step(0)) == -12
            // 하단 존 — 양수 (아래로), 침투 비례
            expect(step(578)) == 6
            expect(step(600)) == 12
            // 존 밖 좌표 (경계 초과)도 최대 스텝으로 클램프
            expect(step(-100)) == -12
            expect(step(700)) == 12
            // 뷰포트가 존 두 개보다 작으면 비활성
            expect(HwpDocumentUIView.autoscrollStep(
                forLocationY: 10, boundsHeight: 80
            )) == 0
        }

        func testProgrammaticZoomUpdatesLayerContentsScale() {
            // 버튼 줌 (zoomScale 프로그램 대입)은 scrollViewDidEndZooming이
            // 발화하지 않는다 — didSet이 직접 재래스터해야 흐릿해지지 않는다.
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            view.document = makeDocument()
            guard let baseScale = view.pageLayers[0]?.contentsScale else {
                fail("페이지 레이어가 없다")
                return
            }

            view.zoomScale = 2.0

            expect(view.pageLayers[0]?.contentsScale) == baseScale * 2
        }

        /// 뷰포트보다 작은 문서로 교체하면 센터링 인셋 보정 원점에서 열린다 —
        /// .zero는 인셋을 지나쳐 작은 문서를 좌상단에 붙인다 (R39 #2).
        func testSmallDocumentReplacementOpensAtCenteringOrigin() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
            view.layoutIfNeeded()

            view.document = makeDocument()

            let inset = view.scrollView.adjustedContentInset
            expect(inset.top) > 0
            expect(inset.left) > 0
            expect(view.scrollView.contentOffset.x) == -inset.left
            expect(view.scrollView.contentOffset.y) == -inset.top
        }

        /// SwiftUI 경로: makeUIView가 bounds 0일 때 문서를 대입하면 인셋이 0이라
        /// 즉시 센터링이 no-op이지만, 첫 non-zero 레이아웃에서 센터링 원점이
        /// 적용돼 작은 문서가 좌상단에 붙지 않는다 (R40 #1).
        func testDeferredCenteringAppliesOnFirstNonZeroLayout() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument()

            view.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
            view.layoutIfNeeded()

            let inset = view.scrollView.adjustedContentInset
            expect(inset.top) > 0
            expect(view.scrollView.contentOffset.x) == -inset.left
            expect(view.scrollView.contentOffset.y) == -inset.top
        }

        /// SwiftUI makeUIView(bounds 0)에서 들어온 초기 페이지 요청은 첫 실측
        /// 레이아웃에서 복원된다 — 예약된 초기 센터링이 요청을 덮으면 페이지 1로
        /// 되돌아가고 currentPage 바인딩까지 오염된다 (R70 #1).
        func testInitialPageRequestSurvivesPendingCentering() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 10)

            view.scrollToPage(at: 4)
            view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
            view.layoutIfNeeded()

            expect(view.currentVisiblePage()) == 4
        }

        /// 첫 레이아웃 전에 문서가 교체되면 옛 문서의 예약 페이지를 버리고 맨
        /// 위에서 연다 — 남기면 교체 문서가 엉뚱한 페이지에서 열린다 (R71 #2).
        func testDocumentReplacementDiscardsQueuedInitialPage() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 10)
            view.scrollToPage(at: 7)

            // 구조가 다른 문서여야 전체 교체 경로를 탄다 (같은 문서 재전달은
            // 스크롤 유지가 의도된 별도 경로).
            view.document = makeDocument(pageCount: 6)
            view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
            view.layoutIfNeeded()

            expect(view.currentVisiblePage()) == 0
        }

        /// 초기 요청이 없으면 종전대로 센터링 원점에서 연다 (R40 #1 유지).
        func testInitialCenteringStillAppliesWithoutPageRequest() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 10)

            view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
            view.layoutIfNeeded()

            expect(view.currentVisiblePage()) == 0
            expect(view.scrollView.contentOffset.y)
                == -view.scrollView.adjustedContentInset.top
        }

        /// scrollToPage는 인셋 반영 클램프로 짧은 문서를 센터에 유지한다 —
        /// zero-based 클램프는 y=0(좌상단)으로 밀어냈다 (R40 #2).
        func testScrollToPageKeepsShortDocumentCentered() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
            view.layoutIfNeeded()
            view.document = makeDocument()

            view.scrollToPage(at: 0)

            let inset = view.scrollView.adjustedContentInset
            expect(inset.top) > 0
            expect(view.scrollView.contentOffset.y) == -inset.top
        }
    }
#endif
