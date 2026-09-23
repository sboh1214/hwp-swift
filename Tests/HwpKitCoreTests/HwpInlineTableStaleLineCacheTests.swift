import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// `HwpInlineTableStaleLineCacheTests`·`HwpInlineTableStaleLineCachePageTests` 공용 입력
    /// (#214 PR 리뷰).
    enum InlineTableStaleLineCacheSupport {
        /// 표를 실은 줄 캐시 — 줄 높이 `height`(HWPUNIT)의 한 줄. 표는 `rows`행이라 셀 내용이 행마다
        /// 10pt로 키웠는데 저작 높이는 행마다 2.82pt다 (`InlineTableActualHeightSupport.staleTable`).
        static func cachedHost(
            instanceId: UInt32,
            rows: Int = 10,
            location: Int32 = 0,
            height: Int32
        ) throws -> CoreHwp.HwpParagraph {
            var host = InlineTableActualHeightSupport.host(
                table: try InlineTableActualHeightSupport.staleTable(
                    rows: rows, instanceId: instanceId
                ),
                suffix: " 뒤"
            )
            host.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "캐시", segments: [(location: location, height: height)]
            ).paraLineSeg
            return host
        }

        /// 절대 캐시 문서 — 구역 첫 문단(0) 뒤 호스트와 캐시 문단 둘(`tailLocation`부터 16pt 간격)이
        /// 이어진다. 본문은 56.68~799.36pt다 (A4, 위 20mm·아래 15mm, 머리말·꼬리말 여백 0).
        static func absolutePaginator(
            host: CoreHwp.HwpParagraph,
            tailLocation: Int32,
            index: HwpIndex = HwpIndex(from: CoreHwp.HwpFile())
        ) throws -> HwpPaginator {
            let tail = try (0 ..< 2).map { ordinal in
                try HwpSynthetic.lineSegParagraph(
                    "뒤 문단 \(ordinal)",
                    segments: [(location: tailLocation + Int32(ordinal * 1600), height: 1000)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host] + tail
            )
            return HwpPaginator(sections: [section], index: index, fontResolver: .testDeterministic)
        }
    }

    /// 글자처럼 취급 표보다 낮은 줄 캐시는 믿지 않는다 (#214 PR 리뷰) — 셀 내용이 저장 뒤에 표를 키운
    /// 문서는 표를 실은 캐시 줄이 그 표보다 낮다. 줄 예약이 그려지는 높이(#214)라 CT 줄은 표만큼
    /// 커지는데, 캐시 높이로 전진하면 블록은 캐시만큼만 내려가고 표는 실제 높이로 그려져 뒤 문단이
    /// 표를 덮는다.
    ///
    /// 기대값은 한컴오피스 한글 12.30.0(6446) macOS 실측이다 (2026-09-23): 한글이 저장한 문서의 4행
    /// 표(51.28pt) 셀마다 문단 다섯을 더해 371.28pt로 키운 사본(호스트 줄 캐시 56.94pt 그대로)을 열면
    /// 한글은 캐시를 버리고 표 줄을 376.94pt로 키워 뒤 문단을 그 차이(320pt)만큼 내려 그린다 — 1단(절대
    /// 캐시 경로)·2단(흐름 경로)·위 10·아래 5pt 문단 간격·두 단에 걸친 구역 첫 문단(다단 캐시 run) 모두
    /// 같다. 종전 우리는 캐시 높이로 전진해 뒤 문단 베이스라인이 186.64pt였다(한글 506.64pt).
    final class HwpInlineTableStaleLineCacheTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport
        private typealias Stale = InlineTableStaleLineCacheSupport

        /// 흐름 배치 — 캐시 줄 28.2pt·실제 100pt 표를 품은 문단은 CT 높이(표 + 비율 여분 6pt)로
        /// 전진해 뒤 문단이 표 아래에 온다. 신선한 캐시(표보다 높은 120pt 줄)는 종전대로 캐시 높이다.
        func testFlowParagraphDropsALineCacheShorterThanItsTable() async throws {
            for (height, expectedBlock) in [(Int32(2820), CGFloat(106)), (12000, 126)] {
                let pages = try await InlineControlFragmentSupport.pages(
                    of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: [
                        try Stale.cachedHost(instanceId: 21, height: height),
                        try HwpSynthetic.textParagraph("뒤 문단"),
                    ])
                )
                let page = try XCTUnwrap(pages.first)
                let table = try XCTUnwrap(Support.table(on: page, instanceId: 21))
                let block = try XCTUnwrap(Support.textBlock(on: page, containing: " 뒤"))
                let tail = try XCTUnwrap(Support.textBlock(on: page, containing: "뒤 문단"))
                expect(table.frame.height).to(beCloseTo(100, within: 0.01))
                expect(block.frame.height).to(beCloseTo(expectedBlock, within: 0.01))
                expect(tail.frame.minY).to(beCloseTo(block.frame.maxY, within: 0.01))
                expect(tail.frame.minY).to(beGreaterThanOrEqualTo(table.frame.maxY - 0.01))
            }
        }

        /// 절대 캐시 경로 — 낡은 캐시 보정이 블록을 CT **줄 범위**로 키우고 뒤 캐시 문단을 그 차이만큼
        /// 민다. 호스트에 위 10·아래 5pt 문단 간격이 있어도 두 간격은 캐시 위치에 이미 들어 있으므로
        /// 두 번 밀지 않는다 — 뒤 문단은 호스트 블록 아래 + 아래 간격 5pt다 (한글 실측: 간격 없는
        /// 문서와 같은 320pt만 밀렸다; CT 문단 높이로 밀면 15pt 더 내려간다).
        func testAbsoluteCacheShiftsFollowingParagraphsByTheLineExtentGrowth() async throws {
            try await Self.assertAbsoluteShift(
                index: HwpIndex(from: CoreHwp.HwpFile()), shapeId: nil, hostLocation: 1600,
                gapAfter: 0
            )
            let spaced = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 2000,
                    paragraphSpacingBottom: 1000, tabDefId: 0
                ),
            ])
            try await Self.assertAbsoluteShift(
                index: spaced, shapeId: 7, hostLocation: 2600, gapAfter: 5
            )
        }

        /// 호스트(`hostLocation`, 낡은 28.2pt 줄 캐시)와 그 뒤 캐시 문단 둘 — 캐시에서 뒤 문단 첫 줄은
        /// 호스트 줄 28.2 + 줄 간격 6pt 뒤에 아래 간격(`gapAfter`)을 둔 자리다.
        private static func assertAbsoluteShift(
            index: HwpIndex,
            shapeId: UInt16?,
            hostLocation: Int32,
            gapAfter: CGFloat
        ) async throws {
            var host = try Stale.cachedHost(instanceId: 22, location: hostLocation, height: 2820)
            if let shapeId {
                host.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: shapeId, paraStyleId: 0
                )
            }
            let tailLocation = hostLocation + 2820 + 600 + Int32(gapAfter * 100)
            let paginator = try Stale.absolutePaginator(
                host: host, tailLocation: tailLocation, index: index
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let table = try XCTUnwrap(Support.table(on: page, instanceId: 22))
            let block = try XCTUnwrap(Support.textBlock(on: page, containing: " 뒤"))
            let tail = try XCTUnwrap(Support.textBlock(on: page, containing: "뒤 문단 0"))
            let next = try XCTUnwrap(Support.textBlock(on: page, containing: "뒤 문단 1"))
            expect(block.frame.height).to(beCloseTo(106, within: 0.01))
            expect(tail.frame.minY).to(beCloseTo(block.frame.maxY + gapAfter, within: 0.01))
            expect(tail.frame.minY).to(beGreaterThanOrEqualTo(table.frame.maxY - 0.01))
            // 뒤 문단끼리는 캐시 간격(16pt) 그대로다.
            expect(next.frame.minY - tail.frame.minY).to(beCloseTo(16, within: 0.01))
        }

        /// 다단 캐시 run(비절대 모드, 두 단에 걸친 문단) — 표를 실은 둘째 단 줄 캐시가 그 표보다
        /// 낮으면 한글의 단 배분도 낡았으므로 줄 단위 배분으로 떨어진다. 캐시 run 높이를 믿으면 둘째
        /// 단 블록이 15pt 줄 둘만큼만 내려가고 뒤 문단이 100pt 표를 덮는다. 신선한 캐시(표를 담는
        /// 110pt 줄)는 종전대로 두 단에 나뉜다.
        ///
        /// 셋째 경우는 **판정 폭**이다: 비등폭 단에서 250pt 표는 문단을 잰 좁은 첫 단(134pt)에서는
        /// 셀 글이 두 줄이라 15pt 줄보다 높지만, 표가 실린 넓은 둘째 단에서는 한 줄(10pt)이라 캐시가
        /// 신선하다 — 첫 단 폭으로 재면 신선한 캐시를 버려 두 단 배분이 한 단으로 무너진다. 넷째는 폭이
        /// **단 기준**(93%)인 표다: 가용 폭만 둘째 단으로 바꾸고 크기 해석기를 첫 단 것으로 두면 표가
        /// 0.93 × 134pt로 풀려 같은 오판이 난다.
        func testCachedColumnRunsShorterThanTheirTableFallBackToLineFill() async throws {
            let equal = HwpSynthetic.column(count: 2, spacing: 1134)
            let tall = try Support.staleTable(rows: 10, instanceId: 23, width: 15000)
            try await Self.assertColumnRun(
                column: equal, table: tall, tableLineHeight: 1500, staysInColumns: false
            )
            try await Self.assertColumnRun(
                column: equal, table: tall, tableLineHeight: 11000, staysInColumns: true
            )
            try await Self.assertColumnRun(
                column: HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0]),
                table: try Support.staleTable(
                    rows: 1, instanceId: 23, width: 25000,
                    cellText: { _ in "abcdefghij abcdefghij abcdefgh" }
                ),
                tableLineHeight: 1500,
                staysInColumns: true
            )
            var columnRelative = try Support.staleTable(
                rows: 1, instanceId: 23, width: 25000,
                cellText: { _ in "abcdefghij abcdefghij abcdefgh" }
            )
            columnRelative.commonCtrlProperty.width = 9300
            columnRelative.commonCtrlProperty.propertyInfo.widthRelativeToRawValue = 2
            columnRelative.commonCtrlProperty.propertyInfo.widthRelativeTo = .column
            try await Self.assertColumnRun(
                column: HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0]),
                table: columnRelative,
                tableLineHeight: 1500,
                staysInColumns: true
            )
        }

        /// 뒤 문단이 표를 덮지 않고, 문단이 두 단에 나뉘는지(`staysInColumns`) 캐시 run 배분 여부다.
        private static func assertColumnRun(
            column: CoreHwp.HwpColumn,
            table: CoreHwp.HwpTable,
            tableLineHeight: Int32,
            staysInColumns: Bool
        ) async throws {
            let page = try await columnRunPage(
                column: column, table: table, tableLineHeight: tableLineHeight
            )
            let placed = try XCTUnwrap(Support.table(on: page, instanceId: 23))
            let tail = try XCTUnwrap(Support.textBlock(on: page, containing: "뒤 문단"))
            expect(tail.frame.intersects(placed.frame)) == false
            let hostBlocks = page.blocks.filter {
                $0.kind == .text && $0.attributedString?.string.contains("word") == true
            }
            let columnOrigins = Set(hostBlocks.map { Int($0.frame.minX.rounded()) })
            expect(columnOrigins.count == 2) == staysInColumns
        }

        /// 두 단에 걸친 캐시 문단 — 컨트롤 문자는 단 정의(코드 2)와 표(코드 11)가 스트림 순서대로
        /// 있어 표의 줄 위치가 풀린다. 표는 둘째 run(단)의 첫 줄에 실린다.
        private static func columnRunPage(
            column: CoreHwp.HwpColumn,
            table: CoreHwp.HwpTable,
            tableLineHeight: Int32
        ) async throws -> HwpPage {
            let prefix = (0 ..< 14).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = " " + (14 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let tableOffset = 8 + prefix.utf16.count
            let streamCount = UInt32(tableOffset + 8 + suffix.utf16.count)
            let secondRun = UInt32(tableOffset - 10)
            var paragraph = try HwpSynthetic.columnCacheParagraph(prefix + suffix, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 20000),
                .init(textIndex: secondRun / 2, location: 2100, height: 1500, width: 20000),
                .init(textIndex: secondRun, location: 0, height: tableLineHeight, width: 20000),
                .init(
                    textIndex: UInt32(tableOffset + 12), location: tableLineHeight + 600,
                    height: 1500, width: 20000
                ),
            ], charCount: streamCount)
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 2)]
                + prefix.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 11)]
                + suffix.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [.column(column), .table(table)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph, try HwpSynthetic.textParagraph("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            return try XCTUnwrap(rendered)
        }

        /// 판정 — 표를 실은 줄이 표 + 바깥 여백을 담으면 캐시를 믿고, 못 담으면 낡았다. 표를 실은
        /// 줄은 컨트롤 문자의 WCHAR 위치를 덮는 마지막 세그먼트이고, 위치를 못 풀면 가장 높은 줄이다.
        func testLineCacheIsStaleComparesTheTablesOwnLine() throws {
            let table = try Support.staleTable(rows: 3, instanceId: 6, width: 10000)
            var paragraph = Support.host(prefix: "가나", table: table, suffix: " 뒤")
            /// 두 줄 캐시 — 둘째 줄이 WCHAR 1에서 시작한다. 인자는 줄마다 (위치, 높이).
            func cache(_ first: (Int32, Int32), _ second: (Int32, Int32)) throws {
                paragraph.paraLineSeg = try HwpSynthetic.splitParagraphWithControlMarkers(
                    lines: [(characters: 1, marker: false)],
                    segments: [(first.0, first.1, 0), (second.0, second.1, 1)],
                    markerCode: 11
                ).paraLineSeg
            }
            func isStale(_ heights: [Int: CGFloat] = [0: 30]) -> Bool {
                HwpParagraphLayout.lineCacheIsStale(paragraph, inlineTableHeights: heights)
            }
            // 표(WCHAR 2)는 둘째 세그먼트(시작 1) 줄에 있다 — 그 줄이 낮으면 첫 줄이 높아도 낡았다.
            try cache((0, 4000), (4600, 1000))
            expect(isStale()) == true
            try cache((0, 1000), (1600, 3000))
            expect(isStale()) == false
            expect(isStale([:])) == false
            expect(HwpParagraphLayout.controlHostSegments(of: paragraph)) == [1]
            // 컨트롤 수와 컨트롤 문자 수가 어긋나면 위치를 못 풀어 가장 높은 줄(40pt)과 견준다.
            paragraph.ctrlHeaderArray = [.table(table), .table(table)]
            try cache((0, 4000), (4600, 1000))
            expect(HwpParagraphLayout.controlHostSegments(of: paragraph)).to(beNil())
            expect(isStale()) == false
        }
    }
#endif
