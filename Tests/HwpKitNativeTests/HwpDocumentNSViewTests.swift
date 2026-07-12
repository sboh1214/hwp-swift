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

        /// 메모 패널은 페이지 오른쪽 바깥에 그려지므로 클립 뷰에 잘리지
        /// 않으려면 콘텐츠 폭에 패널 폭이 포함되어야 한다.
        func testContentSizeIncludesMemoPanelWidth() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

            view.document = makeDocument(pageCount: 1, memoPanelWidth: 120)

            expect(view.documentContentView.frame.width) == 595 + 120
        }
    }
#endif
