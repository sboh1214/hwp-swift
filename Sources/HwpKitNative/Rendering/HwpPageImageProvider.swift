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
    private var resolvedBytes = 0
    /// 현재 가시 페이지가 참조하는 변형 키 — 이 변형만 예산 초과여도 축출하지
    /// 않는다. binItemId가 아니라 (crop/effect별) 변형 단위라, 같은 ID의 옛 style
    /// 변형이 계속 pin돼 256MB를 넘기며 쌓이던 것을 막는다 (#1). 뷰가 updateVisiblePages에서 갱신.
    private var pinnedVariants: Set<String> = []
    /// 진행 중 디코드 task — provider 교체 시 취소해 옛 store/cache 강참조와
    /// 대형 디코드 누적을 끊는다 (#3).
    private var activeTasks: [String: Task<Void, Never>] = [:]
    /// provider 교체 세대 — cancelOutstanding에서 증가. 스폰됐지만 등록 전인
    /// 태스크도 세대 불일치로 무효 처리해 등록 레이스를 닫는다 (#5).
    private var generation = 0
    /// 등록 전에 완료된(캐시 히트/즉시 실패) 태스크 변형 — 등록 측이 완료된
    /// 핸들을 activeTasks에 넣지 않도록 표시한다 (완료/등록 핸드셰이크, #7).
    private var completedBeforeRegister: Set<String> = []
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
    static func variantKey(_ binItemId: UInt32, _ style: HwpImageRenderStyle?) -> String {
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
        } else if !alreadyHandled, atCapacity, !deferredVariants.contains(variant) {
            // 진행 상한 초과: 드롭하지 않고 디퍼드 큐에 넣어 슬롯이 나면
            // finishRequest가 재시도한다 (드롭하면 가시 레이어가 회색으로 남음, #5).
            // 디퍼드가 가득 차면 가장 오래된(대개 스크롤로 지나간) 항목을 빼고 새
            // 가시 요청을 넣는다 — 만석이라 새 요청이 유실되던 것을 막는다 (#2).
            if deferred.count >= Self.maximumDeferred {
                let stale = deferred.removeFirst()
                deferredVariants.remove(Self.variantKey(stale.key, stale.style))
            }
            deferred.append((key, style))
            deferredVariants.insert(variant)
        }
        let shouldSpawn = !alreadyHandled && !atCapacity
        let gen = generation
        lock.unlock()
        guard shouldSpawn else { return }

        let store = store
        let cache = cache
        let adapter = adapter
        let throttle = decodeThrottle
        // provider 교체 시 취소돼 새 디코드를 시작하지 않도록 진입점마다 확인한다 (#3).
        let task = Task { [weak self] in
            if Task.isCancelled {
                return
            }
            // 동시 디코드 예산 확보/반납 (합산 임시 메모리 상한, #8)
            await throttle.acquire()
            defer { Task { await throttle.release() } }
            // provider 교체(세대 불일치) 또는 해제 시 새 디코드를 시작하지 않는다.
            // dealloc으로 self가 nil이면 `== true`는 false라 통과했다 — nil을
            // stale로 취급해 store/cache/adapter가 붙든 채 디코드가 이어지지
            // 않게 한다 (self 강참조는 만들지 않는다, #5·#4).
            if Task.isCancelled || self?.isStale(gen) != false {
                return
            }
            // 원본 디코드는 binItemId 단위로 공유 캐시하고,
            // 스타일 변형은 변형 키로 이 provider에만 저장한다.
            let decoded = await cache.fetch(key) { [weak self] in
                if Task.isCancelled {
                    return nil
                }
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
            // 실제 백킹 스토어(bytesPerRow×height)로 과금한다 — 픽셀당 4바이트
            // 고정 가정은 16-bit 이미지(64bpp)를 절반으로 저계상해 예산을 우회한다 (P1).
            let pinnedBytes = max(
                (styled?.bytesPerRow ?? 0) * (styled?.height ?? 0),
                (decoded?.bytesPerRow ?? 0) * (decoded?.height ?? 0)
            )
            self?.finishRequest(
                key: key,
                variant: variant,
                generation: gen,
                image: styled,
                cost: pinnedBytes
            )
        }
        lock.lock()
        // 등록 전에 이미 완료됐으면(캐시 히트/즉시 실패) 완료된 핸들을 넣지 않는다 (#7).
        if completedBeforeRegister.remove(variant) == nil {
            activeTasks[variant] = task
        }
        lock.unlock()
    }

    private func finishRequest(
        key: UInt32,
        variant: String,
        generation gen: Int,
        image: CGImage?,
        cost: Int
    ) {
        lock.lock()
        inFlightKeys.remove(variant)
        if activeTasks.removeValue(forKey: variant) == nil {
            // 등록 전에 완료됨 — 등록 측이 완료된 핸들을 넣지 않도록 표시 (#7).
            completedBeforeRegister.insert(variant)
        }
        // provider가 교체됐으면(세대 불일치) 옛 문서 결과를 캐시에 넣지 않는다 (#5).
        guard gen == generation else {
            lock.unlock()
            return
        }
        if let image {
            insertResolved(variant, image: image, cost: max(1, cost))
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

    /// lock 보유. 변형이 가시 pin 집합에 있는지 (#1).
    private func isPinned(_ variant: String) -> Bool {
        pinnedVariants.contains(variant)
    }

    /// 세대 불일치(그 사이 provider가 교체됨) 여부 — lock을 잡고 확인한다 (#5).
    private func isStale(_ gen: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gen != generation
    }

    /// lock 보유. 변형을 캐시에 넣고 예산 초과분을 축출한다 (#1).
    private func insertResolved(_ variant: String, image: CGImage, cost: Int) {
        if let old = resolvedCost[variant] {
            resolvedBytes -= old
            resolvedOrder.removeAll { $0 == variant }
        }
        resolved[variant] = image
        resolvedCost[variant] = cost
        resolvedOrder.append(variant)
        resolvedBytes += cost
        evictOverBudget(keeping: variant)
    }

    /// lock 보유. 예산 초과분을 오래된 비고정 변형부터 축출하고, 그래도 초과면
    /// (가시 변형만으로 256MB 초과 — 한 페이지가 4장+ 대형 이미지를 참조) 가장
    /// 오래된 고정 변형도 축출해 하드 상한을 지킨다 (#1 — pin 작업셋 무한 증가
    /// 방지). keep(방금 삽입)은 남겨 즉시 축출→재요청 루프를 막는다. 고정 축출은
    /// 병적 페이지에서만 발동하며, 그 경우 재디코드 회전을 감수하고 OOM을 막는다.
    private func evictOverBudget(keeping keep: String? = nil) {
        while resolvedBytes > Self.resolvedByteLimit,
              let idx = resolvedOrder.firstIndex(where: { $0 != keep && !isPinned($0) })
        {
            evictVariant(at: idx)
        }
        while resolvedBytes > Self.resolvedByteLimit,
              let idx = resolvedOrder.firstIndex(where: { $0 != keep })
        {
            evictVariant(at: idx)
        }
    }

    /// lock 보유. resolvedOrder[idx] 변형을 캐시에서 제거하고 바이트를 갱신한다.
    private func evictVariant(at idx: Int) {
        let variant = resolvedOrder.remove(at: idx)
        resolvedBytes -= resolvedCost.removeValue(forKey: variant) ?? 0
        resolved.removeValue(forKey: variant)
    }

    /// 가시 페이지가 참조하는 변형 키 집합을 갱신한다 — 이 변형은 예산 초과여도
    /// 축출하지 않아 축출→재요청 사이클을 막는다 (#1).
    public func setPinnedImages(_ variants: Set<String>) {
        lock.lock()
        pinnedVariants = variants
        // pin이 바뀌면 방금 unpin된 항목을 예산 내로 정리한다 (#1).
        evictOverBudget()
        lock.unlock()
    }

    /// 진행 중인 모든 디코드를 취소하고 대기/pin 상태를 비운다 — provider 교체
    /// 시 호출해 옛 store/cache 강참조와 대형 디코드 누적을 끊는다 (#3).
    public func cancelOutstanding() {
        lock.lock()
        // 세대를 올려 스폰됐지만 등록 전인 태스크도 무효화한다 (등록 레이스, #5).
        generation &+= 1
        completedBeforeRegister.removeAll()
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        inFlightKeys.removeAll()
        deferred.removeAll()
        deferredVariants.removeAll()
        pinnedVariants.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
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
