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

    func testAcquireFailsImmediatelyWhenAlreadyCancelled() async {
        // 취소된 뒤 시작한 획득은 대기열에 들어가기도 전에 실패해야 한다 — 낡은
        // 문서의 태스크가 슬롯을 쥐면 살아 있는 페이지의 디코드가 그만큼 밀린다.
        let throttle = HwpDecodeThrottle(limit: 2)

        let task = Task { () -> Bool in
            // 취소를 관측한 뒤에만 부른다 — 잠들지 않고 결정론적으로 창을 만든다.
            while !Task.isCancelled {
                await Task.yield()
            }
            return await throttle.acquire()
        }
        task.cancel()
        let acquired = await task.value

        expect(acquired) == false
        // 슬롯이 소비되지 않았으므로 한도만큼 그대로 얻어진다
        let first = await throttle.acquire()
        let second = await throttle.acquire()
        expect(first) == true
        expect(second) == true
        await throttle.release()
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
