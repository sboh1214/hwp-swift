#if os(iOS)
    @testable import HwpKitNative
    import Nimble
    import XCTest

    final class HwpDocumentUIViewTests: XCTestCase {
        func testInitializesWithNoPageLayers() {
            let view = HwpDocumentUIView(frame: .zero)

            expect(view.pageLayers).to(beEmpty())
        }

        func testUpdateVisiblePagesAddsLayers() {
            let view = HwpDocumentUIView(frame: .zero)

            view.updateVisiblePages(range: 0 ..< 3)

            expect(view.pageLayers.keys.sorted()) == [0, 1, 2, 3, 4]
        }
    }
#endif
