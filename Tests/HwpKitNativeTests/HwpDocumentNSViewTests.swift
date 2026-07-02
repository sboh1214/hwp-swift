#if os(macOS)
    import AppKit
    import Foundation
    @testable import HwpKitNative
    import Nimble
    import XCTest

    final class HwpDocumentNSViewTests: XCTestCase {
        func testPageLayersAreEmptyInitially() {
            let view = HwpDocumentNSView()

            expect(view.pageLayers.isEmpty) == true
            expect(view.layer?.sublayers?.isEmpty ?? true) == true
        }

        func testUpdateVisiblePagesAddsVisibleLayers() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))

            view.updateVisiblePages(range: 0 ..< 3)

            expect(view.pageLayers.keys.sorted()) == [0, 1, 2]
            expect(view.layer?.sublayers?.count) == 3
        }

        func testUpdateVisiblePagesDiffsDistantLayers() {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
            view.updateVisiblePages(range: 0 ..< 3)

            view.updateVisiblePages(range: 5 ..< 8)

            expect(view.pageLayers.keys.sorted()) == [5, 6, 7]
            expect(view.layer?.sublayers?.count) == 3
        }
    }
#endif
