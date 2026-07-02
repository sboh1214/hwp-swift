import Foundation
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

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
}
