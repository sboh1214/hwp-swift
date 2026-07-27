import CoreGraphics
import Foundation

/// 캐시 항목: 디코드된 비트맵 + 다운샘플 전 원본 픽셀 크기.
/// crop 좌표는 원본 픽셀 기준으로 저작되므로, 크기가 이미지와 함께 캐시를
/// 타지 않으면 warm 캐시 히트(교체 provider)에서 crop 스케일 기준이
/// 사라진다 (R63 #2).
public struct HwpCachedImage: @unchecked Sendable {
    public let image: CGImage
    public let originalPixelSize: CGSize

    public init(image: CGImage, originalPixelSize: CGSize? = nil) {
        self.image = image
        self.originalPixelSize = originalPixelSize
            ?? CGSize(width: image.width, height: image.height)
    }
}

public actor HwpImageCache {
    private struct CachedEntry {
        let cached: HwpCachedImage
        let bytes: Int
        var timestamp: Date
    }

    private let maxBytes: Int
    private var storage: [UInt32: CachedEntry] = [:]
    private var totalBytes: Int = 0

    /// In-flight decode tasks keyed by binaryDataIndex — coalesces concurrent fetches.
    /// 각 엔트리에 단조 id를 달아, 완료한 fetch가 (clear가 자기 태스크를 지운 뒤
    /// 다른 fetch가 등록한) 새 태스크를 key만 보고 실수로 지우지 않게 한다 (P2).
    private var inFlight: [UInt32: InFlightDecode] = [:]

    /// 진행 중 공유 디코드. waiters는 이 디코드를 기다리는 fetch 수 —
    /// 대기자 하나의 취소로 공유 태스크를 죽이면 남은 대기자가 nil을 받아
    /// 실패로 기록되므로, 마지막 대기자가 사라질 때만 취소한다 (R68).
    private struct InFlightDecode {
        let id: UInt64
        let task: Task<HwpCachedImage?, Never>
        var waiters: Int
    }

    private var nextInFlightId: UInt64 = 0

    /// clear() 세대. fetch가 디코드 await 전 값을 캡처해, await 사이 clear()가
    /// 끼어들어(actor 재진입) 세대가 바뀌면 디코드 결과를 storage에 재삽입하지
    /// 않는다 — 메모리 경고 purge가 신뢰성 있게 비우게 한다 (P2).
    private var generation: UInt64 = 0

    /// 다운샘플 상한(4096²·4 ≈ 67MB) 이미지 두 장(≈134MB)이 한 페이지 작업셋에
    /// 들어가도 축출→재디코드 루프가 안 생기게 256MB로 둔다 (#3).
    public init(maxBytes: Int = 256_000_000) {
        self.maxBytes = maxBytes
    }

    public func fetch(
        _ key: UInt32,
        decode: @escaping @Sendable () async -> HwpCachedImage?
    ) async -> HwpCachedImage? {
        if var entry = storage[key] {
            entry.timestamp = Date()
            storage[key] = entry
            return entry.cached
        }

        if let existing = inFlight[key] {
            // 취소는 대기자 카운트로 전파한다 — 독립 호출자(같은 캐시를 공유하는
            // 두 provider)가 병합됐을 때 한쪽 취소가 공유 디코드를 죽이면 남은
            // 호출자가 nil을 받아 영구 실패로 기록된다 (R68). 마지막 대기자가
            // 사라지면 releaseWaiter가 취소해 옛 문서 대형 디코드 잔존을 막는다 (#2).
            inFlight[key]?.waiters += 1
            let sharedId = existing.id
            let cached = await withTaskCancellationHandler {
                await existing.task.value
            } onCancel: {
                Task { await self.releaseWaiter(key, id: sharedId) }
            }
            if inFlight[key]?.id == sharedId {
                inFlight[key]?.waiters -= 1
            }
            return cached
        }

        let task = Task<HwpCachedImage?, Never> {
            await decode()
        }
        let taskId = nextInFlightId
        nextInFlightId &+= 1
        inFlight[key] = InFlightDecode(id: taskId, task: task, waiters: 1)
        let startGeneration = generation
        // 취소되면 (남은 대기자가 없을 때) 디코드 태스크를 취소해 옛 문서의 대형
        // 디코드가 계속 살아 있지 않게 한다 (#2, R68). 디코드 클로저는
        // Task.isCancelled를 확인한다.
        let cached = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.releaseWaiter(key, id: taskId) }
        }
        // 이 fetch가 등록한 태스크가 아직 그 key의 엔트리일 때만 제거한다 — clear가
        // 이 태스크를 지운 뒤 다른 fetch가 새 태스크를 등록했으면 그것을 지우지
        // 않아 coalescing·바이트 회계가 깨지지 않는다 (P2).
        if inFlight[key]?.id == taskId {
            inFlight.removeValue(forKey: key)
        }

        // clear()가 디코드 await 중 실행됐으면(세대 변경) 캐시를 재오염하지 않는다
        // — 호출자에겐 이미지를 돌려주되 storage 재삽입은 건너뛴다 (actor 재진입, P2).
        guard generation == startGeneration else { return cached }

        if let cached {
            let bytes = cached.image.bytesPerRow * cached.image.height
            storage[key] = CachedEntry(cached: cached, bytes: bytes, timestamp: Date())
            totalBytes += bytes
            await evict(target: maxBytes)
        }

        return cached
    }

    public func evict(target: Int) async {
        guard totalBytes > target else { return }

        let sorted = storage.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            storage.removeValue(forKey: key)
            totalBytes -= entry.bytes
            if totalBytes <= target {
                break
            }
        }
    }

    public func clear() async {
        storage.removeAll()
        totalBytes = 0
        generation &+= 1
        // in-flight 디코드도 취소·제거한다 — 그러지 않으면 clear 이후의 fetch가
        // clear 이전 태스크에 join해 값만 받고 (세대 게이트로) 캐시되지 않아
        // 다음 draw에서 재디코드가 강제된다 (P2). post-clear fetch는 새 디코드를 연다.
        for entry in inFlight.values {
            entry.task.cancel()
        }
        inFlight.removeAll()
    }

    /// 대기자 하나가 취소됐음을 알린다. 마지막 대기자면 공유 디코드를 취소하고
    /// 엔트리를 지운다 — 뒤이은 fetch는 취소된 태스크에 병합되지 않고 새 디코드를
    /// 연다. id를 확인해 그 사이 교체된 엔트리를 건드리지 않는다 (R68).
    private func releaseWaiter(_ key: UInt32, id: UInt64) {
        guard var entry = inFlight[key], entry.id == id else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            inFlight.removeValue(forKey: key)
            entry.task.cancel()
        } else {
            inFlight[key] = entry
        }
    }

    /// key의 현재 대기자 수 (진행 중 디코드가 없으면 0) — 병합 상태 관측용.
    func waiterCount(_ key: UInt32) -> Int {
        inFlight[key]?.waiters ?? 0
    }

    /// clear() 호출마다 증가하는 purge 세대. 소비자가 fetch 전후로 비교해
    /// "내 디코드가 purge에 취소됐는지"를 판별한다 — purge는 취소일 뿐
    /// 디코드 실패가 아니므로 재시도 가능으로 남아야 한다 (R67).
    public func purgeGeneration() async -> UInt64 {
        generation
    }

    public func count() async -> Int {
        storage.count
    }

    public func currentBytes() async -> Int {
        totalBytes
    }
}
