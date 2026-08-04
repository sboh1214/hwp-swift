import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import ImageIO
import Nimble
import UniformTypeIdentifiers
import XCTest

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
}
