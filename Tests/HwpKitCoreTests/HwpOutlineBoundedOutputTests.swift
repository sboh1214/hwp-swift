@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 탐색 목록이 **무엇을 내보내도 되는가**의 경계 (#77) — 제목 수집의 자원
    /// 천장과 `outline()`의 확정 쪽 접두.
    final class HwpOutlineBoundedOutputTests: XCTestCase {
        /// 상위 대리(lead surrogate)만 이어지는 조작 입력에서도 천장이 선다.
        ///
        /// 종전 조건은 "천장을 넘었고 **마지막이 상위 대리가 아니면** 끊는다"라,
        /// 상위 대리가 계속 오면 조건이 영영 참이 되지 않아 문단 전체를 훑고
        /// 그 길이만큼 문자열을 만들었다 — 천장이 막으려던 O(문단 길이) 작업이
        /// 그대로 살아 있었다. 정상 대리 쌍이 안 쪼개지는 것은
        /// `HwpOutlineCollectorTests.testCeilingDoesNotSplitSurrogatePairs`가 본다.
        func testLeadSurrogateRunDoesNotBypassTheUnitCeiling() throws {
            let paragraph = try rawUnitParagraph(
                Array(repeating: UInt16(0xD800), count: 20000)
            )

            let units = HwpOutlineCollector.titleUnits(of: paragraph)

            // 짝을 채울 여지로 한 단위만 더 허용한다.
            expect(units.count) <= HwpOutlineCollector.titleUnitCeiling + 1
        }

        /// `outline()`은 **확정된 쪽까지만** 낸다. 배치 도중 수집된 책갈피는
        /// `cachedPages.count + 1`에 귀속되는데, 그 쪽은 아직 캐시되지 않았고
        /// 취소되면 끝내 만들어지지 않는다 — 공개 API가 없는 쪽으로 안내하면
        /// 안 된다 (액터 스냅샷에만 걸어 둔 접두를 여기로 내린다).
        func testOutlineOnlyExposesFinalizedPages() async throws {
            // 여러 쪽에 걸치는 문단 + 그 문단의 책갈피. 구역 정의 문단이 1쪽을
            // 물고 있어 이 문단은 2쪽으로 밀린 뒤 쪼개지는데, 배치가 끝나는
            // 시점에 마지막 조각은 **아직 캐시되지 않은** 쪽에 있다 — 책갈피는
            // 그 쪽으로 귀속된다.
            let long = String(repeating: "본문 ", count: 400)
            var host = try HwpSynthetic.styledParagraph(long, paraShapeId: 1)
            host.ctrlHeaderArray = [HwpSynthetic.bookmarkControl("걸친 문단 앵커")]
            let paginator = HwpSynthetic.outlinePaginator(
                bodyParagraphs: [host],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                pageHeight: 20000
            )

            _ = try await paginator.page(at: 1)
            let partial = await paginator.outline()

            // 2쪽까지 확정된 시점 — 개요는 그 문단이 **시작한** 2쪽이라 정당히
            // 나오고, 배치 후 쪽(아직 없는 쪽)에 귀속된 책갈피만 빠진다.
            expect(partial.map(\.kind)) == [.heading]
            expect(partial.headings.first?.pageNumber) == 2

            // 조판이 끝나면 그 쪽이 실제로 생기므로 항목이 나온다 — 위 단언이
            // "영영 안 나온다"로 공허하게 통과하는 것이 아님을 함께 고정한다.
            let totalPages = await paginator.totalPages()
            let complete = await paginator.outline()

            expect(complete.map(\.kind)) == [.heading, .bookmark]
            // 정확한 쪽 값(실측 5)은 CT 조판에 달려 있어 박지 않는다 — 계약은
            // "부분 시점에 확정돼 있던 2쪽을 넘고, 최종 문서 안에 있다"이다.
            let anchorPage = try XCTUnwrap(complete.bookmarks.first?.pageNumber)
            expect(anchorPage) > 2
            expect(anchorPage) <= totalPages
        }
    }

    private extension HwpOutlineBoundedOutputTests {
        /// `String`으로는 표현할 수 없는 **짝 없는 대리**를 문단에 담는다.
        func rawUnitParagraph(_ units: [UInt16]) throws -> CoreHwp.HwpParagraph {
            var data = Data()
            for unit in units {
                withUnsafeBytes(of: unit.littleEndian) { data.append(contentsOf: $0) }
            }
            var paragraph = CoreHwp.HwpParagraph()
            paragraph.paraText = try CoreHwp.HwpParaText.load(data)
            paragraph.paraLineSeg.paraLineSegInternalArray = []
            return paragraph
        }
    }
#endif
