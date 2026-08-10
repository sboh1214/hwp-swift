import CoreGraphics
import CoreHwp
import Foundation
import HwpKitCore

// 락 아래 가변 상태를 한 타입에 모아 두느라 길다. 쪼개면 그 상태를 internal로
// 올려야 하고(다른 파일에서 private 접근 불가) 그 순간 "락 없이 만질 수 없다"가
// 구조가 아니라 관례가 된다.
// swiftlint:disable file_length

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
    /// provider 간 공유(static) — cancelOutstanding은 동기 adapter.decode에 이미
    /// 들어간 태스크를 못 끊으므로, 문서 교체마다 새 스로틀이면 낡은 provider들의
    /// 디코드가 병행돼 피크 메모리가 교체 횟수에 비례한다 (P1).
    private static let decodeThrottle = HwpDecodeThrottle(limit: 3)
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
    /// 백프레셔 한도 3종. 프로덕션은 이 기본값 그대로이고, **인스턴스 프로퍼티인
    /// 것은 테스트가 값을 낮춰 초과·축출 경로를 작은 입력으로 재현하기
    /// 위해서다** (`HwpPageLayer.cachedLineBudget`과 같은 이유).
    var maximumDeferred = 64
    /// 다운샘플 상한 이미지 서너 장이 한 페이지 작업셋에 들어가도 루프가 안
    /// 생기게 256MB. 각 변형은 다운샘플로 ≤67MB라 메모리 총량은 유계다 (#3).
    static let defaultResolvedByteLimit = 256_000_000
    var resolvedByteLimit = HwpPageImageProvider.defaultResolvedByteLimit
    /// 동시 진행 요청 상한 — 이미지 변형이 많은 페이지가 무제한 Task·throttle
    /// 대기를 쌓지 않게 백프레셔로 막는다. 초과분은 다음 draw에서 재요청된다 (#2).
    var maximumInFlight = 12

    private var failedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    /// binItemId별 가장 최근에 해석된 변형 키 (platformImage 폴백용)
    private var latestVariantByBinItemId: [UInt32: String] = [:]
    private var imageResolvedHandler: (@Sendable (UInt32) -> Void)?
    /// hard bound 초과로 요청을 드롭한 적이 있는지 — 자리가 나면 전체 가시
    /// 레이어를 재드로우해 드롭된 요청을 재시도시킨다 (R42 #1).
    private var didDropDeferred = false
    private var deferredCapacityHandler: (@Sendable () -> Void)?
    /// 변형 확정(성공/실패)을 기다리는 `resolveImage` 대기자 (#74). 화면 없는
    /// 경로는 레이어 재드로우가 없어 draw → requestImage 재시도 루프를 못 쓰므로
    /// 완료를 여기서 직접 기다린다.
    private var settleWaiters: [String: [VariantWaiter]] = [:]
    /// 요청 하나가 확정될 때마다 증가하는 진행 토큰. 드롭된 요청은 확정 통보가
    /// 영영 오지 않으므로(백프레셔), 대기자는 이 토큰으로 재시도 시점을 잡는다.
    private var progressToken: UInt64 = 0
    /// 변형별 확정 횟수. 요청과 대기자 등록 **사이**에 확정이 지나가고 그 결과가
    /// 다른 변형의 삽입에 축출되면, 등록 측은 캐시에도 추적에도 없는 상태만 보게
    /// 돼 확정을 못 본 것으로 오인한다 — 그러면 아래 축출 라이브락 컷이 통째로
    /// 우회된다. 요청 전 스냅샷과의 차이가 그 확정을 증언한다.
    private var settleEpochs: [String: UInt64] = [:]
    /// 변형별 진행 중인 `resolveImage` 수. 해석자가 대기에 등록되기 **전** 구간이
    /// 곧 위 에포크가 메우려는 창이라, 그 구간에 프루닝이 항목을 지우면 신호가
    /// 통째로 사라진다 — 스냅샷이 0인 첫 해석에서 특히 그렇다 (지운 뒤 조회
    /// 기본값도 0이라 비교가 같아져 버린다).
    private var activeResolvers: [String: Int] = [:]
    private var progressWaiters: [ProgressWaiter] = []
    private var nextWaiterId: UInt64 = 0

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

    /// 디퍼드 큐가 만석이라 드롭했던 요청을 재시도할 자리가 났을 때 호출된다
    /// (임의 스레드) — 뷰가 전체 가시 레이어를 재드로우해, 유일 이미지가
    /// 드롭돼 재드로우를 못 받던 레이어도 재요청하게 한다 (R42 #1).
    public var onDeferredCapacityAvailable: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return deferredCapacityHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            deferredCapacityHandler = newValue
        }
    }

    public init(store: HwpImageStore, cache: HwpImageCache) {
        self.store = store
        self.cache = cache
    }

    /// 뷰가 다른 문서 할당 없이 제거되면 아무도 cancelOutstanding을 부르지 않아,
    /// store/cache를 강참조한 in-flight 태스크가 살아남는다 — 핸들만 놓는 것으론
    /// unstructured Task가 안 끊기므로 해제 시 직접 취소한다 (R47 #3).
    deinit {
        cancelOutstanding()
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
    public func requestImage(
        for key: UInt32,
        style: HwpImageRenderStyle? = nil,
        expectedGeneration: Int? = nil
    ) {
        guard cachedImage(for: key, style: style) == nil else { return }
        let variant = Self.variantKey(key, style)
        lock.lock()
        // expectedGeneration은 디퍼드 재시도의 디큐 시점 세대다 — 락 밖 재시도
        // 창에서 cancelOutstanding이 세대를 올린 요청은 등록 전에 기각된다.
        // 아니면 낡은 provider가 새 세대 태그로 디코드를 시작·보유한다 (#2).
        if let expectedGeneration, generation != expectedGeneration {
            lock.unlock()
            return
        }
        let alreadyHandled = failedKeys.contains(variant) || inFlightKeys.contains(variant)
        let atCapacity = inFlightKeys.count >= maximumInFlight
        var orphanedWaiters: [VariantWaiter] = []
        if !alreadyHandled, !atCapacity {
            inFlightKeys.insert(variant)
        } else if !alreadyHandled, atCapacity, !deferredVariants.contains(variant) {
            orphanedWaiters = enqueueDeferred(key: key, style: style, variant: variant)
        }
        let shouldSpawn = !alreadyHandled && !atCapacity
        let gen = generation
        lock.unlock()
        // 축출된 변형은 확정 통보를 받을 주체가 사라졌다 — 깨우지 않으면 영구
        // 대기다. 재개는 lock 밖에서 (재개가 같은 락을 다시 잡는다).
        for waiter in orphanedWaiters {
            waiter.continuation.resume(returning: .untracked)
        }
        guard shouldSpawn else { return }

        let store = store
        let cache = cache
        let adapter = adapter
        let throttle = Self.decodeThrottle
        // provider 교체 시 취소돼 새 디코드를 시작하지 않도록 진입점마다 확인한다 (#3).
        let task = Task { [weak self] in
            if Task.isCancelled {
                return
            }
            // 동시 디코드 예산 확보/반납 (합산 임시 메모리 상한, #8). 취소로
            // 슬롯을 못 얻으면 반납 없이 종료한다 (P1).
            guard await throttle.acquire() else { return }
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
            let purgeGenerationBeforeFetch = await cache.purgeGeneration()
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
                    return HwpCachedImage(
                        image: decoded.image, originalPixelSize: decoded.originalPixelSize
                    )
                case .failure:
                    return nil
                }
            }
            // 다운샘플됐을 수 있으므로 원본 크기로 crop을 스케일한다 (#5). 원본
            // 크기는 캐시 값이 나른다 — provider 로컬 저장이면 warm 캐시 히트
            // (교체 provider)에서 사라진다 (R63 #2).
            let styled = decoded.map {
                HwpImageStyleRenderer.apply(
                    style, to: $0.image, originalSize: $0.originalPixelSize
                )
            }
            // 실제 백킹 스토어(bytesPerRow×height)로 과금한다 — 픽셀당 4바이트
            // 고정 가정은 16-bit 이미지(64bpp)를 절반으로 저계상해 예산을 우회한다 (P1).
            //
            // 과금 대상은 이 변형이 **자기 몫으로** 든 래스터뿐이다. 디코드 원본은
            // `HwpImageCache`가 binItemId 하나로 한 번만 보유해 변형들이 공유한다.
            // 그것까지 세면 같은 바이트가 변형 수만큼 중복 계상돼, 메모리에
            // 넉넉히 들어가는 페이지가 예산 초과로 판정되고 내보내기가 실패한다
            // (실측: 4MB 원본의 100×100 crop 4장이 8MB 예산에서 16MB로 계상돼
            // 2장 축출 → `pageImagesExceedMemoryBudget`). 원본 쪽 상한은 캐시가
            // 제 예산으로 따로 묶는다 — 이 층 구분이 곧 문서가 적어 둔 보장
            // ("현재 페이지 변형 + 원본 캐시(≤ 같은 예산)")다.
            let pinnedBytes = (styled?.bytesPerRow ?? 0) * (styled?.height ?? 0)
            // 캐시 purge(clear)는 in-flight 디코드 태스크를 취소해 nil을 낸다 —
            // 디코드 실패가 아니므로 실패로 기록하면 그 변형이 provider 수명
            // 내내 placeholder로 남는다. purge 세대가 바뀌었으면 재시도 가능
            // 으로 남긴다 (R67).
            let purgedDuringFetch = await cache.purgeGeneration() != purgeGenerationBeforeFetch
            self?.finishRequest(
                key: key,
                variant: variant,
                generation: gen,
                image: styled,
                cost: pinnedBytes,
                recordsFailure: !purgedDuringFetch
            )
        }
        lock.lock()
        // 스폰~등록 사이에 cancelOutstanding이 세대를 올렸으면(등록 레이스) 등록
        // 대신 취소한다 — activeTasks에 없어 그 취소를 놓친 stale 태스크가 낡은
        // store/cache를 강참조한 채 throttle 슬롯을 기다리는 것을 막는다 (R47 #2).
        let stale = gen != generation
        if stale {
            completedBeforeRegister.remove(variant)
        } else if completedBeforeRegister.remove(variant) == nil {
            // 등록 전에 이미 완료됐으면(캐시 히트/즉시 실패) 완료된 핸들을 넣지 않는다 (#7).
            activeTasks[variant] = task
        }
        lock.unlock()
        if stale {
            task.cancel()
        }
    }

    /// recordsFailure가 false면 nil 결과를 실패로 기록하지 않는다 — 캐시 purge에
    /// 취소된 디코드는 재시도 가능으로 남아야 한다 (R67).
    func finishRequest(
        key: UInt32,
        variant: String,
        generation gen: Int,
        image: CGImage?,
        cost: Int,
        recordsFailure: Bool = true
    ) {
        lock.lock()
        // stale 완료(취소를 지나쳐 완주한 구세대 태스크)는 어떤 요청 상태도
        // 변이하지 않는다 — 구세대 몫은 cancelOutstanding이 이미 비웠으므로,
        // 여기서 지우는 variant 키는 같은 이름으로 등록된 신세대 요청의 것일 수
        // 있다 (중복 디코드 허용·신 태스크 미추적, #5·#7, R64 #1).
        guard gen == generation else {
            lock.unlock()
            return
        }
        inFlightKeys.remove(variant)
        if activeTasks.removeValue(forKey: variant) == nil {
            // 등록 전에 완료됨 — 등록 측이 완료된 핸들을 넣지 않도록 표시 (#7).
            completedBeforeRegister.insert(variant)
        }
        if let image {
            insertResolved(variant, image: image, cost: max(1, cost))
            latestVariantByBinItemId[key] = variant
        } else if recordsFailure {
            failedKeys.insert(variant)
        }
        // 슬롯이 났으니 미뤄 둔 요청 하나를 꺼내 재시도한다 (#5). 디큐 시점
        // 세대를 함께 넘겨 락 밖 재시도 창의 provider 교체를 기각한다 (#2).
        let retry = dequeueDeferred()
        let retryGeneration = generation
        let handler = imageResolvedHandler
        // 드롭이 있었고 이제 디퍼드에 자리가 났으면, 전체 가시 레이어 재드로우를
        // 알려 드롭된 요청(특히 유일 이미지가 드롭된 레이어)을 재시도시킨다 (R42 #1).
        let capacityHandler = didDropDeferred && deferred.count < maximumDeferred
            ? deferredCapacityHandler : nil
        if capacityHandler != nil {
            didDropDeferred = false
        }
        // 확정 통보 + 진행 토큰 — 화면 없는 경로의 대기자를 깨운다 (#74).
        // **기록이 없으면 확정이 아니다**: 캐시 purge에 취소된 디코드는 resolved
        // 에도 failedKeys에도 안 들어가므로(R67) 재시도 가능으로 깨워야 한다.
        // .settled로 깨우면 대기자가 그것을 예산 축출로 보고 포기한다.
        let recorded = image != nil || recordsFailure
        if recorded {
            settleEpochs[variant, default: 0] &+= 1
        }
        let waiters = takeWaiters(settledVariant: variant)
        lock.unlock()
        Self.resume(
            variantWaiters: waiters.variant,
            as: recorded ? .settled : .untracked,
            progress: waiters.progress
        )
        handler?(key)
        capacityHandler?()
        if let retry {
            requestImage(
                for: retry.key, style: retry.style, expectedGeneration: retryGeneration
            )
        }
    }

    /// lock 보유. 진행 상한 초과 요청을 디퍼드 큐에 넣는다 (드롭하면 가시
    /// 레이어가 회색으로 남음, #5). hard bound(maximumDeferred) 유지: 만석이면
    /// pin 안 된(스크롤로 지나간) 가장 오래된 항목을 축출해 자리를 낸다. 가시
    /// (pin) 요청을 빼면 그 페이지 placeholder가 영구 잔존하므로 축출하지
    /// 않고(R40 #3), 전부 pin이라 뺄 게 없으면 새 요청을 드롭해 큐가 무한정
    /// 자라지 않게 한다(R41 #2). dequeueDeferred가 pin을 우선 비우므로(R41 #3)
    /// 만석-전부-pin은 일시적이고, 자리가 나면 레이어 재드로우가 재요청한다.
    private func enqueueDeferred(
        key: UInt32,
        style: HwpImageRenderStyle?,
        variant: String
    ) -> [VariantWaiter] {
        var orphaned: [VariantWaiter] = []
        var canEnqueue = deferred.count < maximumDeferred
        if !canEnqueue,
           let evictIndex = Self.deferredEvictionIndex(deferred, pinnedVariants: pinnedVariants)
        {
            let stale = deferred.remove(at: evictIndex)
            let staleVariant = Self.variantKey(stale.key, stale.style)
            deferredVariants.remove(staleVariant)
            // 축출된 변형은 in-flight도 디퍼드도 아니게 되어 finishRequest가
            // 영영 오지 않는다 — 그 확정을 기다리던 대기자를 함께 내보낸다.
            orphaned = settleWaiters.removeValue(forKey: staleVariant) ?? []
            canEnqueue = true
        }
        if canEnqueue {
            deferred.append((key, style))
            deferredVariants.insert(variant)
        } else {
            // 만석+전부-pin이라 드롭됨 — 자리가 나면 finishRequest가 전체 가시
            // 레이어 재드로우를 알려 이 요청을 재시도시킨다 (R42 #1).
            didDropDeferred = true
            // 이 변형에 **이미 대기자가 있을 수 있다**: finishRequest가 디퍼드에서
            // 꺼낸 재시도는 락 밖에서 다시 요청되는데, 그 사이 두 큐가 차면 여기로
            // 온다. 그때 대기자는 디퍼드에 있던 동안 등록된 것이라, 드롭된 채
            // 남겨 두면 확정 통보가 영영 오지 않는다 (축출 경로와 같은 이유).
            orphaned += settleWaiters.removeValue(forKey: variant) ?? []
        }
        return orphaned
    }

    /// lock 보유. 슬롯이 남고 디퍼드가 있으면 하나 꺼낸다 (#5). pin(가시)된
    /// 항목을 먼저 꺼내 가시 placeholder가 스크롤로 지나간 이미지 뒤에서
    /// 대기하지 않게 한다 (R41 #3).
    private func dequeueDeferred() -> (key: UInt32, style: HwpImageRenderStyle?)? {
        guard inFlightKeys.count < maximumInFlight, !deferred.isEmpty else { return nil }
        let index = Self.deferredDequeueIndex(deferred, pinnedVariants: pinnedVariants)
        let next = deferred.remove(at: index)
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
    /// 재드로우가 없는 경로는 그 회전으로 되살릴 기회가 없으므로, **상한을 끄는
    /// 대신** draw 직전에 잔존 여부를 확인해 오류로 끝낸다 (`HwpPDFRenderer`) —
    /// 상한을 끄면 한 페이지 작업셋이 프로세스를 고갈시킬 수 있다.
    /// 순서 배열은 훑으면서 지우지 않고 **마지막에 한 번** 압축한다. 축출마다
    /// `firstIndex` + `remove(at:)`을 부르면 스캔·이동이 각각 O(N)이라 제거 수에
    /// 대해 이차가 된다 (`retainOnlyImages`와 같은 이유 — 실측은 그쪽 doc 참조).
    private func evictOverBudget(keeping keep: String? = nil) {
        guard resolvedBytes > resolvedByteLimit else { return }
        var dropped: Set<String> = []
        for variant in resolvedOrder {
            if resolvedBytes <= resolvedByteLimit {
                break
            }
            guard variant != keep, !isPinned(variant) else { continue }
            dropResolved(variant)
            dropped.insert(variant)
        }
        for variant in resolvedOrder {
            if resolvedBytes <= resolvedByteLimit {
                break
            }
            guard variant != keep, !dropped.contains(variant) else { continue }
            dropResolved(variant)
            dropped.insert(variant)
        }
        guard !dropped.isEmpty else { return }
        resolvedOrder.removeAll { dropped.contains($0) }
    }

    /// lock 보유. 순서 배열은 그대로 두고 그 변형의 비트맵·비용만 지운다 —
    /// 일괄 축출이 순서 압축을 한 번으로 미룰 수 있게 갈라 둔 조각이다.
    private func dropResolved(_ variant: String) {
        resolvedBytes -= resolvedCost.removeValue(forKey: variant) ?? 0
        resolved.removeValue(forKey: variant)
    }

    /// lock 보유. 확정 이력은 **현재 작업셋 안에서만** 값이 있다 (해석자는 고정된
    /// 변형만 기다린다). 고정 집합이 바뀔 때 함께 줄이지 않으면, 예산 축출된
    /// 변형은 `resolvedOrder`에서도 빠져 있어 어디에서도 정리되지 않고 문서 전체
    /// 변형 수만큼 쌓인다 (뷰 경로는 `retainOnlyImages`를 아예 부르지 않는다).
    private func pruneSettleEpochs() {
        settleEpochs = settleEpochs.filter {
            pinnedVariants.contains($0.key) || activeResolvers[$0.key] != nil
        }
    }

    /// 가시 페이지가 참조하는 변형 키 집합을 갱신한다 — 이 변형은 예산 초과여도
    /// 축출하지 않아 축출→재요청 사이클을 막는다 (#1).
    public func setPinnedImages(_ variants: Set<String>) {
        lock.lock()
        pinnedVariants = variants
        // pin이 바뀌면 방금 unpin된 항목을 예산 내로 정리한다 (#1).
        evictOverBudget()
        pruneSettleEpochs()
        lock.unlock()
    }

    /// 이 변형만 남기고 나머지 해석 결과를 **버린다**. 페이지 단위로 그리는
    /// 경로(PDF)가 쓴다.
    ///
    /// `setPinnedImages`로는 부족하다: 그것이 부르는 축출은 예산을 넘었을 때만
    /// 동작하므로, 예산 안이면 이전 페이지 래스터가 그대로 남아 상주량이 한도
    /// 근처까지 자란다 (**unpin은 해제가 아니다**). 고정 교체와 해제를 한 동작에
    /// 묶어 둔 것은 호출부가 해제를 빠뜨릴 수 없게 하기 위해서다.
    ///
    /// 순서 배열을 **한 번만** 훑는다. 축출마다 `firstIndex` + `remove(at:)`을
    /// 부르던 이전 형태는 스캔·이동이 각각 O(N)이라 이차였다 (릴리스 실측,
    /// 변형 N개 중 앞 절반이 고정: N=4,000 203ms · 8,000 874ms · 16,000 3,611ms —
    /// 배가 될 때마다 4배). 변형 키가 (binItemId, 자르기·밝기·명암·효과)라
    /// 한 페이지가 같은 그림의 crop 인스턴스를 수천 개 참조하면 닿는 크기다.
    func retainOnlyImages(_ variants: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        pinnedVariants = variants
        var kept: [String] = []
        kept.reserveCapacity(resolvedOrder.count)
        for variant in resolvedOrder {
            if isPinned(variant) {
                kept.append(variant)
            } else {
                dropResolved(variant)
            }
        }
        resolvedOrder = kept
        pruneSettleEpochs()
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
        settleEpochs.removeAll()
        didDropDeferred = false
        // 요청 상태를 비웠으니 확정 통보를 받을 대기자가 없다 — 전원 깨워
        // 영구 대기를 막는다 (#74). 깨어난 `resolveImage`는 세대가 바뀐 것을
        // 보고 **재요청 없이 끝낸다** — 여기서 놓은 작업을 되살리면 안 된다.
        progressToken &+= 1
        let orphanedVariantWaiters = settleWaiters.values.flatMap { $0 }
        settleWaiters.removeAll()
        let orphanedProgressWaiters = progressWaiters
        progressWaiters.removeAll()
        lock.unlock()
        for waiter in orphanedVariantWaiters {
            waiter.continuation.resume(returning: .untracked)
        }
        for waiter in orphanedProgressWaiters {
            waiter.continuation.resume()
        }
        tasks.forEach { $0.cancel() }
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

// MARK: - 변형 키 · 디퍼드 큐 정책 (상태 없는 순수 함수)

/// 인스턴스 상태를 건드리지 않는 정책 함수들 — 클래스 본문 밖에 둬 "무엇이
/// 락 아래의 가변 상태이고 무엇이 순수 계산인지"가 구조로 보이게 한다.
extension HwpPageImageProvider {
    /// (binItemId, style) 변형의 결정론적 캐시 키
    static func variantKey(_ binItemId: UInt32, _ style: HwpImageRenderStyle?) -> String {
        guard let style else { return "\(binItemId)" }
        return "\(binItemId)|\(style.cropLeft),\(style.cropTop),\(style.cropRight)," +
            "\(style.cropBottom)|\(style.brightness)|\(style.contrast)|\(style.effect.rawValue)"
    }

    /// paint list가 참조하는 이미지 변형 키 집합 — `setPinnedImages` 인자를
    /// 호출부가 만들 수 있게 공개한다. 키 산식은 provider 내부 규약이라
    /// 밖에서 재구성할 수 없다 (#74).
    public static func imageVariantKeys(in paintList: HwpPaintList) -> Set<String> {
        var variants: Set<String> = []
        for command in paintList.commands {
            if case let .drawImageReference(binItemId, _, style, _) = command {
                variants.insert(variantKey(binItemId, style))
            }
        }
        return variants
    }

    /// 만석 디퍼드 큐에서 축출할 인덱스 — pin(가시) 안 된 가장 오래된 항목.
    /// 전부 pin이면 nil: 가시 요청을 빼면 그 페이지의 어떤 키도 완료를 못
    /// 트리거해 placeholder가 무관한 재드로우 전까지 영구 잔존한다 (#N).
    static func deferredEvictionIndex(
        _ deferred: [(key: UInt32, style: HwpImageRenderStyle?)],
        pinnedVariants: Set<String>
    ) -> Int? {
        deferred.firstIndex { !pinnedVariants.contains(variantKey($0.key, $0.style)) }
    }

    /// 비어있지 않은 디퍼드 큐에서 다음에 꺼낼 인덱스 — pin(가시)된 가장 오래된
    /// 항목 우선, 없으면 가장 오래된 항목(0). 가시 작업을 스크롤로 지나간
    /// stale보다 먼저 디코드해 가시 placeholder 대기를 줄인다 (R41 #3).
    static func deferredDequeueIndex(
        _ deferred: [(key: UInt32, style: HwpImageRenderStyle?)],
        pinnedVariants: Set<String>
    ) -> Int {
        deferred.firstIndex { pinnedVariants.contains(variantKey($0.key, $0.style)) } ?? 0
    }
}

// MARK: - 프리디코드 (화면 없는 경로, #74)

private extension HwpPageImageProvider {
    typealias VariantContinuation = CheckedContinuation<VariantWait, Never>

    struct VariantWaiter {
        let id: UInt64
        let continuation: VariantContinuation
    }

    struct ProgressWaiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    /// 변형 대기 결과 — `untracked`는 요청이 백프레셔로 드롭됐거나(확정 통보 없음)
    /// provider 교체·취소로 버려졌다는 뜻이다.
    enum VariantWait {
        case settled
        case untracked
    }
}

/// 확정 통보를 기다리는 경로는 확장으로 갈라 둔다 — 뷰가 쓰는 fire-and-forget
/// 요청 경로와 섞이면 어느 쪽이 재드로우를 전제하는지 읽어 낼 수 없다.
extension HwpPageImageProvider {
    /// 변형이 확정될 때까지 기다렸다가 디코딩 결과를 돌려준다 (실패·취소는 nil).
    ///
    /// `requestImage`는 draw가 다시 불릴 것을 전제로 한 fire-and-forget이라,
    /// 재드로우가 없는 경로(PDF export·썸네일)에서는 완료를 알 방법이 없다.
    /// 이 API는 확정 통보를 직접 기다린다 — 다만 **영구 대기가 되지 않는 것**이
    /// 요점이다: 진행 상한(`maximumInFlight`) 초과 요청은 디퍼드 큐로 가고,
    /// 그 큐가 만석 + 전부 pin이면 **드롭**되어 아무도 이 변형을 확정시키지
    /// 않는다. 그 경우 다른 요청이 하나 확정될 때까지(진행 토큰) 기다렸다가
    /// 다시 넣는다 — 드롭은 진행 중 요청이 12개 있다는 뜻이므로 확정은 반드시 온다.
    /// 디퍼드 축출로 추적에서 빠진 변형도 같은 재시도 경로를 탄다.
    ///
    /// 확정됐다가 바이트 예산으로 축출된 변형은 **재시도하지 않고 nil**이다
    /// (재요청하면 동시 해석자끼리 서로를 밀어내는 라이브락). 그 페이지를 온전히
    /// 그려야 하는 경로는 draw 전에 `unsettledImageVariants(in:)`로 확인한다.
    /// 캐시 purge에 취소된 요청은 축출이 아니라 재시도 대상이다 (R67).
    public func resolveImage(for key: UInt32, style: HwpImageRenderStyle? = nil) async -> CGImage? {
        let variant = Self.variantKey(key, style)
        beginResolving(variant)
        defer { endResolving(variant) }
        let startGeneration = currentGeneration()
        var didSettleOnce = false
        while !Task.isCancelled {
            if let image = cachedImage(for: key, style: style) {
                return image
            }
            if didFail(for: key, style: style) {
                return nil
            }
            // provider가 해체됐다. 다시 요청하면 `cancelOutstanding`이 놓으려던
            // store/cache 작업을 되살린다. 세대로 보는 것은 두 대기 경로(확정
            // 통보·진행 토큰)를 함께 덮기 위해서다 — 해체는 둘 다 깨운다.
            if currentGeneration() != startGeneration {
                return nil
            }
            // 확정 뒤 캐시에 없으면 예산 축출이다 — 재요청은 동시 해석자끼리
            // 서로를 밀어내는 라이브락이 된다.
            if didSettleOnce {
                return nil
            }
            // 토큰은 요청 **전에** 뜬다 — 드롭 판정과 대기 등록 사이에 끼어든
            // 확정을 놓치면 아무도 깨우지 않아 영구 대기가 된다.
            let token = progressSnapshot()
            // 에포크도 요청 **전에** 뜬다. 요청과 대기자 등록 사이에 확정이
            // 지나가고 그 결과가 축출되면 등록 측엔 아무 흔적도 없어, 이 값과의
            // 차이만이 그 확정을 증언한다 (없으면 아래 `didSettleOnce` 컷이
            // 우회돼 예산 초과 페이지에서 해석이 끝나지 않는다).
            let epoch = settleEpochSnapshot(variant)
            // 세대를 함께 넘긴다: 위 확인과 이 호출 사이에 해체가 끼어들면 인자
            // 없는 요청은 **새 세대로 등록**돼 해체가 못 끊는다. 이 검사는
            // `cancelOutstanding`이 세대를 올리는 것과 같은 락 안이라 창이 없다.
            requestImage(for: key, style: style, expectedGeneration: startGeneration)
            if await awaitVariantSettled(variant, since: epoch) == .untracked {
                await awaitProgress(after: token)
            } else {
                didSettleOnce = true
            }
        }
        return cachedImage(for: key, style: style)
    }

    /// paint list가 참조하는 모든 이미지 변형을 미리 디코딩한다 — 이후의 동기
    /// draw가 회색 로딩 사각형 대신 실제 이미지를 그린다.
    ///
    /// 호출 **전에** `setPinnedImages`로 해당 변형을 고정할 것: 고정하지 않으면
    /// 먼저 디코드된 대형 이미지가 draw 전에 바이트 예산으로 축출된다.
    public func predecodeImageReferences(in paintList: HwpPaintList) async {
        var references: [(key: UInt32, style: HwpImageRenderStyle?)] = []
        var seen: Set<String> = []
        for command in paintList.commands {
            guard case let .drawImageReference(binItemId, _, style, _) = command,
                  seen.insert(Self.variantKey(binItemId, style)).inserted
            else { continue }
            references.append((binItemId, style))
        }
        // 진행 상한 몫씩 나눠 요청한다 — 한 번에 전량을 넣으면 초과분이 디퍼드
        // 큐로 가고, 그쪽 만석 경로(드롭 → 재시도)를 굳이 밟게 된다.
        var start = 0
        while start < references.count, !Task.isCancelled {
            let end = min(start + maximumInFlight, references.count)
            await withTaskGroup(of: Void.self) { group in
                for reference in references[start ..< end] {
                    group.addTask { [self] in
                        _ = await resolveImage(for: reference.key, style: reference.style)
                    }
                }
            }
            start = end
        }
    }

    /// paint list가 참조하는 변형 중 아직 **확정되지 않은** 것 — 디코드 실패는
    /// 뺀다 (그건 플레이스홀더가 정답이라 뷰와 같다). 재드로우가 없는 경로가
    /// draw 직전에 "이 페이지를 온전히 그릴 수 있는가"를 묻는 데 쓴다: 프리디코드
    /// 뒤에도 남아 있으면 그 페이지 작업셋이 바이트 예산을 넘겨 축출된 것이다.
    func unsettledImageVariants(in paintList: HwpPaintList) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        var unsettled: Set<String> = []
        for command in paintList.commands {
            guard case let .drawImageReference(binItemId, _, style, _) = command else { continue }
            let variant = Self.variantKey(binItemId, style)
            if resolved[variant] == nil, !failedKeys.contains(variant) {
                unsettled.insert(variant)
            }
        }
        return unsettled
    }

    /// 테스트 관측점 — 그 변형의 확정 대기자 수.
    func settleWaiterCount(_ variant: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return settleWaiters[variant]?.count ?? 0
    }

    /// 테스트 관측점 — 진행 토큰 대기자 수. 드롭 경로엔 변형 대기자가 없어
    /// `settleWaiterCount`로는 그 대기 상태를 관측할 수 없다.
    func progressWaiterCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return progressWaiters.count
    }

    /// lock 밖. 현재 세대 — `cancelOutstanding`이 올린다.
    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// lock 밖. 현재 진행 토큰.
    private func progressSnapshot() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return progressToken
    }

    /// lock 밖. 이 변형의 확정 횟수 — 요청 전후 비교가 등록 경합 창을 메운다.
    func settleEpochSnapshot(_ variant: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return settleEpochs[variant, default: 0]
    }

    /// lock 밖. 해석이 도는 동안 그 변형을 프루닝에서 보호한다 — 고정 집합은
    /// 뷰 스크롤로 수시로 바뀌는데, 그 사이 확정 이력이 지워지면 해석자가
    /// 자기 요청의 확정을 못 본다.
    private func beginResolving(_ variant: String) {
        lock.lock()
        defer { lock.unlock() }
        activeResolvers[variant, default: 0] += 1
    }

    /// lock 밖. 마지막 해석자가 떠나면 작업셋 밖 항목은 그 자리에서 거둔다 —
    /// 보호를 무기한 두면 프루닝이 무력해져 에포크가 문서 전체만큼 쌓인다.
    private func endResolving(_ variant: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let count = activeResolvers[variant] else { return }
        guard count > 1 else {
            activeResolvers.removeValue(forKey: variant)
            if !pinnedVariants.contains(variant) {
                settleEpochs.removeValue(forKey: variant)
            }
            return
        }
        activeResolvers[variant] = count - 1
    }

    /// lock 밖. 대기자 식별자 발급 — 취소 시 자기 대기만 걷어내기 위한 것.
    private func allocateWaiterId() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextWaiterId
        nextWaiterId &+= 1
        return id
    }

    /// 변형이 확정되거나 추적에서 사라질 때까지 기다린다.
    private func awaitVariantSettled(_ variant: String, since epoch: UInt64) async -> VariantWait {
        let id = allocateWaiterId()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: VariantContinuation) in
                lock.lock()
                // 에포크가 움직였으면 등록 전에 확정이 지나간 것이다 — 그 결과가
                // 다른 변형의 삽입에 축출됐으면 캐시에도 추적에도 없어 아래
                // `.untracked` 분기로 새고, 그러면 호출부가 축출을 못 보고
                // 재요청해 해석자들이 서로를 밀어낸다.
                if resolved[variant] != nil || failedKeys.contains(variant)
                    || settleEpochs[variant, default: 0] != epoch
                {
                    lock.unlock()
                    continuation.resume(returning: .settled)
                    return
                }
                // 진행·디퍼드 어디에도 없으면 드롭됐거나 세대 교체로 버려진 것 —
                // 확정 통보가 오지 않으므로 즉시 돌려준다 (호출부가 재시도).
                if Task.isCancelled ||
                    (!inFlightKeys.contains(variant) && !deferredVariants.contains(variant))
                {
                    lock.unlock()
                    continuation.resume(returning: .untracked)
                    return
                }
                settleWaiters[variant, default: []].append(
                    VariantWaiter(id: id, continuation: continuation)
                )
                lock.unlock()
            }
        } onCancel: {
            cancelVariantWaiter(variant, id: id)
        }
    }

    private func cancelVariantWaiter(_ variant: String, id: UInt64) {
        lock.lock()
        guard var waiters = settleWaiters[variant],
              let index = waiters.firstIndex(where: { $0.id == id })
        else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: index)
        settleWaiters[variant] = waiters.isEmpty ? nil : waiters
        lock.unlock()
        waiter.continuation.resume(returning: .untracked)
    }

    /// 진행 토큰이 `token`에서 움직일 때까지 기다린다 (이미 움직였으면 즉시 반환).
    private func awaitProgress(after token: UInt64) async {
        let id = allocateWaiterId()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if progressToken != token || Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                progressWaiters.append(ProgressWaiter(id: id, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            cancelProgressWaiter(id: id)
        }
    }

    private func cancelProgressWaiter(id: UInt64) {
        lock.lock()
        guard let index = progressWaiters.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        let waiter = progressWaiters.remove(at: index)
        lock.unlock()
        waiter.continuation.resume()
    }

    /// lock 보유. 확정된 변형의 대기자와 진행 대기자 전원을 꺼내고 토큰을 올린다.
    /// 재개는 반드시 lock 밖에서 — continuation 재개가 같은 락을 다시 잡는
    /// 경로(`resolveImage` 루프)로 이어질 수 있다.
    private func takeWaiters(settledVariant variant: String?)
        -> (variant: [VariantWaiter], progress: [ProgressWaiter])
    {
        progressToken &+= 1
        let woken = progressWaiters
        progressWaiters.removeAll()
        let settled = variant.flatMap { settleWaiters.removeValue(forKey: $0) } ?? []
        return (settled, woken)
    }

    private static func resume(
        variantWaiters: [VariantWaiter],
        as wait: VariantWait,
        progress: [ProgressWaiter]
    ) {
        for waiter in variantWaiters {
            waiter.continuation.resume(returning: wait)
        }
        for waiter in progress {
            waiter.continuation.resume()
        }
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
