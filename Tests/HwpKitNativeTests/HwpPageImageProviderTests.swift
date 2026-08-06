import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

/// 해석 완료를 폴링으로 관측하기 위한 상자 — 태스크 완료는 await 없이 볼 수
/// 없는데, 회귀 시 그 await가 끝나지 않아 스위트를 멈춘다.
private final class ResolvedImageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved: CGImage?
    private var finished = false

    func finish(_ image: CGImage?) {
        lock.lock()
        resolved = image
        finished = true
        lock.unlock()
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    var image: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return resolved
    }
}

final class HwpPageImageProviderTests: XCTestCase {
    private func variant(_ key: UInt32) -> String {
        HwpPageImageProvider.variantKey(key, nil)
    }

    /// 실제 디코드 경로를 타도록 PNG 바이트를 만든다 (포맷은 매직 바이트로 판별).
    private func makePNGData(width: Int = 4, height: Int = 4) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination)) == true
        return data as Data
    }

    /// binItemId 1...count 에 각각 PNG를 담은 스토어.
    private func makeStore(count: UInt32) throws -> HwpImageStore {
        let payload = try makePNGData()
        var dataById: [UInt32: Data] = [:]
        var extensionById: [UInt32: String] = [:]
        for key in 1 ... count {
            dataById[key] = payload
            extensionById[key] = "png"
        }
        return HwpImageStore(dataByBinItemId: dataById, extensionByBinItemId: extensionById)
    }

    private func makeCGImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    /// 대기자 등록은 다른 태스크에서 일어나므로 관측 시점을 맞춘다.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                fail("조건이 \(timeout)초 안에 만족되지 않았다")
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func makePaintList(keys: ClosedRange<UInt32>) -> HwpPaintList {
        HwpPaintList(commands: keys.map { key in
            .drawImageReference(
                binItemId: key,
                rect: CGRect(x: 0, y: 0, width: 10, height: 10)
            )
        })
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

    // MARK: - 프리디코드 (#74)

    /// 화면 없는 경로가 재드로우 없이 디코드 결과를 받는다.
    func testResolveImageWaitsForDecodedImage() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )

        let image = await provider.resolveImage(for: 1)

        expect(image).toNot(beNil())
        expect(provider.cachedImage(for: 1)).toNot(beNil())
    }

    /// 바이트가 없는 키는 실패로 확정되고 nil로 끝난다 — 폴링·타임아웃 없이
    /// 확정을 기다리므로, 여기서 멈추면 export가 조용히 걸린다.
    func testResolveImageReturnsNilForMissingPayload() async {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())

        let image = await provider.resolveImage(for: 99)

        expect(image).to(beNil())
        expect(provider.didFail(for: 99)) == true
    }

    /// 진행 상한(12)을 넘는 참조도 전부 확정된다 — 초과분이 디퍼드 큐에서
    /// 잊히면 export가 회색 사각형을 그린다.
    func testPredecodeResolvesMoreReferencesThanInFlightLimit() async throws {
        let count: UInt32 = 30
        let provider = HwpPageImageProvider(
            store: try makeStore(count: count), cache: HwpImageCache()
        )
        let paintList = makePaintList(keys: 1 ... count)
        provider.setPinnedImages(HwpPageImageProvider.imageVariantKeys(in: paintList))

        await provider.predecodeImageReferences(in: paintList)

        let unresolved = (1 ... count).filter { provider.cachedImage(for: $0) == nil }
        expect(unresolved).to(beEmpty())
    }

    /// 디퍼드 큐가 만석 + 전부 pin이라 요청이 **드롭**되는 상황에서도 대기가
    /// 끝난다 — 화면이 없어 재드로우로 재요청될 일이 없으므로, 드롭을 알아채고
    /// 스스로 다시 넣지 않으면 영구 대기가 된다 (필수 요건 ①).
    func testResolveImageRecoversFromDeferredDrop() async throws {
        // 진행 상한 12 + 디퍼드 상한 64를 넘기고, 전부 pin해 축출 여지를 없앤다.
        let count: UInt32 = 120
        let provider = HwpPageImageProvider(
            store: try makeStore(count: count), cache: HwpImageCache()
        )
        let paintList = makePaintList(keys: 1 ... count)
        provider.setPinnedImages(HwpPageImageProvider.imageVariantKeys(in: paintList))
        for key in 1 ... count {
            provider.requestImage(for: key)
        }

        let image = await provider.resolveImage(for: count)

        expect(image).toNot(beNil())
    }

    /// 디퍼드에서 **축출된** 변형의 대기자를 깨운다. 드롭(만석+전부 pin)과 달리
    /// 축출은 대기 등록 **뒤에** 추적에서 빼므로, 깨우지 않으면 그 변형엔
    /// finishRequest가 영영 오지 않아 화면 없는 경로가 영구 대기한다.
    func testResolveImageWakesWaiterEvictedFromDeferredQueue() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 3), cache: HwpImageCache()
        )
        // 진행 슬롯 0 = 아무 요청도 in-flight가 되지 않아 확정이 발생하지 않는다.
        // 대기자가 디퍼드에 등록된 상태를 결정론적으로 만든다.
        provider.maximumInFlight = 0
        provider.maximumDeferred = 1
        let pending = Task { await provider.resolveImage(for: 1) }
        try await waitUntil { provider.settleWaiterCount(self.variant(1)) == 1 }

        // 디퍼드 만석이라 최고령 비고정 항목(key 1)을 축출한다.
        provider.requestImage(for: 2)

        expect(provider.settleWaiterCount(self.variant(1))) == 0
        // 슬롯을 열고 진행 토큰을 한 번 움직여 재시도 경로를 통과시킨다.
        provider.maximumInFlight = 4
        provider.finishRequest(
            key: 3, variant: variant(3), generation: 0, image: nil, cost: 0
        )
        try await waitUntil { provider.cachedImage(for: 1) != nil }
        // 회귀 시 대기가 끝나지 않으므로, 스위트를 멈추는 대신 실패로 끝낸다.
        pending.cancel()
        _ = await pending.value
    }

    /// 하드 상한은 고정 변형까지 축출해 지킨다 — 상한을 끄면 한 페이지 작업셋이
    /// 프로세스를 고갈시킨다 (#74 리뷰 2차). 그 결과 화면 없는 경로에 생기는
    /// 구멍은 `unsettledImageVariants`로 **관측 가능**해야 한다.
    func testPinnedVariantsAreEvictedOverHardLimitAndReportedAsUnsettled() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        provider.resolvedByteLimit = 1
        provider.setPinnedImages([variant(1), variant(2)])
        let image = try makeCGImage()

        provider.finishRequest(key: 1, variant: variant(1), generation: 0, image: image, cost: 10)
        provider.finishRequest(key: 2, variant: variant(2), generation: 0, image: image, cost: 10)

        expect(provider.cachedImage(for: 1)).to(beNil())
        expect(provider.cachedImage(for: 2)).toNot(beNil())
        expect(provider.unsettledImageVariants(in: self.makePaintList(keys: 1 ... 2)))
            == [variant(1)]
    }

    /// 페이지 단위 경로는 pin 교체만으로 이전 페이지를 해제하지 못한다 —
    /// `setPinnedImages`가 부르는 축출은 예산을 넘었을 때만 동작하므로, 예산
    /// 안이면 래스터가 한도 근처까지 쌓인다 (#74 리뷰 6차). `retainOnlyImages`는
    /// 남길 것을 빼고 전부 버린다.
    func testRetainOnlyImagesDropsPreviousPageVariants() throws {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())
        let image = try makeCGImage()
        provider.setPinnedImages([variant(1)])
        provider.finishRequest(key: 1, variant: variant(1), generation: 0, image: image, cost: 10)
        provider.finishRequest(key: 2, variant: variant(2), generation: 0, image: image, cost: 10)

        // 예산 안이라 pin만 바꾸면 1도 2도 그대로 남는다
        provider.setPinnedImages([variant(2)])
        expect(provider.cachedImage(for: 1)).toNot(beNil())

        provider.retainOnlyImages([variant(2)])

        expect(provider.cachedImage(for: 1)).to(beNil())
        expect(provider.cachedImage(for: 2)).toNot(beNil())
    }

    /// 디코드 실패는 미확정이 아니다 — 플레이스홀더가 정답이라 export를 세우면
    /// 손상된 그림 하나로 문서 전체를 못 내보내게 된다.
    func testUnsettledVariantsExcludeDecodeFailures() {
        let provider = HwpPageImageProvider(store: HwpImageStore(), cache: HwpImageCache())

        provider.finishRequest(key: 1, variant: variant(1), generation: 0, image: nil, cost: 0)

        expect(provider.didFail(for: 1)) == true
        expect(provider.unsettledImageVariants(in: self.makePaintList(keys: 1 ... 1)))
            .to(beEmpty())
    }

    /// 캐시 purge에 취소된 요청(기록 없음)은 축출이 아니라 **재시도 대상**이다
    /// (R67). `.settled`로 깨우면 대기자가 그것을 예산 축출로 보고 포기해,
    /// 화면 없는 경로가 회색 로딩 사각형을 그린다.
    func testResolveImageRetriesAfterPurgeCancelledRequest() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )
        provider.maximumInFlight = 0
        let pending = Task { await provider.resolveImage(for: 1) }
        try await waitUntil { provider.settleWaiterCount(self.variant(1)) == 1 }

        provider.maximumInFlight = 4
        provider.finishRequest(
            key: 1, variant: variant(1), generation: 0,
            image: nil, cost: 0, recordsFailure: false
        )

        let image = await pending.value
        expect(image).toNot(beNil())
        expect(provider.didFail(for: 1)) == false
    }

    /// provider 해체(`cancelOutstanding`)는 대기 중인 해석을 **끝낸다**. 깨어난
    /// 대기자가 다시 요청하면 해체가 놓으려던 store/cache 작업이 되살아난다 —
    /// 해체는 그것을 놓으려고 부르는 것이다.
    func testResolveImageStopsAfterProviderTeardown() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )
        // 진행 슬롯 0 = 확정이 발생하지 않아 대기 상태가 유지된다.
        provider.maximumInFlight = 0
        let box = ResolvedImageBox()
        let pending = Task { await box.finish(provider.resolveImage(for: 1)) }
        try await waitUntil { provider.settleWaiterCount(self.variant(1)) == 1 }

        provider.cancelOutstanding()

        // 회귀 시 다시 대기에 들어가 끝나지 않으므로 상한을 둔다 (행 대신 실패).
        try await waitUntil { box.isFinished }
        expect(box.image).to(beNil())
        pending.cancel()
    }

    /// 디퍼드에서 꺼낸 재시도가 **드롭되면** 그 변형의 대기자도 함께 내보낸다.
    /// `finishRequest`는 디큐 뒤 락을 놓고 재요청하는데, 그 사이 두 큐가 차면
    /// 재요청이 드롭 분기로 간다 — 그 변형의 대기자는 디퍼드에 있던 동안 등록된
    /// 것이라, 남겨 두면 확정 통보가 영영 오지 않는다 (#74 리뷰 9차).
    func testDroppedDeferredRetryWakesItsWaiter() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 3), cache: HwpImageCache()
        )
        provider.maximumInFlight = 0
        provider.maximumDeferred = 1
        // 전부 고정해 축출 경로를 막는다 — 드롭 분기를 강제한다.
        provider.setPinnedImages([variant(1), variant(2), variant(3)])
        let pending = Task { await provider.resolveImage(for: 1) }
        try await waitUntil { provider.settleWaiterCount(self.variant(1)) == 1 }

        // finishRequest가 1을 디큐한 뒤 락을 놓는 그 틈(onImageResolved)에 슬롯과
        // 디퍼드를 채워, 이어지는 1의 재요청이 드롭되게 만든다.
        provider.maximumInFlight = 1
        provider.onImageResolved = { _ in
            provider.requestImage(for: 2)
            provider.requestImage(for: 3)
        }
        provider.finishRequest(
            key: 99, variant: variant(99), generation: 0, image: nil, cost: 0
        )
        provider.onImageResolved = nil

        expect(provider.settleWaiterCount(self.variant(1))) == 0
        provider.cancelOutstanding()
        _ = await pending.value
    }

    /// 낡은 세대로 들어온 요청은 **등록 자체가 기각된다**. `resolveImage`가 이
    /// 인자에 기대어 "세대 확인 → 요청" 사이의 창을 닫으므로(그 사이 해체가
    /// 끼어들면 인자 없는 요청은 새 세대로 등록된다) 기각이 실제로 일어나야 한다.
    func testRequestImageRejectsStaleGeneration() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 2), cache: HwpImageCache()
        )

        provider.cancelOutstanding()
        provider.requestImage(for: 1, expectedGeneration: 0)
        provider.requestImage(for: 2)

        // 2는 디코드되고 1은 안 된다 — 기각이 실제로 일어났음을 가른다.
        try await waitUntil { provider.cachedImage(for: 2) != nil }
        expect(provider.cachedImage(for: 1)).to(beNil())
    }

    /// 태스크 취소는 대기를 즉시 끝낸다 (디코드 완료를 기다리지 않는다).
    func testResolveImageReturnsOnCancellation() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )

        let task = Task { await provider.resolveImage(for: 1) }
        task.cancel()

        // 값이 무엇이든(취소 시점에 따라 nil 또는 이미지) 반환은 되어야 한다.
        _ = await task.value
    }

    /// **등록된 뒤** 도착한 취소는 자기 대기만 걷어내고 끝낸다. 위 가드는 등록
    /// 전에 취소해 이 경로를 밟지 않는다 — 남겨 두면 그 엔트리는 확정 통보를
    /// 받을 주체가 없는 채로 provider 수명 내내 쌓인다.
    func testCancellationWhileWaitingRemovesItsVariantWaiter() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )
        // 진행 슬롯 0 = 확정이 발생하지 않아 대기 상태가 유지된다.
        provider.maximumInFlight = 0
        let box = ResolvedImageBox()
        let pending = Task { await box.finish(provider.resolveImage(for: 1)) }
        try await waitUntil { provider.settleWaiterCount(self.variant(1)) == 1 }

        pending.cancel()

        // 회귀 시 대기가 끝나지 않으므로 상한을 둔다 (행 대신 실패).
        try await waitUntil { box.isFinished }
        expect(provider.settleWaiterCount(self.variant(1))) == 0
        expect(box.image).to(beNil())
    }

    /// 드롭된 요청의 재시도를 기다리는 중(진행 토큰 대기)에 도착한 취소도 같다.
    /// 이 경로엔 변형 대기자가 아예 없어 위 가드가 닿지 않는다 — 두 대기 축을
    /// 따로 깨우도록 설계했으므로 취소도 축마다 확인해야 한다.
    func testCancellationWhileAwaitingProgressRemovesItsWaiter() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )
        // 진행·디퍼드 둘 다 0 = 요청이 곧바로 드롭돼 확정 통보가 오지 않는다.
        provider.maximumInFlight = 0
        provider.maximumDeferred = 0
        let box = ResolvedImageBox()
        let pending = Task { await box.finish(provider.resolveImage(for: 1)) }
        try await waitUntil { provider.progressWaiterCount() == 1 }

        pending.cancel()

        try await waitUntil { box.isFinished }
        expect(provider.progressWaiterCount()) == 0
        expect(box.image).to(beNil())
    }

    /// 해체는 **진행 대기자도** 깨운다. 변형 대기자만 깨우면 드롭 재시도를
    /// 기다리던 해석자가 영구 대기한다 — 해체가 요청 상태를 비웠으므로 그
    /// 토큰을 움직여 줄 확정이 다시는 오지 않는다.
    func testTeardownWakesProgressWaiters() async throws {
        let provider = HwpPageImageProvider(
            store: try makeStore(count: 1), cache: HwpImageCache()
        )
        provider.maximumInFlight = 0
        provider.maximumDeferred = 0
        let box = ResolvedImageBox()
        let pending = Task { await box.finish(provider.resolveImage(for: 1)) }
        try await waitUntil { provider.progressWaiterCount() == 1 }

        provider.cancelOutstanding()

        try await waitUntil { box.isFinished }
        expect(box.image).to(beNil())
        pending.cancel()
    }
}
