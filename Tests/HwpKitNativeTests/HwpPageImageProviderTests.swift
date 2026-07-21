@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

final class HwpPageImageProviderTests: XCTestCase {
    private func variant(_ key: UInt32) -> String {
        HwpPageImageProvider.variantKey(key, nil)
    }

    /// 만석 디퍼드에서 pin(가시) 안 된 가장 오래된 항목을 축출한다 — 스크롤로
    /// 지나간 요청만 빼 가시 페이지의 placeholder를 방치하지 않는다 (R40 #3).
    func testDeferredEvictionSkipsPinnedAndPicksOldestUnpinned() {
        let deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = [(1, nil), (2, nil), (3, nil)]
        let pinned: Set<String> = [variant(1), variant(2)]

        let index = HwpPageImageProvider.deferredEvictionIndex(deferred, pinnedVariants: pinned)

        expect(index) == 2
    }

    /// 전부 pin이면 nil — 가시 요청을 축출하면 그 페이지의 어떤 키도 완료를 못
    /// 트리거해 placeholder가 영구 잔존한다 (R40 #3).
    func testDeferredEvictionReturnsNilWhenAllPinned() {
        let deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = [(1, nil), (2, nil)]
        let pinned: Set<String> = [variant(1), variant(2)]

        let index = HwpPageImageProvider.deferredEvictionIndex(deferred, pinnedVariants: pinned)

        expect(index).to(beNil())
    }

    /// pin이 없으면 가장 오래된(index 0) 항목을 축출한다.
    func testDeferredEvictionPicksOldestWhenNonePinned() {
        let deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = [(5, nil), (6, nil)]

        let index = HwpPageImageProvider.deferredEvictionIndex(deferred, pinnedVariants: [])

        expect(index) == 0
    }
}
