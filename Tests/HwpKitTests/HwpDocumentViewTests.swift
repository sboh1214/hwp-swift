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
    func testPageChangeWritebackSuppressedWhileApplyingBinding() {
        var currentPage = 50
        let coordinator = HwpDocumentCoordinator(
            zoomScale: nil,
            currentPage: Binding(get: { currentPage }, set: { currentPage = $0 }),
            onHyperlinkTapped: nil,
            onUnsupportedElement: nil
        )
        // 첫 프로그레시브 스냅샷(page 0)의 echo는 적용 구간이라 무시 — 요청
        // 페이지(50)가 유지돼 이후 스냅샷에서 유실되지 않는다 (P2).
        coordinator.applyingBinding {
            coordinator.handlePageChanged(0)
        }
        expect(currentPage) == 50
        // 구간 밖 실제 스크롤은 바인딩에 반영한다.
        coordinator.handlePageChanged(24)
        expect(currentPage) == 25
    }

    #if os(macOS)
        @MainActor
        func testBindingsPropagateThroughNativeWrapper() {
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

            expect(currentPage) == 3
        }
    #endif
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
