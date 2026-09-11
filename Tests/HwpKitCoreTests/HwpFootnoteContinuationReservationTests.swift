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
            // 절대 캐시 모드의 이월 예약 — 흐름 모드는 나누지 않으므로 통째다.
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 451, footnoteShape: nil, continuesAtCacheBreaks: true
            )
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

        /// 조각 예약은 **절대 캐시 모드**에서만이다 (#165 리뷰): 흐름 모드의 절반 상한 배치는
        /// 각주를 통째로 놓으므로 첫 조각만 예약하면 본문이 그 자리를 먹은 뒤 통째 블록이 본문
        /// 위나 쪽 밖으로 나간다. 같은 각주라도 환경의 이어짐 여부로 예약이 갈린다.
        func testFragmentReservationAppliesOnlyWhenPlacementContinuesAtCacheBreaks() throws {
            // 40줄, 20줄마다 리셋 — 절대 캐시 모드에선 첫 20줄, 흐름 모드에선 40줄 전부.
            let note = try Support.note(
                lines: (1 ... 40).map { "줄 \($0)" }, locations: (0 ..< 40).map { Int32($0 % 20) * 1172 }
            )
            let host = try Support.host(at: 1500, notes: [[note]])
            func reserved(continues: Bool) -> (collected: CGFloat, anticipated: CGFloat) {
                var coordinator = HwpFootnoteCoordinator(
                    index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
                )
                let environment = HwpFootnoteCoordinator.Environment(
                    contentWidth: 400, footnoteShape: nil, continuesAtCacheBreaks: continues
                )
                let anticipated = coordinator.anticipatedFootnoteHeight(
                    for: host, environment: environment, childParagraphs: { _ in [] }
                )
                coordinator.collectFootnotes(
                    from: host, environment: environment, childParagraphs: { _ in [] }
                )
                return (coordinator.footnoteReservedHeight, anticipated)
            }
            let fragment = Support.overhead + 19 * 11.72 + 9 // 첫 20줄 (쪽 끝: 마지막 줄 상자까지)
            let whole = Support.overhead + 2 * (19 * 11.72 + 9) + 2.72 // 두 몫의 합, 마지막 줄 간격 제외
            let absolute = reserved(continues: true)
            expect(absolute.collected).to(beCloseTo(fragment, within: 0.01))
            expect(absolute.anticipated).to(beCloseTo(fragment, within: 0.01))
            let flow = reserved(continues: false)
            expect(flow.collected).to(beCloseTo(whole, within: 0.01))
            expect(flow.anticipated).to(beCloseTo(whole, within: 0.01))
        }

        /// 예약이 이미 분할 지점에서 멈춘 쪽의 예측은 0이다 (#165 리뷰) — 그 뒤 각주는 이 쪽에
        /// 실리지 않는데 전부를 더하면 첫 조각 옆에 들어가는 문단이 다른 쪽으로 밀린다.
        func testPreflightReservesNothingAfterASplitOnThePage() throws {
            let note = try Support.note(lines: ["줄 1", "줄 2"], locations: [0, 1172])
            let host = try Support.host(at: 1500, notes: [[note]])
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil, continuesAtCacheBreaks: true
            )
            expect(coordinator.anticipatedFootnoteHeight(
                for: host, environment: environment, childParagraphs: { _ in [] }
            )) > 0
            coordinator.reservationStopsAtSplit = true
            expect(coordinator.anticipatedFootnoteHeight(
                for: host, environment: environment, childParagraphs: { _ in [] }
            )) == 0
        }

        /// 예약이 분할 지점에서 멈춘 쪽의 예측은 뒤 각주의 개체 술어·중첩 순회에 들어가지 않는다
        /// (#165 리뷰) — 이어지는 각주 뒤에 흐름 문단·표를 다시 시도하는 쪽마다 되풀이되는 일이다.
        func testStoppedPreflightDoesNotTraverseNestedContainers() throws {
            let note = try Support.note(lines: ["줄 1"], locations: [0])
            var host = try Support.host(at: 1500, notes: [[note]])
            // 중첩 컨테이너(머리말)를 하나 달아 순회가 들어가는지 본다.
            host.ctrlHeaderArray = (host.ctrlHeaderArray ?? []) + [.header(HwpSynthetic.listControl(
                ctrlId: .header, paragraphs: [try HwpSynthetic.textParagraph("중첩")]
            ))]
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil, continuesAtCacheBreaks: true
            )
            var visits = 0
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                visits += 1
                if case let .header(list) = ctrl {
                    return list.listArray.flatMap(\.paragraphArray).map { ($0, .text) }
                }
                return []
            }
            _ = coordinator.anticipatedFootnoteHeight(
                for: host, environment: environment, childParagraphs: children
            )
            expect(visits) > 0
            visits = 0
            coordinator.reservationStopsAtSplit = true
            expect(coordinator.anticipatedFootnoteHeight(
                for: host, environment: environment, childParagraphs: children
            )) == 0
            expect(visits) == 0
        }

        /// 이월 각주가 기하·구분선이 다른 구역으로 넘어가면 예약을 새 구역으로 다시 잰다 (#165
        /// 리뷰). 앞 쪽을 확정하며 잰 예약은 이전 구역의 구분선 여백 기준이라, 새 구역 첫 쪽에서
        /// 배치(새 구분선)보다 작게 예약하면 흐름 문단이 각주 자리를 먹고 각주가 다음 쪽으로 밀린다.
        func testCarriedReservationIsRefreshedForTheNewSection() async throws {
            // 1구역: 쪽 아래 15pt 자리에 26줄(≈302pt) 각주 — 통째로 이월된다.
            let note = try Support.note(
                lines: (1 ... 26).map { "줄 \($0)" }, locations: (0 ..< 26).map { Int32($0) * 1172 }
            )
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            // 절대 캐시 모드 감지: 첫 줄 위치가 0보다 큰 캐시 문단이 (구역 문단들보다) 다수여야 한다.
            let leading = try [1500, 2720].map { location in
                try HwpSynthetic.lineSegParagraph("본문", segments: [(location: Int32(location), height: 1000)])
            }
            let firstSection = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: leading + [host]
            )
            // 2구역: 구분선 위 여백 50pt — 예약이 44.3pt 더 커야 한다 (여백 5000 + 850 vs 850 + 567).
            var secondDef = HwpSynthetic.sectionDef()
            secondDef.footNoteShape.rawPayload = Self.dividerPayload(marginTop: 5000, marginBottom: 850)
            // 24줄(384pt) 흐름 문단: 자리 = 742.68 − 16(구역 문단) − 예약. 옛 예약(302 + 14.17)으론
            // 410pt라 들어가고 새 예약(302 + 58.5)으론 366pt라 안 들어간다.
            let flow = try HwpSynthetic.textParagraph((1 ... 24).map { "흐름 \($0)" }.joined(separator: "\n"))
            let secondSection = HwpSynthetic.section(
                firstParagraphControls: [.section(secondDef)], bodyParagraphs: [flow]
            )
            let paginator = HwpPaginator(
                sections: [firstSection, secondSection],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var pages: [HwpPage] = []
            var index = 0
            while let page = try await paginator.page(at: index) {
                pages.append(page)
                index += 1
            }
            // 2구역 첫 쪽(1)에 이월 각주가 실리고, 흐름 문단은 그 자리를 비켜 다음 쪽으로 간다.
            expect(Support.footnoteBlocks(on: pages[1]).count) == 1
            let flowPage = try XCTUnwrap(pages.firstIndex { page in
                page.blocks.contains { ($0.attributedString?.string ?? "").contains("흐름 1") }
            })
            expect(flowPage) == 2
        }

        /// 구분선 여백만 지정한 각주 모양 payload (28바이트) — `dividerInfo`는 rawPayload를 다시
        /// 디코딩한다.
        private static func dividerPayload(marginTop: Int16, marginBottom: Int16) -> Data {
            var payload = Data(count: 12)
            withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: marginTop.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: marginBottom.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int16(283).littleEndian) { payload.append(contentsOf: $0) }
            payload.append(contentsOf: [0, 0])
            withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
            return payload
        }
    }
#endif
