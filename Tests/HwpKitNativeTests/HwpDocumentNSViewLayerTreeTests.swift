#if os(macOS)
    import AppKit
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    /// macOS 뷰 레이어 트리 회귀 스냅샷 (#125) — 시나리오·기대 트리는
    /// `HwpLayerTreeSnapshot` (iOS와 공유).
    @MainActor
    final class HwpDocumentNSViewLayerTreeTests: XCTestCase {
        func testLayerTreeMatchesSnapshot() async {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = HwpLayerTreeSnapshot.document()

            let search = HwpSearchController()
            search.publishInterval = .zero
            view.searchController = search
            search.search(text: "alpha")
            await expect(search.matchCount).toEventually(equal(6), timeout: .seconds(2))
            view.updateSearchOverlays()

            view.selectionController.begin(at: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 0
            ))
            view.selectionController.extend(to: HwpTextPosition(
                pageIndex: 0, blockIndex: 0, unitIndex: 0, characterOffset: 5
            ))

            let tree = HwpLayerTreeSnapshot.describe(
                sublayersOf: view.documentContentView.layer ?? CALayer(),
                // 뷰의 base 배율 산식과 같다 — 테스트 환경은 창이 없어
                // main screen 폴백 (zoom 1이라 effectiveContentsScale = base).
                baseScale: NSScreen.main?.backingScaleFactor ?? 2
            )

            expect(tree) == HwpLayerTreeSnapshot.expectedTree
        }
    }
#endif
