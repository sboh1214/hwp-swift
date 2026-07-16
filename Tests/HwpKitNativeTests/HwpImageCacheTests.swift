import CoreGraphics
import Foundation
import HwpKitNative
import Nimble
import XCTest

private func makeImage(width: Int = 10, height: Int = 10) -> CGImage? {
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return ctx?.makeImage()
}

final class HwpImageCacheTests: XCTestCase {
    func testFetchMissInvokesDecode() async {
        let cache = HwpImageCache()
        var callCount = 0
        let image = makeImage()
        _ = await cache.fetch(1) {
            callCount += 1
            return image
        }
        expect(callCount) == 1
    }

    func testFetchHitDoesNotInvokeDecode() async {
        let cache = HwpImageCache()
        let image = makeImage()
        _ = await cache.fetch(1) { image }
        var callCount = 0
        _ = await cache.fetch(1) {
            callCount += 1
            return image
        }
        expect(callCount) == 0
    }

    func testEvictionOnOverflow() async {
        // Each 1×1 image costs 1*1*4 = 4 bytes; maxBytes=10 holds 2 entries.
        let cache = HwpImageCache(maxBytes: 10)
        let img = makeImage(width: 1, height: 1)
        _ = await cache.fetch(1) { img }
        _ = await cache.fetch(2) { img }
        _ = await cache.fetch(3) { img } // should evict key 1 (oldest)
        let count = await cache.count()
        expect(count) <= 2
        let bytes = await cache.currentBytes()
        expect(bytes) <= 10
    }

    func testClearResetsCache() async {
        let cache = HwpImageCache()
        let img = makeImage()
        _ = await cache.fetch(1) { img }
        _ = await cache.fetch(2) { img }
        await cache.clear()
        let count = await cache.count()
        expect(count) == 0
        let bytes = await cache.currentBytes()
        expect(bytes) == 0
    }

    func testFetchNilDecodeNotCached() async {
        let cache = HwpImageCache()
        let result = await cache.fetch(99) { nil }
        expect(result).to(beNil())
        let count = await cache.count()
        expect(count) == 0
    }

    func testCountAndCurrentBytes() async {
        let cache = HwpImageCache()
        let img = makeImage(width: 2, height: 2) // 2*2*4 = 16 bytes
        _ = await cache.fetch(7) { img }
        let count = await cache.count()
        expect(count) == 1
        let bytes = await cache.currentBytes()
        expect(bytes) == 16
    }

    func testClearDuringInFlightDecodeDoesNotRepopulate() async {
        // clear가 fetch의 디코드 await 사이에 끼어드는 actor 재진입을 재현한다:
        // 디코드 클로저 안에서 clear를 불러 세대를 바꾼다. 호출자는 이미지를
        // 받지만, clear 이후 시작된 디코드라 storage엔 재삽입되지 않아야 한다 (P2).
        let cache = HwpImageCache()
        let image = makeImage()
        let result = await cache.fetch(1) {
            await cache.clear()
            return image
        }
        expect(result).toNot(beNil())
        let count = await cache.count()
        expect(count) == 0
    }

    func testFetchAfterClearCachesNormally() async {
        // clear로 세대가 바뀐 뒤 시작한 fetch는 정상 캐시된다 (게이트가 정상
        // 동작을 막지 않음).
        let cache = HwpImageCache()
        let image = makeImage()
        await cache.clear()
        _ = await cache.fetch(1) { image }
        let count = await cache.count()
        expect(count) == 1
    }
}
