#if os(iOS)
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    @MainActor
    final class HwpDocumentUIViewTests: XCTestCase {
        private func makeDocument(
            pageCount: Int = 1,
            memoPanelWidth: CGFloat? = nil
        ) -> HwpDocument {
            let pages = (0 ..< pageCount).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [],
                    pageNumber: index + 1,
                    memoPanel: memoPanelWidth.map {
                        HwpMemoPanel(width: $0, paintList: HwpPaintList(commands: []))
                    }
                )
            }
            return HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: pageCount),
                unsupportedElements: []
            )
        }

        // MARK: - fit 배율 (#78)

        /// SwiftUI `makeUIView` 는 bounds 0 에서 배선하므로 뷰포트는 첫
        /// `layoutSubviews` 에서야 선다 — fit 테스트는 전부 그 뒤를 본다.
        private func makeMeasuredView(
            width: CGFloat = 800,
            height: CGFloat = 600,
            pageCount: Int = 3,
            memoPanelWidth: CGFloat? = nil
        ) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(
                frame: CGRect(x: 0, y: 0, width: width, height: height)
            )
            view.document = makeDocument(pageCount: pageCount, memoPanelWidth: memoPanelWidth)
            view.layoutIfNeeded()
            return view
        }

        /// 폭 맞춤의 계약은 "가로 스크롤이 사라진다"이므로 기준은 쪽 폭이 아니라
        /// **실제로 스크롤되는 캔버스**다 (macOS 와 같은 규약).
        func testFitWidthScalesCanvasToViewportWidth() {
            let view = makeMeasuredView()

            expect(view.applyFitZoom(.width)) == true

            expect(view.contentView.bounds.width * view.zoomScale)
                .to(beCloseTo(view.bounds.width, within: 0.5))
        }

        /// 메모 패널은 쪽 바깥 오른쪽에 그려져 캔버스 폭에 들어 있다.
        func testFitWidthIncludesMemoPanelWidth() {
            let bare = makeMeasuredView(pageCount: 1)
            bare.applyFitZoom(.width)

            let withPanel = makeMeasuredView(pageCount: 1, memoPanelWidth: 120)
            withPanel.applyFitZoom(.width)

            expect(withPanel.zoomScale) < bare.zoomScale
            expect(withPanel.contentView.bounds.width * withPanel.zoomScale)
                .to(beCloseTo(withPanel.bounds.width, within: 0.5))
        }

        /// 쪽 맞춤은 두 축을 **모두** 담는다 — 800×600 뷰포트 / A4 는 세로가 이긴다.
        func testFitPageFitsBothAxes() {
            let view = makeMeasuredView()

            expect(view.applyFitZoom(.page)) == true

            let viewport = view.bounds.size
            expect(view.contentView.bounds.width * view.zoomScale) <= viewport.width + 0.5
            expect(view.rowHeight(at: 0) * view.zoomScale) <= viewport.height + 0.5
            expect(view.rowHeight(at: 0) * view.zoomScale)
                .to(beCloseTo(viewport.height, within: 0.5))
        }

        /// 뷰포트 측정이 **현재 배율과 무관**해야 한다 — 맞춤을 두 번 눌러도 같은
        /// 배율이다 (macOS 와 같은 계약, 거기서는 클립 뷰 bounds 함정이 근거다).
        func testFitZoomIsIndependentOfCurrentZoomScale() {
            let view = makeMeasuredView()

            view.applyFitZoom(.width)
            let fromIdentity = view.zoomScale

            view.zoomScale = 3.0
            view.applyFitZoom(.width)
            let fromZoomedIn = view.zoomScale

            view.zoomScale = 0.3
            view.applyFitZoom(.width)
            let fromZoomedOut = view.zoomScale

            expect(fromZoomedIn).to(beCloseTo(fromIdentity, within: 0.0001))
            expect(fromZoomedOut).to(beCloseTo(fromIdentity, within: 0.0001))
        }

        /// SwiftUI `makeUIView` 가 bounds 0 에서 배선하므로 이 경로는 실제로
        /// 밟힌다 — 버리면 호스트가 "문서를 열자마자 폭 맞춤"을 걸 수 없다.
        func testFitZoomDefersUntilViewportIsMeasured() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 2)

            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0

            view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            view.layoutIfNeeded()

            expect(view.pendingFitZoom).to(beNil())
            expect(view.contentView.bounds.width * view.zoomScale)
                .to(beCloseTo(view.bounds.width, within: 0.5))
        }

        /// 쪽 맞춤은 그 쪽이 통째로 보인다는 약속이라 쪽 위로 옮긴다.
        func testFitPageScrollsToThatPage() {
            let view = makeMeasuredView(pageCount: 5)
            view.scrollToPage(at: 2)
            let before = view.currentVisiblePage()

            view.applyFitZoom(.page)

            expect(before) == 2
            expect(view.currentVisiblePage()) == 2
        }

        private func makeTokenDocument(pageCount: Int, loadToken: UUID) -> HwpDocument {
            HwpDocument(
                pages: (0 ..< pageCount).map { index in
                    HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [],
                        pageNumber: index + 1
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: pageCount, loadToken: loadToken),
                unsupportedElements: []
            )
        }

        /// 쪽이 없는 문서는 캔버스에 `defaultPageSize` 하한만 서 있어, 가드가 없으면
        /// 산식이 **유령 A4** 에 맞춘 배율을 성공으로 돌려준다 (macOS 와 같은 가드).
        func testFitZoomDefersWhileDocumentHasNoPages() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutIfNeeded()

            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0
        }

        /// "문서를 열자마자 폭 맞춤" — 문서 대입 끝에서 예약을 직접 소비한다.
        func testQueuedFitAppliesWhenTheDocumentArrives() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutIfNeeded()
            view.applyFitZoom(.width)

            view.document = makeDocument(pageCount: 3)

            expect(view.pendingFitZoom).to(beNil())
            expect(view.contentView.bounds.width * view.zoomScale)
                .to(beCloseTo(view.bounds.width, within: 0.5))
        }

        /// 옛 문서를 향한 예약이 새 문서의 배율을 뺏으면 안 된다 (R71 #2와 같은 판단).
        func testPendingFitIsDiscardedWhenAnotherDocumentReplacesIt() {
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeDocument(pageCount: 2)
            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width

            view.document = makeDocument(pageCount: 5)
            view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            view.layoutIfNeeded()

            expect(view.pendingFitZoom).to(beNil())
            expect(view.zoomScale) == 1.0
        }

        /// 같은 문서의 프로그레시브 스냅샷은 교체가 아니다 — 예약이 살아남는다.
        func testPendingFitSurvivesProgressiveSnapshot() {
            let token = UUID()
            let view = HwpDocumentUIView(frame: .zero)
            view.document = makeTokenDocument(pageCount: 1, loadToken: token)
            view.applyFitZoom(.width)

            view.document = makeTokenDocument(pageCount: 3, loadToken: token)

            expect(view.pendingFitZoom) == HwpZoomFit.width
        }

        /// 쪽이 없어 예약된 맞춤은 **프로그레시브 전이에서** 적용돼야 한다.
        /// `isProgressiveUpdate` 가 `pages.count >=` 라 0 → N 이 그 분기로 오는데,
        /// 그 분기는 조기 반환하고 문서 대입은 레이아웃을 걸지 않으므로 소비하지
        /// 않으면 무관한 리사이즈까지 잠든다 (#78 리뷰, macOS 와 같은 계약).
        func testQueuedFitAppliesOnProgressiveSnapshotFromZeroPages() {
            let token = UUID()
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutIfNeeded()
            view.document = makeTokenDocument(pageCount: 0, loadToken: token)
            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0

            view.document = makeTokenDocument(pageCount: 3, loadToken: token)

            expect(view.pendingFitZoom).to(beNil())
            expect(view.contentView.bounds.width * view.zoomScale)
                .to(beCloseTo(view.bounds.width, within: 0.5))
        }

        /// 맞출 수 없는 조합에서도 실패가 아니라 **범위 안에서 최선**이다.
        func testFitZoomClampsToNativeZoomLimits() {
            let view = makeMeasuredView(width: 100, height: 100, pageCount: 1)

            expect(view.applyFitZoom(.width)) == true

            expect(view.zoomScale) == view.scrollView.minimumZoomScale
        }

        /// 스크롤 뷰는 contentOffset을 기기 픽셀 그리드에 맞춘다 — 3× 기기에서
        /// 102.5pt 인셋이 102.333pt(=307/3)로 스냅되므로, 센터링 원점 판정은
        /// 정확한 일치가 아니라 1픽셀 허용오차여야 2×·3× 양쪽에서 성립한다.
        private func devicePixel(of view: HwpDocumentUIView) -> CGFloat {
            let scale = view.traitCollection.displayScale
            return scale > 0 ? 1 / scale : 0.5
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

        /// 범위 밖 배율은 스크롤 뷰가 클램프하므로 저장 값도 클램프돼야 한다 —
        /// 클램프 전 값이 남으면 HwpKit 정규화가 그것을 실제 배율로 오인한다 (R72 #3).
        func testZoomScaleClampsToNativeMaximum() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            view.document = makeDocument()

            view.zoomScale = 10

            expect(view.zoomScale) == view.scrollView.maximumZoomScale
            expect(view.scrollView.zoomScale) == view.scrollView.maximumZoomScale
        }

        /// 이미 상한이면 스크롤 뷰가 안 바뀌어 echo도 없다 — 그래도 stale 값이
        /// 남지 않아야 정규화가 바인딩을 되돌릴 수 있다 (R72 #3의 발현 조건).
        func testZoomScaleAtMaximumDiscardsFurtherOutOfRangeValue() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            view.document = makeDocument()
            view.zoomScale = view.scrollView.maximumZoomScale

            view.zoomScale = 10

            expect(view.zoomScale) == view.scrollView.maximumZoomScale
        }

        /// 비-finite 배율은 직전 값을 유지한다 — NaN을 저장하면 정규화 술어가
        /// 무조건 writeback으로 판정해 바인딩까지 NaN으로 오염된다.
        func testNonFiniteZoomScaleKeepsPreviousValue() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            view.document = makeDocument()
            view.zoomScale = 2

            view.zoomScale = .nan

            expect(view.zoomScale) == 2
        }

        func testProgrammaticZoomUpdatesLayerContentsScale() {
            // 버튼 줌 (zoomScale 프로그램 대입)은 scrollViewDidEndZooming이
            // 발화하지 않는다 — didSet이 직접 재래스터해야 흐릿해지지 않는다.
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            view.document = makeDocument()
            guard let layer = view.pageLayers[0] else {
                fail("페이지 레이어가 없다")
                return
            }
            let baseScale = layer.contentsScale

            view.zoomScale = 2.0

            // 3× 기기에서는 요청 배율(base×2 = 6)이 페이지 면적 래스터 상한
            // √(16,000,000/(595·842)) ≈ 5.651에 걸린다 — 상한을 빼고 단언하면
            // 2× 기기에서만 통과한다.
            let expected = HwpDocumentViewSupport.boundedContentsScale(
                baseScale * 2, for: layer.bounds.size
            )
            expect(expected) > baseScale
            expect(view.pageLayers[0]?.contentsScale) == expected
        }

        /// 뷰포트보다 작은 문서로 교체하면 센터링 인셋 보정 원점에서 열린다 —
        /// .zero는 인셋을 지나쳐 작은 문서를 좌상단에 붙인다 (R39 #2).
        func testSmallDocumentReplacementOpensAtCenteringOrigin() {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
            view.layoutIfNeeded()

            view.document = makeDocument()

            let inset = view.scrollView.adjustedContentInset
            let pixel = devicePixel(of: view)
            expect(inset.top) > 0
            expect(inset.left) > 0
            expect(view.scrollView.contentOffset.x).to(beCloseTo(-inset.left, within: pixel))
            expect(view.scrollView.contentOffset.y).to(beCloseTo(-inset.top, within: pixel))
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
            let pixel = devicePixel(of: view)
            expect(inset.top) > 0
            expect(view.scrollView.contentOffset.x).to(beCloseTo(-inset.left, within: pixel))
            expect(view.scrollView.contentOffset.y).to(beCloseTo(-inset.top, within: pixel))
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
