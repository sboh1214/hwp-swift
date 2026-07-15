import CoreGraphics
import CoreHwp
import Foundation
import HwpKitCore

/// 페이지 레이어의 `.drawImageReference` 명령을 실제 `CGImage`로 해석하는 공급자.
///
/// `HwpImageStore`(문서의 BinData 바이트) → `HwpImageAdapter`(디코딩) →
/// `HwpImageCache`(LRU + 동시 디코드 병합) 경로를 잇고, 디코딩이 끝나면
/// `onImageResolved`로 레이어 redraw를 요청한다.
///
/// 공급자는 문서마다 새로 만든다 — binItemId는 문서-로컬 키이므로
/// 캐시를 문서 간에 공유하면 다른 문서의 이미지가 재사용된다.
public final class HwpPageImageProvider: @unchecked Sendable {
    private let store: HwpImageStore
    private let cache: HwpImageCache
    private let adapter = HwpImageAdapter()
    /// 동시 디코드 수를 제한해 다수 이미지 페이지에서 임시 비트맵 합산이
    /// 프로세스를 고갈시키지 않게 한다 (개별 픽셀 한도만으론 합산을 못 막음, #8).
    private let decodeThrottle = HwpDecodeThrottle(limit: 3)
    private let lock = NSLock()
    /// 해석된 (binItemId, style) 변형 — 바이트 예산 내 삽입순 LRU. NSCache의
    /// 비결정 축출(예산 안이어도 즉시 축출)이 가시 이미지를 축출→재요청하는
    /// 무한 루프를 만들던 것을 결정적 예산 축출로 대체한다 (#3).
    private var resolved: [String: CGImage] = [:]
    private var resolvedOrder: [String] = []
    private var resolvedCost: [String: Int] = [:]
    private var resolvedBinItemId: [String: UInt32] = [:]
    private var resolvedBytes = 0
    /// 현재 가시 페이지가 참조하는 binItemId — 이 변형은 예산 초과여도 축출하지
    /// 않는다. 4장+ 이미지 페이지에서 가시 이미지가 축출→즉시 재요청되는 무한
    /// 사이클을 끊는다 (#2). 뷰가 updateVisiblePages에서 갱신한다.
    private var pinnedBinItemIds: Set<UInt32> = []
    /// 진행 상한으로 미룬 요청 — 슬롯이 나면 finishRequest가 재시도한다. 안 하면
    /// 다른 가시 레이어의 요청이 드롭된 채 회색으로 남는다 (#5).
    private var deferred: [(key: UInt32, style: HwpImageRenderStyle?)] = []
    private var deferredVariants: Set<String> = []
    private static let maximumDeferred = 64
    /// 다운샘플 상한 이미지 서너 장이 한 페이지 작업셋에 들어가도 루프가 안
    /// 생기게 256MB. 각 변형은 다운샘플로 ≤67MB라 메모리 총량은 유계다 (#3).
    private static let resolvedByteLimit = 256_000_000
    /// 동시 진행 요청 상한 — 이미지 변형이 많은 페이지가 무제한 Task·throttle
    /// 대기를 쌓지 않게 백프레셔로 막는다. 초과분은 다음 draw에서 재요청된다 (#2).
    private static let maximumInFlight = 12
    private var failedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    /// binItemId별 다운샘플 전 원본 픽셀 크기 — crop 스케일용 (#5).
    private var originalSizeByBinItemId: [UInt32: CGSize] = [:]
    /// binItemId별 가장 최근에 해석된 변형 키 (platformImage 폴백용)
    private var latestVariantByBinItemId: [UInt32: String] = [:]
    private var imageResolvedHandler: (@Sendable (UInt32) -> Void)?

    /// (binItemId, style) 변형의 결정론적 캐시 키
    private static func variantKey(_ binItemId: UInt32, _ style: HwpImageRenderStyle?) -> String {
        guard let style else { return "\(binItemId)" }
        return "\(binItemId)|\(style.cropLeft),\(style.cropTop),\(style.cropRight)," +
            "\(style.cropBottom)|\(style.brightness)|\(style.contrast)|\(style.effect.rawValue)"
    }

    /// 비동기 디코딩 완료 시 호출된다 (임의 스레드).
    public var onImageResolved: (@Sendable (UInt32) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return imageResolvedHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            imageResolvedHandler = newValue
        }
    }

    public init(store: HwpImageStore, cache: HwpImageCache) {
        self.store = store
        self.cache = cache
    }

    /// 이미 디코딩된 이미지를 동기 반환한다 (draw 경로용).
    public func cachedImage(for key: UInt32, style: HwpImageRenderStyle? = nil) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return resolved[Self.variantKey(key, style)]
    }

    /// 디코딩에 실패했던 키인지 여부 (placeholder 렌더 판단용).
    public func didFail(for key: UInt32, style: HwpImageRenderStyle? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedKeys.contains(Self.variantKey(key, style))
    }

    /// 비동기 디코딩 + 스타일 적용을 트리거한다. 이미 완료/진행 중이면 무시한다.
    public func requestImage(for key: UInt32, style: HwpImageRenderStyle? = nil) {
        guard cachedImage(for: key, style: style) == nil else { return }
        let variant = Self.variantKey(key, style)
        lock.lock()
        let alreadyHandled = failedKeys.contains(variant) || inFlightKeys.contains(variant)
        let atCapacity = inFlightKeys.count >= Self.maximumInFlight
        if !alreadyHandled, !atCapacity {
            inFlightKeys.insert(variant)
        } else if !alreadyHandled, atCapacity,
                  !deferredVariants.contains(variant), deferred.count < Self.maximumDeferred
        {
            // 진행 상한 초과: 드롭하지 않고 디퍼드 큐에 넣어 슬롯이 나면
            // finishRequest가 재시도한다 (드롭하면 가시 레이어가 회색으로 남음, #5).
            deferred.append((key, style))
            deferredVariants.insert(variant)
        }
        let shouldSpawn = !alreadyHandled && !atCapacity
        lock.unlock()
        guard shouldSpawn else { return }

        let store = store
        let cache = cache
        let adapter = adapter
        let throttle = decodeThrottle
        Task { [weak self] in
            // 동시 디코드 예산 확보/반납 (합산 임시 메모리 상한, #8)
            await throttle.acquire()
            defer { Task { await throttle.release() } }
            // 원본 디코드는 binItemId 단위로 공유 캐시하고,
            // 스타일 변형은 변형 키로 이 provider에만 저장한다.
            let decoded = await cache.fetch(key) { [weak self] in
                guard let data = store.data(forBinItemId: key) else { return nil }
                let binaryData = CoreHwpBinaryDataShim.binaryData(
                    named: store.extensionName(forBinItemId: key),
                    data: data
                )
                switch adapter.decode(binaryData: binaryData) {
                case let .success(decoded):
                    self?.recordOriginalSize(decoded.originalPixelSize, for: key)
                    return decoded.image
                case .failure:
                    return nil
                }
            }
            // 다운샘플됐을 수 있으므로 원본 크기로 crop을 스케일한다 (#5).
            let originalSize = self?.originalSize(for: key)
            let styled = decoded.map {
                HwpImageStyleRenderer.apply(style, to: $0, originalSize: originalSize)
            }
            let pinnedPixels = max(
                (styled?.width ?? 0) * (styled?.height ?? 0),
                (decoded?.width ?? 0) * (decoded?.height ?? 0)
            )
            self?.finishRequest(
                key: key,
                variant: variant,
                image: styled,
                cost: pinnedPixels * 4
            )
        }
    }

    private func finishRequest(key: UInt32, variant: String, image: CGImage?, cost: Int) {
        lock.lock()
        inFlightKeys.remove(variant)
        if let image {
            insertResolved(variant, binItemId: key, image: image, cost: max(1, cost))
            latestVariantByBinItemId[key] = variant
        } else {
            failedKeys.insert(variant)
        }
        // 슬롯이 났으니 미뤄 둔 요청 하나를 꺼내 재시도한다 (#5).
        let retry = dequeueDeferred()
        let handler = imageResolvedHandler
        lock.unlock()
        handler?(key)
        if let retry {
            requestImage(for: retry.key, style: retry.style)
        }
    }

    /// lock 보유. 슬롯이 남고 디퍼드가 있으면 하나 꺼낸다 (#5).
    private func dequeueDeferred() -> (key: UInt32, style: HwpImageRenderStyle?)? {
        guard inFlightKeys.count < Self.maximumInFlight, !deferred.isEmpty else { return nil }
        let next = deferred.removeFirst()
        deferredVariants.remove(Self.variantKey(next.key, next.style))
        return next
    }

    /// lock 보유. 변형의 binItemId가 가시 pin 집합에 있는지 (#2).
    private func isPinned(_ variant: String) -> Bool {
        guard let id = resolvedBinItemId[variant] else { return false }
        return pinnedBinItemIds.contains(id)
    }

    /// lock 보유. 예산 초과분을 가장 오래된 '비고정·비방금삽입' 변형부터
    /// 축출한다. 남은 게 전부 가시(pin)면 축출을 멈춘다 — 작업셋은 그려야
    /// 하므로 (그 대신 pin 집합이 가시 페이지로 유계라 총량이 유계, #2).
    private func insertResolved(_ variant: String, binItemId: UInt32, image: CGImage, cost: Int) {
        if let old = resolvedCost[variant] {
            resolvedBytes -= old
            resolvedOrder.removeAll { $0 == variant }
        }
        resolved[variant] = image
        resolvedCost[variant] = cost
        resolvedBinItemId[variant] = binItemId
        resolvedOrder.append(variant)
        resolvedBytes += cost
        while resolvedBytes > Self.resolvedByteLimit {
            guard let idx = resolvedOrder.firstIndex(where: { $0 != variant && !isPinned($0) })
            else { break }
            let evict = resolvedOrder.remove(at: idx)
            resolvedBytes -= resolvedCost.removeValue(forKey: evict) ?? 0
            resolved.removeValue(forKey: evict)
            resolvedBinItemId.removeValue(forKey: evict)
        }
    }

    /// 가시 페이지가 참조하는 binItemId 집합을 갱신한다 — 이 이미지는 예산
    /// 초과여도 축출하지 않아 축출→재요청 사이클을 막는다 (#2).
    public func setPinnedImages(_ ids: Set<UInt32>) {
        lock.lock()
        pinnedBinItemIds = ids
        lock.unlock()
    }

    private func recordOriginalSize(_ size: CGSize, for key: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        originalSizeByBinItemId[key] = size
    }

    private func originalSize(for key: UInt32) -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        return originalSizeByBinItemId[key]
    }

    /// PlatformImage(NSImage/UIImage) 편의 접근자 — 앱 레벨 소비용.
    /// 원본(스타일 없는) 변형이 없으면 가장 최근에 렌더된 스타일 변형을 돌려준다.
    public func platformImage(for key: UInt32) -> PlatformImage? {
        if let image = cachedImage(for: key) {
            return PlatformImage(hwpCgImage: image)
        }
        lock.lock()
        let image = latestVariantByBinItemId[key].flatMap { resolved[$0] }
        lock.unlock()
        guard let image else { return nil }
        return PlatformImage(hwpCgImage: image)
    }
}

/// HwpImageAdapter가 `CoreHwp.HwpBinaryData`를 받으므로 스토어 바이트를 감싸준다.
private enum CoreHwpBinaryDataShim {
    static func binaryData(named extensionName: String?, data: Data) -> CoreHwp.HwpBinaryData {
        CoreHwp.HwpBinaryData(
            name: "BIN0000.\(extensionName ?? "bin")",
            data: data
        )
    }
}

/// 동시 디코드 수를 `limit`개로 제한하는 비동기 세마포어 (#8).
/// 다수 이미지 페이지에서 모든 디코드가 동시에 큰 비트맵을 할당하는 것을 막는다.
actor HwpDecodeThrottle {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}
