import CoreGraphics
import Foundation
@testable import HwpKitNative
import Nimble
import XCTest

/// 축소판 캐시의 **결정적** 축출 계약.
///
/// `NSCache`를 쓰지 않는 이유가 여기 있다 — 예산 안에서는 아무것도 사라지지
/// 않아야 하고, 넘치면 삽입 순서대로 나가야 한다. 비결정 축출은 가시 항목을
/// 축출 → 재요청하는 루프를 만든다 (#3).
final class HwpThumbnailCacheTests: XCTestCase {
    private func makeImage(pixels: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixels,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private static func key(_ index: Int) -> HwpThumbnailCache.Key {
        HwpThumbnailCache.Key(pageIndex: index, pixelWidth: 100)
    }

    func testKeepsEntriesWithinBudget() throws {
        let cache = HwpThumbnailCache(maxBytes: 1000)
        let image = try makeImage(pixels: 10) // 40 bytes

        for index in 0 ..< 5 {
            cache.insert(image, for: Self.key(index))
        }

        expect(cache.count) == 5
        expect(cache.image(for: Self.key(0))) === image
    }

    /// 예산을 넘으면 **삽입 순서대로** 나간다.
    func testEvictsInInsertionOrder() throws {
        let cache = HwpThumbnailCache(maxBytes: 120)
        let image = try makeImage(pixels: 10) // 40 bytes

        for index in 0 ..< 4 {
            cache.insert(image, for: Self.key(index))
        }

        // 160 > 120이므로 가장 먼저 넣은 하나가 나간다
        expect(cache.image(for: Self.key(0))).to(beNil())
        expect(cache.image(for: Self.key(1))).toNot(beNil())
        expect(cache.image(for: Self.key(3))).toNot(beNil())
        expect(cache.currentBytes) <= 120
    }

    /// 예산보다 큰 축소판 하나도 살아남아야 한다 — 삽입 즉시 축출되면 그 쪽은
    /// 매 요청이 재렌더가 된다 (`insertResolved`의 `keeping:`과 같은 이유).
    func testKeepsTheJustInsertedEntryEvenWhenItAloneExceedsBudget() throws {
        let cache = HwpThumbnailCache(maxBytes: 40)
        let small = try makeImage(pixels: 10) // 40 bytes
        let large = try makeImage(pixels: 100) // 400 bytes

        cache.insert(small, for: Self.key(0))
        cache.insert(large, for: Self.key(1))

        expect(cache.image(for: Self.key(1))) === large
        expect(cache.image(for: Self.key(0))).to(beNil())
    }

    /// 같은 키를 다시 넣으면 바이트가 이중 계상되면 안 된다 — 새면 예산이
    /// 영구히 부풀어 멀쩡한 항목이 계속 축출된다.
    func testReinsertingSameKeyReplacesBytes() throws {
        let cache = HwpThumbnailCache(maxBytes: 1000)
        let image = try makeImage(pixels: 10) // 40 bytes

        cache.insert(image, for: Self.key(0))
        cache.insert(image, for: Self.key(0))

        expect(cache.count) == 1
        expect(cache.currentBytes) == 40
    }

    func testRemoveAllClearsBytes() throws {
        let cache = HwpThumbnailCache(maxBytes: 1000)
        cache.insert(try makeImage(pixels: 10), for: Self.key(0))

        cache.removeAll()

        expect(cache.count) == 0
        expect(cache.currentBytes) == 0
        expect(cache.image(for: Self.key(0))).to(beNil())
    }

    /// 정리가 **한 패스**임을 크기로 보인다. 축출마다 `firstIndex` + `remove(at:)`을
    /// 부르던 형태는 제거 수에 대해 이차라 이 크기에서 초 단위가 된다
    /// (`retainOnlyImages`의 실측과 같은 형상).
    func testEvictionStaysLinear() throws {
        let cache = HwpThumbnailCache(maxBytes: 400)
        let image = try makeImage(pixels: 10) // 40 bytes

        let start = Date()
        for index in 0 ..< 20000 {
            cache.insert(image, for: Self.key(index))
        }
        let elapsed = Date().timeIntervalSince(start)

        expect(cache.currentBytes) <= 400
        expect(elapsed) < 5.0
    }
}
