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

    /// 디큐는 pin(가시)된 가장 오래된 항목을 먼저 꺼낸다 — 스크롤로 지나간
    /// stale 이미지가 새로 보이는 요청보다 앞서 디코드되지 않는다 (R41 #3).
    func testDeferredDequeuePicksPinnedBeforeStale() {
        let deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = [(1, nil), (2, nil), (3, nil)]
        let pinned: Set<String> = [variant(2), variant(3)]

        let index = HwpPageImageProvider.deferredDequeueIndex(deferred, pinnedVariants: pinned)

        expect(index) == 1
    }

    /// pin이 없으면 가장 오래된(index 0) 항목을 꺼낸다.
    func testDeferredDequeuePicksOldestWhenNonePinned() {
        let deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = [(5, nil), (6, nil)]

        let index = HwpPageImageProvider.deferredDequeueIndex(deferred, pinnedVariants: [])

        expect(index) == 0
    }

    /// 캐시 purge에 취소된 디코드(nil)는 실패로 기록하지 않는다 — 기록하면
    /// failedKeys가 그 변형을 provider 수명 내내 placeholder로 묶는다. 진짜
    /// 디코드 실패는 종전처럼 기록해 매 draw 재디코드를 막는다 (R67).
    func testCachePurgeCancellationKeepsVariantRetryable() {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())

        provider.finishRequest(
            key: 1, variant: variant(1), generation: 0,
            image: nil, cost: 0, recordsFailure: false
        )
        provider.finishRequest(
            key: 2, variant: variant(2), generation: 0,
            image: nil, cost: 0, recordsFailure: true
        )

        expect(provider.didFail(for: 1)) == false
        expect(provider.didFail(for: 2)) == true
    }
}
