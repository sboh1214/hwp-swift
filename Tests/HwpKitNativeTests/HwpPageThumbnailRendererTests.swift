import CoreGraphics
import Foundation
@testable import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 문서 스코프 축소판 렌더러 — **쪽 순회 규율**과 문서 교체 계약.
///
/// 한 쪽을 그리는 것 자체는 `HwpPageBitmapRendererTests`가 본다. 여기가 잡는
/// 것은 그 위의 상태다: 이전 쪽 래스터를 실제로 버리는가, 이미 그린 축소판을
/// 다시 그리지 않는가, 문서가 바뀌면 옛 비트맵이 새 문서에 새지 않는가.
final class HwpPageThumbnailRendererTests: XCTestCase {
    // MARK: - 크기 · 캐시

    func testThumbnailFollowsPageAspectRatio() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 2))

        let image = try await renderer.image(forPageAt: 0, pixelWidth: 90)

        expect(image.width) == 90
        // 300×400 페이지 → 90×120
        expect(image.height) == 120
    }

    /// 두 번째 호출은 **같은 인스턴스**여야 한다. 새 비트맵이 나오면 사이드바를
    /// 스크롤할 때마다 1,030쪽을 다시 그린다.
    func testRepeatedRequestReturnsTheCachedInstance() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 2))

        let first = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        let second = try await renderer.image(forPageAt: 0, pixelWidth: 90)

        expect(first === second) == true
        // 폭이 다르면 다른 항목이다 — 작은 축소판이 큰 요청에 히트하면 흐려진다
        let wider = try await renderer.image(forPageAt: 0, pixelWidth: 120)
        expect(wider === first) == false
        expect(wider.width) == 120
    }

    func testRejectsPageOutsideTheDocument() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 2))

        await expect { try await renderer.image(forPageAt: 5, pixelWidth: 90) }
            .to(throwError(errorType: HwpPageBitmapRenderError.self) { error in
                guard case let .pageOutOfRange(index, pageCount) = error else {
                    return fail("Expected .pageOutOfRange, got \(error)")
                }
                expect(index) == 5
                expect(pageCount) == 2
            })
    }

    // MARK: - 쪽 순회 규율

    /// **이 스위트의 존재 이유.** 쪽을 옮기면 이전 쪽 래스터가 예산 안에서도
    /// 버려져야 한다 — `setPinnedImages`만 쓰면 unpin이 해제가 아니라서 문서를
    /// 훑는 동안 상주량이 한도까지 자란다 (`retainOnlyImages` doc).
    ///
    /// 예산이 넉넉한 상태로 재현하는 것이 요점이다: 예산이 빠듯하면 축출이
    /// 어차피 돌아 규율이 빠져도 통과한다.
    func testMovingToTheNextPageDropsThePreviousPageRasters() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 2))

        _ = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        let provider = try XCTUnwrap(renderer.imageProvider)
        // 1쪽은 binItemId 1을 참조한다
        expect(provider.cachedImage(for: 1)).toNot(beNil())

        _ = try await renderer.image(forPageAt: 1, pixelWidth: 90)

        // 2쪽은 binItemId 2만 참조하므로 1쪽 래스터는 남아 있으면 안 된다
        expect(provider.cachedImage(for: 2)).toNot(beNil())
        expect(provider.cachedImage(for: 1)).to(beNil())
    }

    // MARK: - 문서 교체

    /// 프로그레시브 스냅샷(같은 loadToken + 쪽 수 비감소)은 이미 그린 축소판을
    /// 유지한다. 버리면 1,030쪽 문서가 배치마다 처음부터 다시 그려진다.
    func testProgressiveSnapshotKeepsRenderedThumbnails() async throws {
        let token = UUID()
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1, loadToken: token))
        let first = try await renderer.image(forPageAt: 0, pixelWidth: 90)

        renderer.update(document: try Self.makeDocument(pageCount: 2, loadToken: token))

        expect(renderer.pageCount) == 2
        let again = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        expect(again === first) == true
    }

    /// 다른 문서(다른 loadToken)면 축소판도 이미지 캐시도 버린다 — 캐시 키가
    /// `binItemId` 하나라 남겨 두면 다른 문서의 비트맵이 그대로 히트한다.
    func testDifferentDocumentDiscardsThumbnailsAndProvider() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1, loadToken: UUID()))
        let first = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        let firstProvider = renderer.imageProvider

        renderer.update(document: try Self.makeDocument(pageCount: 1, loadToken: UUID()))

        expect(renderer.imageProvider === firstProvider) == false
        let again = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        expect(again === first) == false
    }

    /// 그림이 없는 문서는 공급자를 만들지 않는다 (PDF 경로와 같은 규약) —
    /// 만들면 빈 store를 붙든 캐시가 문서마다 쌓인다.
    func testDocumentWithoutImagesHasNoProvider() async throws {
        let renderer = HwpPageThumbnailRenderer()
        let page = HwpPageBitmapRendererTests.makePage(commands: [])
        renderer.update(document: HwpDocument(
            pages: [page],
            metadata: HwpDocumentMetadata(pageCount: 1, loadToken: UUID(), isComplete: true),
            unsupportedElements: []
        ))

        let image = try await renderer.image(forPageAt: 0, pixelWidth: 90)

        expect(renderer.imageProvider).to(beNil())
        expect(image.width) == 90
    }

    /// 취소된 요청은 **끝까지 가지 않고** 아무것도 굳히지 않는다 — 확정이 중간에
    /// 끊긴 결과를 캐시에 넣으면 회색 사각형이 그 쪽의 답으로 남는다.
    ///
    /// 취소를 **관측한 뒤에만** 요청한다 (`HwpPDFRendererTests`의 형판) — 그러지
    /// 않으면 취소가 렌더보다 늦게 도착해 성공할 수 있고, 그 회차를 눈감아 주는
    /// 순간 이 가드는 취소 검사를 전부 지워도 통과한다 (실측 확인).
    func testCancelledRequestFailsWithoutCaching() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1))

        let task = Task { () -> Result<CGImage, Error> in
            while !Task.isCancelled {
                await Task.yield()
            }
            do {
                return await .success(try renderer.image(forPageAt: 0, pixelWidth: 90))
            } catch {
                return .failure(error)
            }
        }
        task.cancel()
        let result = await task.value

        guard case let .failure(error) = result else {
            return fail("취소된 요청이 축소판을 돌려줬다")
        }
        expect(error is CancellationError) == true
        expect(renderer.thumbnailCache.count) == 0
    }

    /// 취소 검사는 **첫 캐시 조회보다 앞**에 서야 한다. 그 조회는 게이트보다
    /// 앞이라, 검사가 뒤에 있으면 이미 그린 쪽을 요청한 취소된 셀은 취소 경로를
    /// 아예 지나지 않고 성공한다 — 위 `testCancelledRequestFailsWithoutCaching`은
    /// 캐시가 빈 상태라 이 창을 보지 못한다.
    func testCancelledRequestDoesNotReturnAnAlreadyRenderedThumbnail() async throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1))
        _ = try await renderer.image(forPageAt: 0, pixelWidth: 90)
        expect(renderer.thumbnailCache.count) == 1

        let task = Task { () -> Result<CGImage, Error> in
            while !Task.isCancelled {
                await Task.yield()
            }
            do {
                return await .success(try renderer.image(forPageAt: 0, pixelWidth: 90))
            } catch {
                return .failure(error)
            }
        }
        task.cancel()

        guard case let .failure(error) = await task.value else {
            return fail("취소된 요청이 캐시된 축소판을 돌려줬다")
        }
        expect(error is CancellationError) == true
    }

    /// **세대 가드의 단독 가드.** `cancelOutstanding()`은 호출자 태스크에 전파되지
    /// 않으므로 그 렌더는 끝까지 돌아 회색 플레이스홀더가 섞인 비트맵을 낸다
    /// (`.drawPlaceholder` 정책은 그것을 오류로 보지 않는다). 삽입을 막는 것은
    /// 세대 비교뿐이라, 그 한 줄이 사라져도 다른 가드는 전부 초록으로 남는다.
    func testSupersededRenderResultIsNotCached() throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1))
        let key = HwpThumbnailCache.Key(pageIndex: 0, pixelWidth: 90)
        let image = try HwpPageBitmapRendererTests.makeBitmap()
        let stale = renderer.currentGeneration

        renderer.cancelOutstanding()
        renderer.insertIfCurrent(image, for: key, generation: stale)

        expect(renderer.thumbnailCache.count) == 0
        // 대조군 — 현재 세대로 넣으면 들어간다 (가드가 삽입 자체를 막는 게 아니다)
        renderer.insertIfCurrent(image, for: key, generation: renderer.currentGeneration)
        expect(renderer.thumbnailCache.image(for: key)) === image
    }

    /// 문서 교체도 같은 가드를 쓴다 — 세대를 올리는 자리가 둘이라 한쪽만 잠그면
    /// 다른 쪽이 조용히 뚫린다.
    func testRenderStartedBeforeADocumentSwapIsNotCached() throws {
        let renderer = HwpPageThumbnailRenderer()
        renderer.update(document: try Self.makeDocument(pageCount: 1))
        let key = HwpThumbnailCache.Key(pageIndex: 0, pixelWidth: 90)
        let stale = renderer.currentGeneration

        renderer.update(document: try Self.makeDocument(pageCount: 1))
        let image = try HwpPageBitmapRendererTests.makeBitmap()
        renderer.insertIfCurrent(image, for: key, generation: stale)

        expect(renderer.thumbnailCache.count) == 0
    }

    // MARK: - 합성 입력

    /// 쪽마다 **다른** binItemId를 참조하는 문서 — 쪽 경계에서 무엇이 버려지는지
    /// 관측하려면 쪽끼리 그림을 공유하면 안 된다.
    private static func makeDocument(
        pageCount: UInt32,
        loadToken: UUID? = UUID()
    ) throws -> HwpDocument {
        let payload = try HwpPageBitmapRendererTests.makePNGData()
        var dataById: [UInt32: Data] = [:]
        var extensionById: [UInt32: String] = [:]
        var pages: [HwpPage] = []
        for key in 1 ... pageCount {
            dataById[key] = payload
            extensionById[key] = "png"
            pages.append(HwpPageBitmapRendererTests.makePage(commands: [
                .drawImageReference(
                    binItemId: key,
                    rect: CGRect(x: 10, y: 10, width: 50, height: 50)
                ),
            ]))
        }
        return HwpDocument(
            pages: pages,
            metadata: HwpDocumentMetadata(
                pageCount: Int(pageCount), loadToken: loadToken, isComplete: true
            ),
            unsupportedElements: [],
            imageStore: HwpImageStore(
                dataByBinItemId: dataById, extensionByBinItemId: extensionById
            )
        )
    }
}
