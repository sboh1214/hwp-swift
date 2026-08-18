import CoreGraphics
import Foundation

/// 렌더된 축소판 비트맵 캐시 — **삽입순 + 바이트 예산 결정적 축출**.
///
/// `NSCache`를 쓰지 않는다: 그쪽은 예산 안이어도 즉시 축출할 수 있는 비결정
/// 정책이라, 가시 항목을 축출 → 재요청하는 무한 루프를 만든 전례가 있다
/// (#3, `HwpPageImageProvider`의 `resolved` 주석). 축소판은 그리기 비용이
/// 쪽당 수십 ms라 그 루프의 대가가 더 크다.
///
/// 정리는 **한 패스**다. 축출마다 `firstIndex` + `remove(at:)`을 부르면 스캔·이동이
/// 각각 O(N)이라 제거 수에 대해 이차가 된다 (`HwpPageImageProvider.retainOnlyImages`
/// doc의 실측: N=16,000에서 3,611ms → 한 패스 뒤 0.003s).
///
/// 키에 픽셀 폭이 들어가는 것은 같은 쪽을 다른 크기로 요청할 수 있어서다
/// (사이드바 폭 변경·Retina 배율 변경). 쪽 번호만으로 키를 잡으면 작은 축소판이
/// 큰 요청에 그대로 히트해 흐릿하게 남는다.
final class HwpThumbnailCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let pageIndex: Int
        let pixelWidth: Int
    }

    private struct Entry {
        let image: CGImage
        let bytes: Int
    }

    /// 축소판은 쪽당 수백 KB다 (A4 200px 폭 ≈ 226KB). 1,030쪽 문서를 전부
    /// 들고 있으면 230MB가 되므로 예산을 둔다 — 32MB면 200px 기준 약 145쪽이라
    /// 사이드바 화면 몫과 그 앞뒤 스크롤을 덮는다.
    static let defaultMaxBytes = 32_000_000

    private let lock = NSLock()
    private let maxBytes: Int
    private var storage: [Key: Entry] = [:]
    private var order: [Key] = []
    private var totalBytes = 0

    init(maxBytes: Int = HwpThumbnailCache.defaultMaxBytes) {
        self.maxBytes = max(1, maxBytes)
    }

    func image(for key: Key) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]?.image
    }

    func insert(_ image: CGImage, for key: Key) {
        let bytes = image.bytesPerRow * image.height
        lock.lock()
        defer { lock.unlock() }
        if let existing = storage.removeValue(forKey: key) {
            totalBytes -= existing.bytes
            order.removeAll { $0 == key }
        }
        storage[key] = Entry(image: image, bytes: bytes)
        order.append(key)
        totalBytes += bytes
        evictOverBudget(keeping: key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
        totalBytes = 0
    }

    /// 테스트 관측점.
    var currentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes
    }

    /// 테스트 관측점.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    /// lock 보유. 방금 넣은 항목(`keep`)은 남긴다 — 예산보다 큰 축소판 하나가
    /// 삽입 즉시 축출돼 매 요청이 재렌더가 되는 것을 막는다 (`insertResolved`의
    /// `keeping:`과 같은 이유). 순서 배열은 마지막에 **한 번만** 압축한다.
    private func evictOverBudget(keeping keep: Key) {
        guard totalBytes > maxBytes else { return }
        var dropped: Set<Key> = []
        for key in order {
            if totalBytes <= maxBytes {
                break
            }
            guard key != keep, let entry = storage.removeValue(forKey: key) else { continue }
            totalBytes -= entry.bytes
            dropped.insert(key)
        }
        guard !dropped.isEmpty else { return }
        order.removeAll { dropped.contains($0) }
    }
}
