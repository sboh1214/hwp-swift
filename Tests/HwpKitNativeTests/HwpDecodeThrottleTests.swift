@testable import HwpKitNative
import Nimble
import XCTest

final class HwpDecodeThrottleTests: XCTestCase {
    func testCancelledWaiterFailsWithoutConsumingSlot() async {
        // 취소가 대기자 등록 전/후 어느 시점에 와도 acquire는 false(슬롯 미보유)를
        // 보장해야 한다 — 낡은 provider 태스크가 대기열에 상주하지 않게 (P1).
        let throttle = HwpDecodeThrottle(limit: 1)
        let first = await throttle.acquire()
        expect(first) == true

        let waiter = Task { await throttle.acquire() }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        waiter.cancel()
        let acquired = await waiter.value
        expect(acquired) == false

        // 취소된 대기자가 슬롯을 소비하지 않았으므로 release 후 즉시 획득된다.
        await throttle.release()
        let after = await throttle.acquire()
        expect(after) == true
        await throttle.release()
    }

    func testReleaseHandsSlotToNextWaiter() async {
        let throttle = HwpDecodeThrottle(limit: 1)
        _ = await throttle.acquire()
        let waiter = Task { await throttle.acquire() }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        await throttle.release()
        let acquired = await waiter.value
        expect(acquired) == true
        await throttle.release()
    }
}
