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
    }
#endif
