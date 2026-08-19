#if os(macOS)
    import AppKit
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    final class HwpDocumentNSViewTests: XCTestCase {
        private let defaultPageHeight: CGFloat = 842
        private let pageGap: CGFloat = 24

        private func makeDocument(
            pageCount: Int,
            pageSize: CGSize = CGSize(width: 595, height: 842),
            memoPanelWidth: CGFloat? = nil
        ) -> HwpDocument {
            let pages = (0 ..< pageCount).map { index in
                HwpPage(
                    size: pageSize,
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

        func testPageLayersAreEmptyInitially() {
            let view = HwpDocumentNSView()

            expect(view.pageLayers.isEmpty) == true
            expect(view.documentContentView.layer?.sublayers?.isEmpty ?? true) == true
        }

        func testUpdateVisiblePagesAddsVisibleLayers() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))

            view.updateVisiblePages(range: 0 ..< 3)

            expect(view.pageLayers.keys.sorted()) == [0, 1, 2]
            expect(view.documentContentView.layer?.sublayers?.count) == 3
        }

        func testUpdateVisiblePagesDiffsDistantLayers() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.updateVisiblePages(range: 0 ..< 3)

            view.updateVisiblePages(range: 5 ..< 8)

            expect(view.pageLayers.keys.sorted()) == [5, 6, 7]
            expect(view.documentContentView.layer?.sublayers?.count) == 3
        }

        /// 버그 회귀: 앵커 페이지가 항상 y=0에 재고정되어 2페이지부터 위치가
        /// 어긋나던 문제 — 모든 페이지는 문서 좌표계의 누적 y에 놓여야 한다.
        func testPageFramesAccumulate() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.document = makeDocument(pageCount: 10)

            view.updateVisiblePages(range: 5 ..< 6)

            let expectedY = CGFloat(5) * (defaultPageHeight + pageGap)
            expect(view.pageLayers[5]?.frame.minY) == expectedY
        }

        func testPageFramesAccumulateWithoutDocument() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))

            view.updateVisiblePages(range: 5 ..< 6)

            let expectedY = CGFloat(5) * (defaultPageHeight + pageGap)
            expect(view.pageLayers[5]?.frame.minY) == expectedY
        }

        /// 페이지 사이 gap의 상단 절반(위 페이지에 더 가까움)은 위 페이지로,
        /// 하단 절반은 아래 페이지로 클램프한다 — 드래그 선택 끝점이 아래 페이지
        /// top으로 점프하지 않게 인접 두 페이지 거리를 비교한다 (R52 #1).
        func testPagePositionNearestComparesBothPagesInGap() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.document = makeDocument(pageCount: 3)
            view.rebuildPageOrigins()

            // 페이지 0 [0,842], gap [842,866], 페이지 1 [866,1708].
            expect(view.pagePosition(nearest: CGPoint(x: 100, y: 848))?.pageIndex) == 0
            expect(view.pagePosition(nearest: CGPoint(x: 100, y: 860))?.pageIndex) == 1
            // 페이지 내부 점은 그대로.
            expect(view.pagePosition(nearest: CGPoint(x: 100, y: 400))?.pageIndex) == 0
            expect(view.pagePosition(nearest: CGPoint(x: 100, y: 1000))?.pageIndex) == 1
        }

        /// 보존 창 (가시 ±2)을 미리 실체화한다 — 인접 페이지가 뷰포트 진입
        /// 전에 생성돼 스크롤 중 플레이스홀더가 번쩍이지 않는다 (R31 #4).
        func testUpdateVisiblePagesMaterializesRetentionWindow() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.document = makeDocument(pageCount: 10)

            view.updateVisiblePages(range: 5 ..< 6)

            expect(view.pageLayers.keys.sorted()) == [3, 4, 5, 6, 7]
        }

        /// 보존 창은 문서 페이지 수로 클램프된다 — 끝 페이지에서 범위 밖
        /// 레이어를 만들지 않는다.
        func testRetentionWindowClampsToPageCount() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.document = makeDocument(pageCount: 4)

            view.updateVisiblePages(range: 3 ..< 4)

            expect(view.pageLayers.keys.sorted()) == [1, 2, 3]
        }

        func testScrollToPageMovesDocumentVisibleRect() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = makeDocument(pageCount: 10)

            view.scrollToPage(at: 3)

            let expectedY = CGFloat(3) * (defaultPageHeight + pageGap)
            expect(view.scrollView.documentVisibleRect.minY) == expectedY
            expect(view.currentVisiblePage()) == 3
        }

        func testScrollOffsetDrivesCurrentPage() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = makeDocument(pageCount: 10)
            var reportedPages: [Int] = []
            view.onPageChanged = { reportedPages.append($0) }

            let offsetY = CGFloat(2) * (defaultPageHeight + pageGap)
            view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: offsetY))
            view.scrollView.reflectScrolledClipView(view.scrollView.contentView)

            expect(view.currentVisiblePage()) == 2
            expect(reportedPages.last) == 2
        }

        func testZoomScaleClamps() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.document = makeDocument(pageCount: 2)

            view.zoomScale = 100
            expect(view.zoomScale) == 5.0

            view.zoomScale = 0.01
            expect(view.zoomScale) == 0.25
        }

        func testMagnificationFiresOnZoomChanged() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = makeDocument(pageCount: 2)
            var reportedZooms: [CGFloat] = []
            view.onZoomChanged = { reportedZooms.append($0) }

            view.scrollView.magnification = 2.0

            expect(reportedZooms.last).to(beCloseTo(2.0))
        }

        // MARK: - fit 배율 (#78)

        private func makeMeasuredView(
            width: CGFloat = 800,
            height: CGFloat = 600
        ) -> HwpDocumentNSView {
            let view = HwpDocumentNSView(
                frame: NSRect(x: 0, y: 0, width: width, height: height)
            )
            view.layoutSubtreeIfNeeded()
            return view
        }

        /// 폭 맞춤의 계약은 "가로 스크롤이 사라진다"이므로, 기준은 쪽 폭이 아니라
        /// **실제로 스크롤되는 캔버스**다 — 캔버스 폭 × 배율 = 뷰포트 폭.
        func testFitWidthScalesCanvasToViewportWidth() {
            let view = makeMeasuredView()
            view.document = makeDocument(pageCount: 3)

            expect(view.applyFitZoom(.width)) == true

            expect(view.documentContentView.frame.width * view.zoomScale)
                .to(beCloseTo(view.scrollView.contentSize.width, within: 0.5))
        }

        /// 메모 패널은 쪽 바깥 오른쪽에 그려져 캔버스 폭에 들어 있다 — 빼고 맞추면
        /// 패널이 뷰포트 밖으로 밀려 폭 맞춤이 아니게 된다.
        func testFitWidthIncludesMemoPanelWidth() {
            let bare = makeMeasuredView()
            bare.document = makeDocument(pageCount: 1)
            bare.applyFitZoom(.width)

            let withPanel = makeMeasuredView()
            withPanel.document = makeDocument(pageCount: 1, memoPanelWidth: 120)
            withPanel.applyFitZoom(.width)

            expect(withPanel.zoomScale) < bare.zoomScale
            expect(withPanel.documentContentView.frame.width * withPanel.zoomScale)
                .to(beCloseTo(withPanel.scrollView.contentSize.width, within: 0.5))
        }

        /// 쪽 맞춤은 두 축을 **모두** 담는다 — 더 빡빡한 축이 이긴다.
        func testFitPageFitsBothAxes() {
            let view = makeMeasuredView()
            view.document = makeDocument(pageCount: 3)

            expect(view.applyFitZoom(.page)) == true

            let viewport = view.scrollView.contentSize
            expect(view.documentContentView.frame.width * view.zoomScale) <= viewport.width + 0.5
            expect(view.rowHeight(at: 0) * view.zoomScale) <= viewport.height + 0.5
            // 세로가 더 빡빡한 배치(800×600 뷰포트 / A4)라 높이가 배율을 정한다.
            expect(view.rowHeight(at: 0) * view.zoomScale)
                .to(beCloseTo(viewport.height, within: 0.5))
        }

        /// 뷰포트 측정이 **현재 배율과 무관**해야 한다. `NSScrollView` 는 확대를
        /// 클립 뷰 bounds 로 구현하므로 그쪽을 재면 맞춤을 누를 때마다 배율이
        /// 흘러간다 — 프레임(=`contentSize`)을 재는 근거가 이 단언이다.
        func testFitZoomIsIndependentOfCurrentMagnification() {
            let view = makeMeasuredView()
            view.document = makeDocument(pageCount: 3)

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

        /// 뷰포트가 실측되기 전(창에 붙기 전·SwiftUI 첫 배선) 요청을 버리면
        /// 호스트가 "문서를 열자마자 폭 맞춤"을 걸 수 없다 — 예약했다가 첫
        /// 실측 레이아웃에서 적용한다.
        func testFitZoomDefersUntilViewportIsMeasured() {
            let view = HwpDocumentNSView()
            view.document = makeDocument(pageCount: 2)

            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0

            view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            view.layout()

            expect(view.pendingFitZoom).to(beNil())
            expect(view.documentContentView.frame.width * view.zoomScale)
                .to(beCloseTo(view.scrollView.contentSize.width, within: 0.5))
        }

        /// 쪽 맞춤은 그 쪽이 **통째로 보인다**는 약속이라 배율만으로는 반쪽이다 —
        /// 쪽 위로 옮긴다. 폭 맞춤은 반대로 읽던 자리를 지킨다.
        func testFitPageScrollsToThatPageButFitWidthDoesNot() {
            let view = makeMeasuredView()
            view.document = makeDocument(pageCount: 5)
            let pageTop = view.frameForPage(at: 2).minY
            func scrollIntoPageTwo() {
                view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: pageTop + 200))
                view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
            }

            view.zoomScale = 1.0
            scrollIntoPageTwo()
            view.applyFitZoom(.width)
            let afterWidth = view.scrollView.documentVisibleRect.minY

            view.zoomScale = 1.0
            scrollIntoPageTwo()
            view.applyFitZoom(.page)
            let afterPage = view.scrollView.documentVisibleRect.minY

            expect(afterWidth) > pageTop
            expect(afterPage).to(beCloseTo(pageTop, within: 1))
            expect(view.currentVisiblePage()) == 2
        }

        /// 쪽이 없는 문서는 캔버스에 `defaultPageSize` 하한만 서 있어, 가드가
        /// 없으면 산식이 **유령 A4** 에 맞춘 배율을 성공으로 돌려준다 — 원샷이라
        /// 진짜 문서가 도착해도 다시 맞추지 않으므로 그 배율이 그대로 남는다.
        func testFitZoomDefersWhileDocumentHasNoPages() {
            let view = makeMeasuredView()

            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0
        }

        /// "문서를 열자마자 폭 맞춤" — 문서 대입은 자기 자신에게 레이아웃을 걸지
        /// 않으므로 대입 끝에서 예약을 직접 소비하지 않으면 다음 리사이즈까지 잠든다.
        func testQueuedFitAppliesWhenTheDocumentArrives() {
            let view = makeMeasuredView()
            view.applyFitZoom(.width)

            view.document = makeDocument(pageCount: 3)

            expect(view.pendingFitZoom).to(beNil())
            expect(view.documentContentView.frame.width * view.zoomScale)
                .to(beCloseTo(view.scrollView.contentSize.width, within: 0.5))
        }

        /// 옛 문서를 향한 예약이 새 문서의 배율을 뺏으면 안 된다 — 교체에서
        /// 버린다 (`pendingInitialPageIndex` 와 같은 판단, R71 #2).
        func testPendingFitIsDiscardedWhenAnotherDocumentReplacesIt() {
            let view = HwpDocumentNSView()
            view.document = makeDocument(pageCount: 2)
            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width

            view.document = makeDocument(pageCount: 5)
            view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            view.layout()

            expect(view.pendingFitZoom).to(beNil())
            expect(view.zoomScale) == 1.0
        }

        /// 같은 문서의 프로그레시브 스냅샷은 교체가 아니다 — 예약이 살아남아야
        /// 로딩 중 요청이 유실되지 않는다.
        func testPendingFitSurvivesProgressiveSnapshot() {
            let token = UUID()
            let view = HwpDocumentNSView()
            view.document = makeTokenDocument(pageCount: 1, loadToken: token)
            view.applyFitZoom(.width)

            view.document = makeTokenDocument(pageCount: 3, loadToken: token)

            expect(view.pendingFitZoom) == HwpZoomFit.width
        }

        /// 0쪽 문서에 건 예약도 **다른 문서로 교체되면** 버린다 (#107 리뷰).
        ///
        /// 예약을 살리는 조건이 `oldValue?.pages.isEmpty == false` 였을 때는
        /// `oldValue == nil`(열자마자 맞춤)과 **0쪽 실제 문서**가 뭉개져, A 에 건
        /// `.page` 가 B 에 그대로 실렸다 (실측: 배율이 B 의 쪽 맞춤 0.3 으로,
        /// 스크롤도 B 의 쪽 머리로). 코디네이터의 세대 가드는 이것을 막지 못한다 —
        /// 문서 대입이 fit 블록보다 먼저라 그 didSet 안에서 이미 적용된다.
        func testPendingFitFromAnEmptyDocumentIsDiscardedOnReplacement() {
            let view = makeMeasuredView()
            view.document = makeTokenDocument(pageCount: 0, loadToken: UUID())
            expect(view.applyFitZoom(.page)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.page

            view.document = makeTokenDocument(pageCount: 3, loadToken: UUID())

            expect(view.pendingFitZoom).to(beNil())
            expect(view.zoomScale) == 1.0
        }

        /// 그 가드가 진짜 "열자마자 맞춤"까지 죽이면 안 된다 — 문서가 **아예 없던**
        /// 상태에서 온 예약은 첫 문서에 적용된다. 위 테스트만 두면 예약을 통째로
        /// 버리는 구현도 통과한다.
        func testPendingFitFromNoDocumentStillAppliesToTheFirstDocument() {
            let view = makeMeasuredView()
            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width

            view.document = makeTokenDocument(pageCount: 3, loadToken: UUID())

            expect(view.pendingFitZoom).to(beNil())
            expect(view.documentContentView.frame.width * view.zoomScale)
                .to(beCloseTo(view.scrollView.contentSize.width, within: 0.5))
        }

        /// 쪽이 없어 예약된 맞춤은 **프로그레시브 전이에서** 적용돼야 한다.
        /// `isProgressiveUpdate` 가 `pages.count >=` 라 0 → N 이 그 분기로 오는데,
        /// 그 분기는 조기 반환하고 문서 대입은 레이아웃을 걸지 않으므로 소비하지
        /// 않으면 무관한 리사이즈까지 잠든다 (#78 리뷰).
        func testQueuedFitAppliesOnProgressiveSnapshotFromZeroPages() {
            let token = UUID()
            let view = makeMeasuredView()
            view.document = makeTokenDocument(pageCount: 0, loadToken: token)
            expect(view.applyFitZoom(.width)) == false
            expect(view.pendingFitZoom) == HwpZoomFit.width
            expect(view.zoomScale) == 1.0

            view.document = makeTokenDocument(pageCount: 3, loadToken: token)

            expect(view.pendingFitZoom).to(beNil())
            expect(view.documentContentView.frame.width * view.zoomScale)
                .to(beCloseTo(view.scrollView.contentSize.width, within: 0.5))
        }

        /// 맞출 수 없는 조합(거대 쪽 · 좁은 창)에서도 실패가 아니라 **범위 안에서
        /// 최선**이다 — 네이티브 한계를 넘겨 계산하므로 `0.25...5.0`의 네 번째
        /// 사본이 생기지 않는다.
        func testFitZoomClampsToNativeMagnificationLimits() {
            let view = makeMeasuredView(width: 100, height: 100)
            view.document = makeDocument(pageCount: 1)

            expect(view.applyFitZoom(.width)) == true

            expect(view.zoomScale) == view.scrollView.minMagnification
        }

        /// 메모 패널은 페이지 오른쪽 바깥에 그려지므로 클립 뷰에 잘리지
        /// 않으려면 콘텐츠 폭에 패널 폭이 포함되어야 한다.
        func testContentSizeIncludesMemoPanelWidth() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

            view.document = makeDocument(pageCount: 1, memoPanelWidth: 120)

            expect(view.documentContentView.frame.width) == 595 + 120
        }

        private func makeTokenDocument(pageCount: Int, loadToken: UUID?) -> HwpDocument {
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
                metadata: HwpDocumentMetadata(pageCount: pageCount, loadToken: loadToken),
                unsupportedElements: []
            )
        }

        func testProgressiveSnapshotKeepsLayersAndGrowsContent() {
            // 같은 loadToken + 페이지 증가 = 증분 적용 (레이어 유지, 크기 확장)
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            let token = UUID()
            view.document = makeTokenDocument(pageCount: 1, loadToken: token)
            let firstLayer = view.pageLayers[0]
            expect(firstLayer).toNot(beNil())

            view.document = makeTokenDocument(pageCount: 3, loadToken: token)

            expect(view.pageLayers[0]) === firstLayer
            expect(view.documentContentView.frame.height)
                == 842 * 3 + pageGap * 2
        }

        func testDifferentTokenResetsLayers() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.document = makeTokenDocument(pageCount: 2, loadToken: UUID())
            let firstLayer = view.pageLayers[0]

            view.document = makeTokenDocument(pageCount: 2, loadToken: UUID())

            expect(view.pageLayers[0]).toNot(beNil())
            expect(view.pageLayers[0]) !== firstLayer
        }
    }
#endif
