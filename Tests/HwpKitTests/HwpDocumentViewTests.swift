@testable import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import SwiftUI
import XCTest

#if os(macOS)
    import AppKit
#endif

final class HwpDocumentViewTests: XCTestCase {
    @MainActor
    func testDocumentViewBodyCompiles() {
        let view = HwpDocumentView(document: HwpDocument.empty)

        expect(String(describing: type(of: view.body))).toNot(beEmpty())
    }

    @MainActor
    func testBindingsPropagateThroughNativeWrapper() {
        #if os(macOS)
            var zoomScale = CGFloat(1.75)
            var currentPage = 0
            let view = HwpDocumentView(
                document: HwpDocument.empty,
                zoomScale: Binding(get: { zoomScale }, set: { zoomScale = $0 }),
                currentPage: Binding(get: { currentPage }, set: { currentPage = $0 })
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            hostingView.layoutSubtreeIfNeeded()

            guard let nativeView = hostingView.firstSubview(of: HwpDocumentNSView.self) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }

            expect(nativeView.zoomScale).to(beCloseTo(1.75))

            nativeView.updateVisiblePages(range: 2 ..< 3)

            expect(currentPage) == 2
        #else
            expect(true) == true
        #endif
    }
}

#if os(macOS)
    private extension NSView {
        func firstSubview<T: NSView>(of type: T.Type) -> T? {
            if let match = self as? T {
                return match
            }

            for subview in subviews {
                if let match = subview.firstSubview(of: type) {
                    return match
                }
            }

            return nil
        }
    }
#endif
