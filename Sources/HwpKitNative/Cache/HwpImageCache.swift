import CoreGraphics
import Foundation

public actor HwpImageCache {
    private struct CachedEntry {
        let image: CGImage
        let bytes: Int
        var timestamp: Date
    }

    private let maxBytes: Int
    private var storage: [UInt32: CachedEntry] = [:]
    private var totalBytes: Int = 0

    /// In-flight decode tasks keyed by binaryDataIndex — coalesces concurrent fetches.
    private var inFlight: [UInt32: Task<CGImage?, Never>] = [:]

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
        decode: @escaping @Sendable () async -> CGImage?
    ) async -> CGImage? {
        if var entry = storage[key] {
            entry.timestamp = Date()
            storage[key] = entry
            return entry.image
        }

        if let existing = inFlight[key] {
            // 호출자 취소를 병합된 디코드로 전파한다 (#2). provider 교체 시
            // cancelOutstanding이 모든 대기자를 취소하므로 공유 태스크 취소가 옳다.
            return await withTaskCancellationHandler {
                await existing.value
            } onCancel: {
                existing.cancel()
            }
        }

        let task = Task<CGImage?, Never> {
            await decode()
        }
        inFlight[key] = task
        let startGeneration = generation
        // 취소되면 디코드 태스크를 취소해 옛 문서의 대형 디코드가 계속 살아
        // 있지 않게 한다 (#2). 디코드 클로저는 Task.isCancelled를 확인한다.
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        inFlight.removeValue(forKey: key)

        // clear()가 디코드 await 중 실행됐으면(세대 변경) 캐시를 재오염하지 않는다
        // — 호출자에겐 이미지를 돌려주되 storage 재삽입은 건너뛴다 (actor 재진입, P2).
        guard generation == startGeneration else { return image }

        if let image {
            let bytes = image.width * image.height * 4
            storage[key] = CachedEntry(image: image, bytes: bytes, timestamp: Date())
            totalBytes += bytes
            await evict(target: maxBytes)
        }

        return image
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
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    public func count() async -> Int {
        storage.count
    }

    public func currentBytes() async -> Int {
        totalBytes
    }
}
