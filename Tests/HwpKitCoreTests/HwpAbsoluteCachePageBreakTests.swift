@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 절대 캐시 모드의 쪽 절단점 (#214) — 줄 위치가 줄어드는 곳에 더해, 앞 줄이 자리를
    /// 차지했는데(전진량 > 0) **같은** 위치에서 시작하는 줄도 새 쪽이다. 한글은 쪽을 채우는
    /// 글자처럼 취급 표를 품은 문단이 잇달면 문단마다 쪽 머리(`vertpos` 0)에 놓아 저장하는데
    /// (`inline-table-actual-height`의 32행 표 셋), 위치만 보면 0 → 0이 절단점으로 안 보여 그
    /// 문단들이 한 쪽에 겹쳤다.
    final class HwpAbsoluteCachePageBreakTests: XCTestCase {
        func testEqualLocationIsABreakOnlyAfterALineThatAdvances() {
            typealias Placer = HwpAbsoluteCachePlacer
            expect(Placer.isPageBreak(at: 0, after: 100, previousAdvance: 600)) == true
            expect(Placer.isPageBreak(at: 0, after: 0, previousAdvance: 41590)) == true
            // 전진량이 0 이하인 줄(고정 줄 간격 0 등) 뒤의 같은 위치는 같은 쪽이다.
            expect(Placer.isPageBreak(at: 0, after: 0, previousAdvance: 0)) == false
            expect(Placer.isPageBreak(at: 0, after: 0, previousAdvance: -100)) == false
            expect(Placer.isPageBreak(at: 100, after: 0, previousAdvance: 600)) == false
            expect(Placer.isPageBreak(at: 0, after: .min, previousAdvance: 0)) == false
        }

        /// 문단 안에서도 같다 — 쪽 머리에서 시작하는 줄이 잇달면 run이 갈린다.
        func testCacheRunsSplitAtARepeatedPageTopLocation() throws {
            let repeated = try HwpSynthetic.lineSegParagraph(
                "쪽 채움", segments: [(location: 0, height: 60000), (location: 0, height: 60000)]
            )
            expect(HwpAbsoluteCachePlacer.cacheRuns(for: repeated)?.count) == 2
            let flowing = try HwpSynthetic.lineSegParagraph(
                "보통", segments: [(location: 0, height: 1500), (location: 2100, height: 1500)]
            )
            expect(HwpAbsoluteCachePlacer.cacheRuns(for: flowing)?.count) == 1
        }

        /// 한 줄이 여러 세그먼트로 나뉜 줄(어울림 개체 양옆으로 흐르는 글 — 이어지는 세그먼트는 표 62
        /// bit 17 '줄의 첫 세그먼트'가 꺼져 있다)은 같은 위치여도 한 run이다 (#214 리뷰). 줄을 새로
        /// 시작하는 세그먼트만 쪽 절단점이 될 수 있다.
        func testContinuationSegmentAtTheSameLocationStaysInTheRun() throws {
            var paragraph = try HwpSynthetic.textParagraph("어울림 양옆")
            paragraph.paraLineSeg = try Self.lineSeg([
                Segment(location: 5000, flags: 0x20000), // 줄의 첫 세그먼트 (왼쪽)
                Segment(location: 5000, flags: 0x40000), // 같은 줄의 마지막 세그먼트 (오른쪽)
                Segment(location: 6600, flags: 0x60000),
            ])
            expect(HwpAbsoluteCachePlacer.cacheRuns(for: paragraph)?.count) == 1
            expect(HwpAbsoluteCachePlacer.isPageBreak(
                at: 5000, after: 5000, previousAdvance: 1600, startsLine: false
            )) == false
        }

        /// 쪽 중간에 단 밴드가 바뀌면 줄 캐시 위치를 밴드 상단 기준으로 다시 센다 — 1단 구역 첫
        /// 문단(줄 위치 0) 뒤 2단 밴드를 지나 다시 1단 밴드의 첫 문단이 0이어도 같은 쪽이다 (한글
        /// `Column` 쌍, #214 리뷰). 2단 밴드는 흐름 배치라 마지막 절대 캐시 줄은 구역 첫 문단의 것이다.
        func testBandStartAtTheSameLocationAsAnEarlierBandStaysOnThePage() async throws {
            var twoColumn = try (0 ..< 4).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "두 단 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            twoColumn[0].ctrlHeaderArray = [.column(HwpSynthetic.column(count: 2, spacing: 1134))]
            var oneColumn = try (0 ..< 4).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "한 단 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            oneColumn[0].ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: twoColumn + oneColumn
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 1
        }

        /// 앞 밴드의 마지막 캐시 줄이 밴드 상단보다 아래(0보다 큰 위치)여도 마찬가지다 — 위치는 밴드마다
        /// 다시 세므로 앞 밴드 기록과 견주지 않는다 (#214 2차 리뷰: 한글 `Column` 꼴 문서에 1단 문단을
        /// 더한 한글 저장본이 한글 1쪽인데 종전에는 마지막 1단 밴드만 2쪽으로 갔다 — `0 < 19200`).
        func testBandStartBelowAnEarlierBandsLastLineStaysOnThePage() async throws {
            let lead = try [1600, 3200, 4800].map { location in
                try HwpSynthetic.lineSegParagraph(
                    "앞 한 단 \(location)", segments: [(location: Int32(location), height: 1000)]
                )
            }
            var twoColumn = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "두 단 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            twoColumn[0].ctrlHeaderArray = [.column(HwpSynthetic.column(count: 2, spacing: 1134))]
            var oneColumn = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "한 단 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            oneColumn[0].ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let totalPages = await Self.paginator(lead + twoColumn + oneColumn).totalPages()
            expect(totalPages) == 1
        }

        /// 쪽 중간에 열린 밴드의 첫 캐시 문단은 **자리**로 판정한다 — 쪽을 채운 문단 뒤에 단 정의를
        /// 품은 문단이 쪽 머리(0)에 저장돼 있으면, 그 첫 줄이 남은 본문에 안 들어가므로 다음 쪽이다
        /// (#214 2차 리뷰: 한글 12.30이 `inline-table-actual-height`의 `table DOT` 문단에 단 정의를 더한
        /// 사본을 4쪽으로 저장했는데, 위치 기록을 지우기만 하면 쪽 채움 두 문단이 한 쪽에 겹친다).
        func testBandStartThatDoesNotFitMovesToTheNextPage() async throws {
            let lead = try [2720, 4820, 6920, 9020, 11120].map { location in
                try HwpSynthetic.lineSegParagraph(
                    "앞 문단 \(location)", segments: [(location: Int32(location), height: 1500)]
                )
            }
            let first = try HwpSynthetic.lineSegParagraph(
                "쪽 채움 0", segments: [(location: 0, height: 60000)]
            )
            var second = try HwpSynthetic.lineSegParagraph(
                "쪽 채움 1", segments: [(location: 0, height: 60000)]
            )
            second.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let paginator = Self.paginator(lead + [first, second])
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 3
            let rendered = try await paginator.page(at: 2)
            let page = try XCTUnwrap(rendered)
            let block = page.blocks.first { $0.attributedString?.string.contains("쪽 채움 1") == true }
            expect(block?.frame.minY).to(beCloseTo(page.margins.top, within: 0.01))
        }

        /// 첫 줄은 들어가도 한글이 통째로 다음 쪽에 옮긴 여러 줄 문단(문단 보호·외톨이줄 보호, #207)이
        /// 쪽 중간에 열린 밴드의 첫 문단이면 첫 run 전체의 자리로 판정한다 — 그 뒤 문단들도 위치가
        /// 늘기만 해서 위치로는 절단점이 안 보이므로 쪽이 넘어갈 때까지 자리로 본다 (#214 3차 리뷰:
        /// 첫 줄만 보면 옮겨진 문단과 그 쪽의 나머지가 본문 아래로 넘쳤다).
        func testMovedMultiLineBandStartParagraphTakesTheNextPage() async throws {
            let lead = try (1 ... 43).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "앞 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            var moved = try HwpSynthetic.lineSegParagraph(
                "옮긴 문단",
                segments: [(location: 0, height: 1000), (location: 1600, height: 1000),
                           (location: 3200, height: 1000)]
            )
            moved.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let after = try HwpSynthetic.lineSegParagraph(
                "뒤 문단", segments: [(location: 4800, height: 1000)]
            )
            let paginator = Self.paginator(lead + [moved, after])
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let rendered = try await paginator.page(at: 1)
            let page = try XCTUnwrap(rendered)
            let block = page.blocks.first { $0.attributedString?.string.contains("옮긴 문단") == true }
            expect(block?.frame.minY).to(beCloseTo(page.margins.top, within: 0.01))
            expect(page.blocks.contains { $0.attributedString?.string.contains("뒤 문단") == true })
                == true
        }

        /// 밴드 첫 문단(한 줄 제목)은 들어가도 뒤 문단이 안 들어가면 그 뒤 문단은 다음 쪽이다 — 다음
        /// 문단과 함께 옮긴 제목(keep-with-next)의 뒤 문단도 위치가 늘기만 하므로 자리로 본다. 제목은
        /// 한글과 달리 이 쪽에 남지만 본문 아래로 넘치지는 않는다.
        func testLaterParagraphInARestartedBandIsStillFitChecked() async throws {
            let lead = try (1 ... 43).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "앞 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                )
            }
            var heading = try HwpSynthetic.lineSegParagraph(
                "제목", segments: [(location: 0, height: 1000)]
            )
            heading.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let body = try HwpSynthetic.lineSegParagraph(
                "본문",
                segments: [(location: 1600, height: 1000), (location: 3200, height: 1000),
                           (location: 4800, height: 1000)]
            )
            let paginator = Self.paginator(lead + [heading, body])
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2
            let first = try await paginator.page(at: 0)
            let firstPage = try XCTUnwrap(first)
            let bottom = firstPage.size.height - firstPage.margins.bottom
            for block in firstPage.blocks where block.role == .body {
                expect(block.frame.minY) <= bottom
            }
        }

        /// 낡은 캐시 문단(캐시 줄 높이 < 글자 크기)이 키운 몫은 새 밴드 상단이 이미 담는다 — 밴드가
        /// 다시 열리면 그 보정을 한 번 더 더하지 않는다 (#214 3차 리뷰: 3pt 캐시의 10pt 문단이 7pt를
        /// 키운 뒤 열린 밴드의 첫 문단이 앞 블록보다 7pt 더 아래에 놓였다).
        func testStaleGrowthIsNotAddedTwiceAfterABandRestart() async throws {
            struct Placed {
                let previous: CGRect
                let bandTop: CGFloat
            }
            func placed(staleHeight: Int32) async throws -> Placed {
                let lead = try (1 ... 5).map { index in
                    try HwpSynthetic.lineSegParagraph(
                        "앞 \(index)", segments: [(location: Int32(index * 1600), height: 1000)]
                    )
                }
                let stale = try HwpSynthetic.lineSegParagraph(
                    "낡은 캐시", segments: [(location: 9600, height: staleHeight)]
                )
                var band = try HwpSynthetic.lineSegParagraph(
                    "새 밴드", segments: [(location: 0, height: 1000)]
                )
                band.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
                let rendered = try await Self.paginator(lead + [stale, band]).page(at: 0)
                let page = try XCTUnwrap(rendered)
                let staleBlock = try XCTUnwrap(page.blocks.first {
                    $0.attributedString?.string.contains("낡은 캐시") == true
                })
                let bandBlock = try XCTUnwrap(page.blocks.first {
                    $0.attributedString?.string.contains("새 밴드") == true
                })
                return Placed(previous: staleBlock.frame, bandTop: bandBlock.frame.minY)
            }
            let fresh = try await placed(staleHeight: 1000)
            let stale = try await placed(staleHeight: 300)
            // 낡은 캐시 문단은 캐시 전진량(3 + 6pt)이 아니라 CT 높이로 넓어졌다.
            expect(stale.previous.height) > 9 + 1
            // 밴드 첫 문단은 두 경우 모두 앞 블록 바로 아래 같은 간격에 놓인다.
            expect(stale.bandTop - stale.previous.maxY)
                .to(beCloseTo(fresh.bandTop - fresh.previous.maxY, within: 0.01))
        }

        private static func paginator(_ body: [CoreHwp.HwpParagraph]) -> HwpPaginator {
            HwpPaginator(
                sections: [HwpSynthetic.section(
                    firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                    bodyParagraphs: body
                )],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 줄 캐시 세그먼트 하나 — 높이 10pt, 속성(`flags`)만 갈린다.
        private struct Segment {
            let location: Int32
            let height: Int32 = 1000
            let flags: UInt32
        }

        /// 줄 캐시 레코드 (표 62).
        private static func lineSeg(_ segments: [Segment]) throws -> CoreHwp.HwpParaLineSeg {
            var payload = Data()
            func append(_ value: some FixedWidthInteger) {
                withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
            }
            for segment in segments {
                append(UInt32(0))
                append(segment.location)
                append(segment.height)
                append(segment.height)
                append(Int32(850))
                append(Int32(600))
                append(Int32(0))
                append(Int32(20000))
                append(segment.flags)
            }
            return try CoreHwp.HwpParaLineSeg.load(payload)
        }

        /// 쪽을 채우는 줄 하나짜리 문단 둘이 잇달아 쪽 머리에 저장돼 있으면 쪽마다 하나씩 놓인다.
        func testConsecutivePageTopParagraphsTakeAPageEach() async throws {
            // 절대 캐시 모드는 첫 줄 위치가 0보다 큰 문단이 다수일 때만 켜진다 — 앞 문단 다섯이
            // 구역 첫 문단·쪽 채움 문단 둘보다 많아야 한다.
            let lead = try [2720, 4820, 6920, 9020, 11120].enumerated().map { index, location in
                try HwpSynthetic.lineSegParagraph(
                    "앞 문단 \(index)", segments: [(location: Int32(location), height: 1500)]
                )
            }
            let tall = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "쪽 채움 \(index)", segments: [(location: 0, height: 60000)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: lead + tall
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let totalPages = await paginator.totalPages()
            expect(totalPages) == 3
            for index in 0 ..< 2 {
                let rendered = try await paginator.page(at: index + 1)
                let page = try XCTUnwrap(rendered)
                let blocks = page.blocks.filter {
                    $0.attributedString?.string.contains("쪽 채움") == true
                }
                expect(blocks.count) == 1
                expect(blocks.first?.attributedString?.string.contains("쪽 채움 \(index)")) == true
                expect(blocks.first?.frame.minY).to(beCloseTo(page.margins.top, within: 0.01))
            }
        }
    }
#endif
