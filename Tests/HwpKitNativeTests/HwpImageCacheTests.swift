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
}
