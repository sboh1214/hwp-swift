@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 페이지네이션 취소 응답 — `Task.yield()` 배칭(#73 조각 3)이 취소 관찰을
    /// 늦추지 않음을 고정한다.
    ///
    /// 배칭 전에는 문단마다 양보했으므로 취소가 늦어도 한 문단 안에 관찰됐다.
    /// 배칭 후에는 양보가 `HwpPaginator.yieldBatchSize` 문단마다 한 번인데,
    /// **취소 관찰은 양보가 아니라 `Task.checkCancellation()`이 한다** — 그것은
    /// `processParagraph`가 문단마다 그대로 부른다. 이 스위트가 그 분리를 잠근다.
    ///
    /// `HwpPaginator`가 도는 동안 취소가 관찰되는지를 보는 저장소 최초의 테스트다
    /// (종전에는 `HwpKitNative`의 액터 스모크뿐이었다).
    final class HwpPaginatorCancellationTests: XCTestCase {
        /// 취소하면 `page(at:)`이 `CancellationError`로 끝난다 — 문서 끝까지
        /// 조판하고 나서가 아니라.
        func testCancelDuringPaginationThrowsCancellationError() async throws {
            let paginator = makePaginator(paragraphCount: 4000)

            let task = Task {
                // 마지막 페이지보다 훨씬 뒤 — 취소가 없으면 전량 조판해야 닿는다.
                try await paginator.page(at: 100_000)
            }
            // 조판이 실제로 시작하도록 한 틱 넘긴 뒤 취소한다.
            await Task.yield()
            task.cancel()

            do {
                _ = try await task.value
                fail("취소했는데 CancellationError가 아니라 정상 반환했다")
            } catch is CancellationError {
                // 기대 경로
            } catch {
                fail("CancellationError가 아니라 \(error)")
            }
        }

        /// 취소는 문서를 끝까지 조판하기 전에 관찰된다 — 배칭이 취소를
        /// "문서 끝까지 밀어 버리지" 않음을 페이지 수로 확인한다.
        func testCancelStopsBeforePaginatingWholeDocument() async {
            let paragraphCount = 4000
            let paginator = makePaginator(paragraphCount: paragraphCount)

            let task = Task { try await paginator.page(at: 100_000) }
            await Task.yield()
            task.cancel()
            _ = try? await task.value

            // 전량 조판했다면 문단 수 / 페이지당 줄 수 만큼 페이지가 생긴다.
            let fullDocumentPages = paragraphCount / linesPerPage
            let produced = await paginator.cachedPages.count
            expect(produced) < fullDocumentPages
        }

        /// 취소하지 않으면 같은 문서가 끝까지 조판된다 — 위 두 테스트가
        /// "그냥 아무것도 안 해서" 통과하는 것이 아님을 잠근다.
        func testUncancelledPaginationCompletes() async {
            let paragraphCount = 400
            let paginator = makePaginator(paragraphCount: paragraphCount)
            let totalPages = await paginator.totalPages()
            expect(totalPages) >= paragraphCount / linesPerPage
        }

        // MARK: 헬퍼

        private let linesPerPage = 34

        private func makePaginator(paragraphCount: Int) -> HwpPaginator {
            let bodyParagraphs = (0 ..< paragraphCount).compactMap { index in
                try? HwpSynthetic.lineSegParagraph(
                    "제\(index)문단 가나다라마바사아자차카타파하 취소 응답 계측 본문",
                    segments: [(
                        location: Int32(2720 + (index % linesPerPage) * 2100),
                        height: 1500
                    )]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: bodyParagraphs
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }
    }
#endif
