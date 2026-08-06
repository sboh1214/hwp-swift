import Foundation

/// 동시 디코드 수를 `limit`개로 제한하는 비동기 세마포어 (#8).
/// 다수 이미지 페이지에서 모든 디코드가 동시에 큰 비트맵을 할당하는 것을 막는다.
actor HwpDecodeThrottle {
    private let limit: Int
    private var active = 0
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterId: UInt64 = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// 슬롯을 얻으면 true. 대기 중 취소되면 슬롯 없이 false — 취소된 대기자를
    /// 즉시 큐에서 제거해, 낡은 문서의 store/cache를 캡처한 태스크가 슬롯이
    /// 풀릴 때까지 상주하지 않게 한다 (P1). false면 release를 부르면 안 된다.
    func acquire() async -> Bool {
        if Task.isCancelled {
            return false
        }
        if active < limit {
            active += 1
            return true
        }
        let id = nextWaiterId
        nextWaiterId &+= 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // 등록 전 취소는 취소 플래그로 판정한다 — 플래그는 onCancel보다
                // 먼저 동기 설정되므로 별도 대기 집합 없이 즉시 실패한다.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UInt64) {
        // release()가 이미 슬롯을 이양해 재개한 대기자의 늦은 취소는 무시한다 —
        // id를 따로 기록하면 소비 불가능한 엔트리가 전역 스로틀에 누적된다 (P3).
        // 슬롯을 받은 뒤의 취소는 호출부의 isCancelled 확인 + release가 처리한다.
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(returning: false)
        }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            // 슬롯을 다음 대기자에게 이양 — active 불변으로 한도 유지.
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }
}
