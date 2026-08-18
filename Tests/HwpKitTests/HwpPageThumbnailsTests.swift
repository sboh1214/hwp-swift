import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 공개 표면(`HwpKit.HwpPageThumbnails`)의 골든 — 실제 픽스처 문서로 잰다.
///
/// 자원 한도·순회 규율은 `HwpKitNativeTests`가 internal 이음매로 본다. 여기가
/// 채우는 구멍은 따로 있다: **커밋된 렌더 골든이 1쪽(인덱스 0)을 한 번도
/// 그리지 않는다** (`FixtureRenderGoldenTests.specs`가 2쪽 이후만 고른다 —
/// 1쪽 오라클인 fidelity 스위트는 opt-in이라 CI에서 안 돈다). 축소판이 가장
/// 먼저 그리는 쪽이 정확히 그 1쪽이므로, 잉크가 실린 1쪽을 상시 CI에서 한 번은
/// 그려 본다.
final class HwpPageThumbnailsTests: XCTestCase {
    private func loadDocument(_ id: String) async throws -> HwpDocument {
        let fixtures = try FixtureRoot.loadAllFixtures(from: #file)
        let fixture = try XCTUnwrap(fixtures.first { $0.id == id })
        return try await HwpDocumentLoader(fontResolver: .testDeterministic)
            .load(from: fixture.documentURL)
    }

    /// 1쪽이 실제로 그려진다 (백지가 아니다) — 그리고 위·아래 잉크 분포가
    /// 갈려 상하 반전이 통과하지 못한다.
    func testFirstPageThumbnailHasInkAndKeepsOrientation() async throws {
        let document = try await loadDocument("noori")
        let thumbnails = HwpPageThumbnails()
        thumbnails.update(document: document)

        let image = try await thumbnails.image(forPageAt: 0, pixelWidth: 200)

        expect(image.width) == 200
        let page = try XCTUnwrap(document.pages.first)
        expect(image.height) == HwpPageThumbnails.pixelHeight(for: page, pixelWidth: 200)

        let columns = 4
        let rows = 8
        let grid = try FixturePreview.inkGrid(
            of: image, width: image.width, height: image.height, columns: columns, rows: rows
        )
        expect(grid.reduce(0, +)) > 0
        // 표지 성격의 1쪽이라 잉크가 위쪽에 몰린다. 상하 반전은 두 합을 맞바꾸므로
        // 잉크 비영만 보는 가드와 달리 여기서 걸린다.
        let half = columns * rows / 2
        let top = grid[0 ..< half].reduce(0, +)
        let bottom = grid[half...].reduce(0, +)
        expect(top) > bottom
    }

    /// 축소판은 뷰·PDF와 **같은 조판**이다 — 같은 쪽을 같은 크기로 그린 기존
    /// 렌더 하네스와 잉크 분포가 일치해야 한다. 이 대조가 없으면 축소판만
    /// 조용히 다른 경로로 갈라져도 아무도 빨개지지 않는다.
    func testThumbnailMatchesTheSharedRenderPath() async throws {
        let document = try await loadDocument("noori")
        let page = try XCTUnwrap(document.pages.first)
        let width = 200
        let height = HwpPageThumbnails.pixelHeight(for: page, pixelWidth: width)
        let thumbnails = HwpPageThumbnails()
        thumbnails.update(document: document)

        let thumbnail = try await thumbnails.image(forPageAt: 0, pixelWidth: width)
        let reference = try await FixturePreview.renderImage(
            page: page, imageStore: document.imageStore, pixelWidth: width, pixelHeight: height
        )

        let columns = 6
        let rows = 8
        let thumbnailGrid = try FixturePreview.inkGrid(
            of: thumbnail, width: width, height: height, columns: columns, rows: rows
        )
        let referenceGrid = try FixturePreview.inkGrid(
            of: reference, width: width, height: height, columns: columns, rows: rows
        )
        // 같은 draw 경로·같은 CTM이라 픽셀까지 같아야 하지만, 임계를 0이 아닌
        // 아주 작은 값으로 둬 래스터라이저 잔차에 깨지지 않게 한다.
        expect(FixturePreview.meanAbsoluteError(thumbnailGrid, referenceGrid)) < 0.001
    }

    /// 여러 쪽을 훑어도 각 쪽이 제 크기로 나온다 — 공급자를 재사용하는 순회
    /// 경로가 두 번째 쪽부터 깨지지 않는지 본다 (`multi-section`은 구역마다
    /// 용지가 다를 수 있어 종횡비 계약도 함께 걸린다).
    func testTraversesEveryPageWithItsOwnAspectRatio() async throws {
        let document = try await loadDocument("multi-section")
        let thumbnails = HwpPageThumbnails()
        thumbnails.update(document: document)
        expect(thumbnails.pageCount) == document.pages.count

        for index in document.pages.indices.prefix(3) {
            let image = try await thumbnails.image(forPageAt: index, pixelWidth: 120)
            expect(image.width) == 120
            expect(image.height)
                == HwpPageThumbnails.pixelHeight(for: document.pages[index], pixelWidth: 120)
        }
    }

    /// 아직 오지 않은 쪽은 **재시도 가능한** 상태로 알린다 — 프로그레시브 로딩
    /// 중에는 흔한 일이라 문자열 실패로 접으면 호스트가 진짜 실패와 못 가른다.
    func testPageOutsideTheDocumentIsReportedAsSuch() async throws {
        let document = try await loadDocument("noori")
        let thumbnails = HwpPageThumbnails()
        thumbnails.update(document: document)

        await expect { try await thumbnails.image(forPageAt: 999, pixelWidth: 120) }
            .to(throwError(errorType: HwpThumbnailError.self) { error in
                guard case let .pageOutOfRange(index, pageCount) = error else {
                    return fail("Expected .pageOutOfRange, got \(error)")
                }
                expect(index) == 999
                expect(pageCount) == document.pages.count
            })
    }

    func testErrorDescriptionsCoverEveryCase() {
        let errors: [HwpThumbnailError] = [
            .cancelled,
            .pageOutOfRange(index: 3, pageCount: 2),
            .renderFailed("컨텍스트 생성 실패"),
        ]

        for error in errors {
            expect(error.description).toNot(beEmpty())
            expect(error.errorDescription) == error.description
        }
        expect(HwpThumbnailError.pageOutOfRange(index: 3, pageCount: 2).description)
            .to(contain("Page 4"))
        // 쪽 인덱스는 공개 인자다 — 1-기반 표시가 여기서 트랩하면 "재시도 가능"을
        // 알리려고 만든 타입이 그것을 **표시하는 순간** 프로세스를 죽인다
        expect(HwpThumbnailError.pageOutOfRange(index: .max, pageCount: 2).description)
            .toNot(beEmpty())
        expect(HwpThumbnailError.renderFailed("컨텍스트 생성 실패").description)
            .to(contain("컨텍스트 생성 실패"))
    }
}
