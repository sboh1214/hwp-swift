import CoreGraphics
import CoreHwp
import Foundation
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

private func makeSolidImage(width: Int = 4, height: Int = 4) -> CGImage? {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return context?.makeImage()
}

final class HwpDocumentActorTests: XCTestCase {
    func testInitSucceeds() {
        let actor = HwpDocumentActor()
        expect(actor).toNot(beNil())
    }

    func testPageAtUninitializedReturnsNil() async throws {
        let actor = HwpDocumentActor()
        let page = try await actor.page(at: 0)
        expect(page).to(beNil())
    }

    func testTotalPagesUninitializedReturnsZero() async {
        let actor = HwpDocumentActor()
        let count = await actor.totalPages()
        expect(count) == 0
    }

    func testCancelLoadDoesNotThrow() async {
        let actor = HwpDocumentActor()
        await actor.cancelLoad()
        expect(true) == true
    }

    func testImageCacheIsAccessible() async {
        let actor = HwpDocumentActor()
        let cache = await actor.imageCache()
        let count = await cache.count()
        expect(count) == 0
    }

    /// 캐시 키는 문서-로컬 binItemId — 새 문서 로드가 캐시를 회전하지 않으면
    /// 이전 문서의 비트맵이 같은 키로 오해석된다 (R35 #2).
    func testLoadDocumentRotatesImageCache() async throws {
        let actor = HwpDocumentActor()
        let cache = await actor.imageCache()
        let seeded = await cache.fetch(1) { makeSolidImage().map { HwpCachedImage(image: $0) } }
        expect(seeded).notTo(beNil())
        let seededCount = await cache.count()
        expect(seededCount) == 1

        _ = try await actor.loadDocument(from: CoreHwp.HwpFile())
        let rotatedCount = await cache.count()
        expect(rotatedCount) == 0
    }
}
