import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 이어짐 (#165) PR 리뷰가 잡은 **예약** 결함의 재현 — 이월·수집 예약이 배치와 같은
    /// 조각·같은 높이를 보는지. 조각·측정 결함은 `HwpFootnoteContinuationSourceLayoutTests`
    /// (클래스 본문이 SwiftLint type_body_length 상한에 닿아 갈라 뒀다), 조립 헬퍼는
    /// `FootnoteContinuationSupport`.
    final class HwpFootnoteContinuationReservationTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        /// 이월 각주의 예약은 **다음 쪽에 실릴 조각**만이다 (#165 리뷰). 분할 지점이 여러 쪽에
        /// 걸친 각주의 남은 전부를 예약하면 `effectiveContentHeight`가 1pt로 무너져, 캐시 없는
        /// 흐름 문단이 자리가 남아도 다음 쪽으로 밀린다 — 배치는 그 쪽에 첫 조각만 싣는다.
        func testCarriedReservationCoversOnlyTheNextFragment() async throws {
            // 100줄 각주, 20줄마다 쪽 리셋 — 다섯 조각. 첫 쪽 15pt엔 앞 조각도 못 들어가 통째로 이월.
            let note = try Support.note(
                lines: (1 ... 100).map { "줄 \($0)" },
                locations: (0 ..< 100).map { Int32($0 % 20) * 1172 }
            )
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            // 둘째 쪽: 캐시 문단 하나 + 캐시 **없는** 흐름 문단 하나 — 흐름 문단은 예약을 본다.
            let flow = try HwpSynthetic.textParagraph("흐름 문단")
            let paginator = Support.paginate([host] + (try Support.nextPageBody()) + [flow])
            var pages: [HwpPage] = []
            var index = 0
            while let page = try await paginator.page(at: index) {
                pages.append(page)
                index += 1
            }
            let flowPage = try XCTUnwrap(pages.firstIndex { page in
                page.blocks.contains { ($0.attributedString?.string ?? "").contains("흐름 문단") }
            })
            // 다음 조각(20줄 ≈ 231pt)만 예약하면 둘째 쪽에 자리가 남아 흐름 문단이 거기 실린다.
            expect(flowPage) == 1
            // 그 쪽의 각주는 첫 조각뿐이고 흐름 문단 아래에 있다.
            let notes = Support.footnoteBlocks(on: pages[1])
            expect(notes.count) == 1
            let flowBlock = try XCTUnwrap(pages[1].blocks.first {
                ($0.attributedString?.string ?? "").contains("흐름 문단")
            })
            expect(try XCTUnwrap(notes.first).separatorLine.minY) >= flowBlock.frame.maxY - 0.01
        }

        /// 문단 경계에서 쪽이 갈리는 각주(뒤 문단이 앞 문단의 마지막 줄보다 위에서 시작)도 예약은
        /// 앞 문단까지다 (#165 리뷰) — `splitPoint`와 같은 두 번째 분할 지점. 문단 안 리셋만 보면
        /// 남은 문단 전부를 예약해 흐름 문단이 밀린다.
        func testCarriedReservationStopsAtAParagraphBoundaryReset() async throws {
            // 20줄 문단 다섯 개, 모두 0에서 시작 — 문단마다 쪽이 갈린다.
            var paragraphs = [try Support.note(
                lines: (1 ... 20).map { "문단 1 줄 \($0)" }, locations: (0 ..< 20).map { Int32($0) * 1172 }
            )]
            for number in 2 ... 5 {
                paragraphs.append(try Support.notePlainParagraph(
                    (1 ... 20).map { "문단 \(number) 줄 \($0)" }.joined(separator: "\n"),
                    locations: (0 ..< 20).map { Int32($0) * 1172 }
                ))
            }
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [paragraphs])
            let flow = try HwpSynthetic.textParagraph("흐름 문단")
            let paginator = Support.paginate([host] + (try Support.nextPageBody()) + [flow])
            var pages: [HwpPage] = []
            var index = 0
            while let page = try await paginator.page(at: index) {
                pages.append(page)
                index += 1
            }
            let flowPage = try XCTUnwrap(pages.firstIndex { page in
                page.blocks.contains { ($0.attributedString?.string ?? "").contains("흐름 문단") }
            })
            expect(flowPage) == 1
            expect(Support.footnoteBlocks(on: pages[1]).count) == 1
        }

        /// 구분선 획이 위 여백을 넘는 몫은 예약에도 든다 (#165 리뷰) — 배치가 그 몫을 자리에서
        /// 빼므로 예약이 빼지 않으면 본문이 그 자리를 먹어 들어갈 조각이 밀린다.
        func testReservationOverheadCountsTheSeparatorOverhang() throws {
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let thick = try HwpFootnoteContinuationBodyBottomTests.thickDividerShape()
            let metrics = layout.reservationMetrics(footnoteShape: thick, contentWidth: 451)
            // 위 여백 0 + 아래 여백 8.5 + 획 반 두께(14.17/2)
            expect(metrics.separatorOverhead).to(beCloseTo(8.5 + 14.1732 / 2, within: 0.01))
            let plain = layout.reservationMetrics(footnoteShape: nil, contentWidth: 451)
            expect(plain.separatorOverhead).to(beCloseTo(Support.overhead, within: 0.001))
        }

        /// 문단 경계에서 쪽이 갈리는 각주의 예약은 앞 문단을 **쪽 끝**으로 재어 마지막 줄의 줄
        /// 간격을 뺀다 (#165 리뷰) — 배치(`headEntries`)와 같은 높이. 뒤 문단을 먼저 보고 정한다.
        func testCarriedReservationDropsTrailingSpacingAtAParagraphBoundaryReset() throws {
            let first = try Support.note(lines: ["줄 1", "줄 2", "줄 3"], locations: [0, 1172, 2344])
            let second = try Support.notePlainParagraph("다음 쪽 문단", locations: [0, 1172])
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            let environment = HwpFootnoteCoordinator.Environment(contentWidth: 451, footnoteShape: nil)
            let reserved = coordinator.reservedFootnoteHeight(
                for: [
                    .init(paragraph: first, number: 1, sizeResolver: nil, numbering: nil, noteId: 1),
                    .init(paragraph: second, number: 1, sizeResolver: nil, numbering: nil, noteId: 1),
                ],
                environment: environment
            )
            // 앞 문단 3줄(35.16) − 마지막 줄 간격(2.72) + 구분선 여백 — 뒤 문단은 다음 쪽이다.
            expect(reserved).to(beCloseTo(Support.overhead + 3 * 11.72 - 2.72, within: 0.01))
        }

        /// 참조 쪽에서 새로 수집한 각주의 예약도 **첫 조각**까지다 (#165 리뷰) — 캐시가 여러 쪽에
        /// 걸친 각주의 전부를 더하면 그 쪽의 캐시 없는 흐름 문단이 다음 쪽으로 밀린다.
        func testCollectedReservationCoversOnlyTheFirstFragment() async throws {
            let note = try Support.note(
                lines: (1 ... 100).map { "줄 \($0)" },
                locations: (0 ..< 100).map { Int32($0 % 20) * 1172 }
            )
            // 참조는 쪽 위쪽 — 첫 조각(20줄 ≈ 231pt)은 이 쪽에 실린다.
            let host = try Support.host(at: 1500, notes: [[note]])
            let cached = try HwpSynthetic.lineSegParagraph(
                "캐시 문단", segments: [(location: 2720, height: 1500)]
            )
            let flow = try HwpSynthetic.textParagraph("흐름 문단")
            let paginator = Support.paginate([host, cached, flow] + (try Support.nextPageBody()))
            let page = try await paginator.page(at: 0)
            let first = try XCTUnwrap(page)
            let flowBlock = first.blocks.first { ($0.attributedString?.string ?? "").contains("흐름 문단") }
            expect(flowBlock).toNot(beNil())
            let notes = Support.footnoteBlocks(on: first)
            expect(notes.count) == 1
            if let flowBlock, let note = notes.first {
                expect(note.separatorLine.minY) >= flowBlock.frame.maxY - 0.01
            }
        }
    }
#endif
