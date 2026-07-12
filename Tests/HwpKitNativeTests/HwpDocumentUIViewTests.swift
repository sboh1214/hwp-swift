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
    }
#endif
