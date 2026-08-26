#if os(iOS)
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import UIKit
    import XCTest

    /// iOS 뷰 레이어 트리 회귀 스냅샷 (#125) — 시나리오·기대 트리는
    /// `HwpLayerTreeSnapshot` (macOS와 공유). 두 뷰의 레이어 구성이 대칭이라는
    /// 규약이 같은 기대 문자열로 검증된다. 선택 핸들 (#84)은 contentView 밖
    /// (뷰 본체의 서브뷰)이라 이 트리에 나타나지 않는 것까지가 계약이다.
    @MainActor
    final class HwpDocumentUIViewLayerTreeTests: XCTestCase {
        func testLayerTreeMatchesSnapshot() async {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutIfNeeded()
            view.document = HwpLayerTreeSnapshot.document()
            view.layoutIfNeeded()

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

            // 뷰의 base 배율 산식과 같다 — 테스트 환경은 창이 없어 트레잇
            // displayScale 폴백 (zoom 1이라 effectiveContentsScale = base).
            let displayScale = view.traitCollection.displayScale
            let tree = HwpLayerTreeSnapshot.describe(
                sublayersOf: view.contentView.layer,
                baseScale: displayScale > 0 ? displayScale : 2
            )

            expect(tree) == HwpLayerTreeSnapshot.expectedTree
        }
    }
#endif
