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
        func testOutOfRangePageBindingNormalizedForCompleteDocument() {
            // 최종 문서(isComplete)에 없는 페이지 요청(3쪽 문서에 100)은 클램프
            // 값으로 바인딩이 되돌아온다 — 억제된 echo 탓에 무효 바인딩이 남지
            // 않게 한다 (#6). 프로그레시브 중간 스냅샷은 정규화하지 않는다.
            var currentPage = 100
            let pages = (0 ..< 3).map { index in
                HwpPage(
                    size: CGSize(width: 595, height: 842),
                    margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                    blocks: [],
                    pageNumber: index + 1
                )
            }
            let document = HwpDocument(
                pages: pages,
                metadata: HwpDocumentMetadata(pageCount: 3, loadToken: UUID()),
                unsupportedElements: []
            )
            let view = HwpDocumentView(
                document: document,
                currentPage: Binding(get: { currentPage }, set: { currentPage = $0 })
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            hostingView.layoutSubtreeIfNeeded()

            expect(currentPage) == 3
        }

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
