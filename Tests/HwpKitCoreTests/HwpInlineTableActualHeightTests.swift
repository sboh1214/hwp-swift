import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// `HwpInlineTableActualHeightTests`·`HwpInlineTableActualHeightContainerTests` 공용 입력 (#214).
    enum InlineTableActualHeightSupport {
        /// `rows`행 1열 글자처럼 취급 표 — 셀 저작 높이는 `authoredRowHeight`(기본 282 HWPUNIT =
        /// 한글 12.30 macOS `표 만들기`가 적는 여백 합, #160)이고 셀마다 10pt 문단이 있어 행이
        /// 10pt로 커진다(안쪽 여백 0). 공통 속성 높이는 기본적으로 저작 셀 높이의 합 — 셀 내용이
        /// 키우기 전의 **낡은** 높이다. 크기 기준은 절대값(실물처럼).
        static func staleTable(
            rows: Int,
            instanceId: UInt32,
            width: UInt32 = 20000,
            authoredRowHeight: UInt32 = 282,
            commonHeight: UInt32? = nil,
            margins: [CoreHwp.HWPUNIT16] = [0, 0, 0, 0],
            cellText: (Int) -> String = { "행 \($0)" }
        ) throws -> CoreHwp.HwpTable {
            var table = HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: width,
                    rowHeights: Array(repeating: authoredRowHeight, count: rows),
                    cellParagraphs: try (0 ..< rows).map {
                        [[try HwpSynthetic.textParagraph(cellText($0))]]
                    }
                ),
                treatAsChar: true,
                margins: margins
            )
            table.commonCtrlProperty.width = width
            table.commonCtrlProperty.height = commonHeight ?? authoredRowHeight * UInt32(rows)
            table.commonCtrlProperty.instanceId = instanceId
            table.commonCtrlProperty.propertyInfo.widthRelativeToRawValue = 4
            table.commonCtrlProperty.propertyInfo.widthRelativeTo = .absolute
            table.commonCtrlProperty.propertyInfo.heightRelativeToRawValue = 2
            table.commonCtrlProperty.propertyInfo.heightRelativeTo = .absolute
            return table
        }

        /// `prefix` + 표 마커(코드 11) + `suffix` — 캐시 없는 본문 문단.
        static func host(
            prefix: String = "",
            table: CoreHwp.HwpTable,
            suffix: String
        ) -> CoreHwp.HwpParagraph {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: prefix, suffix: suffix)
            host.ctrlHeaderArray = [.table(table)]
            return host
        }

        static func table(on page: HwpPage, instanceId: UInt32) -> AnyHwpBlock? {
            page.blocks.first { $0.kind == .table && $0.source?.controlInstanceId == instanceId }
        }

        static func textBlock(on page: HwpPage, containing text: String) -> AnyHwpBlock? {
            page.blocks.first {
                $0.kind == .text && $0.attributedString?.string.contains(text) == true
            }
        }

        /// 블록이 그리는 첫 줄 — 렌더러와 같은 조판.
        static func firstDrawnLine(of block: AnyHwpBlock) -> HwpDrawnLine? {
            guard let attributed = block.attributedString else { return nil }
            return HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: block.frame.origin,
                lineWidth: block.frame.width
            ).first
        }
    }

    /// 글자처럼 취급 표의 줄 예약은 **그려지는 높이**다 (#214·#218) — 저작 높이(공통 속성)가 셀
    /// 내용이 키운 실제 높이보다 작으면 줄이 표보다 작아 뒤 문단이 표를 덮는다.
    ///
    /// 기대값은 한컴오피스 한글 12.30.0(6446) macOS 실측이다 (2026-09-23, 합성 HWPX → PDF·재저장 줄
    /// 캐시): 저작 90.24pt·실제 410.24pt 표를 품은 문단 13개는 쪽마다 하나씩 13쪽이고, 그 줄의
    /// `vertsize`는 실제 높이 + 위·아래 바깥 여백(41590), `baseline`은 그 0.85배, 표 상단은 줄 상단 +
    /// 위 여백이다. 10pt 줄의 저작 8pt·실제 10pt 표는 줄 상단에(베이스라인 − 0.85 × 10), 공통 높이가
    /// 행 합보다 **큰** 표(30 vs 12.82pt)는 행 합으로 잡힌다. 본문보다 큰 표는 새 쪽 머리에 통째로
    /// 놓여 쪽 아래로 넘친다. 종전에는 줄이 저작 높이를 예약해 표들이 101.90pt 간격으로 겹쳤다.
    final class HwpInlineTableActualHeightTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport

        /// 이슈의 형상 — 저작 112.8pt·실제 400pt 표를 품은 문단 셋이 쪽마다 하나씩 놓이고, 줄은
        /// 표 + 바깥 여백 + 비율 여분(10pt 글자의 60%)만큼 전진한다.
        func testConsecutiveInlineTablesReserveTheirLaidOutHeight() async throws {
            let margins: [CoreHwp.HWPUNIT16] = [283, 283, 283, 283]
            let hosts = try (0 ..< 3).map { index in
                Support.host(
                    table: try Support.staleTable(
                        rows: 40, instanceId: UInt32(100 + index), margins: margins
                    ),
                    suffix: "table \(index)"
                )
            }
            let pages = try await InlineControlFragmentSupport.pages(
                of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: hosts)
            )
            expect(pages.count) == 3
            for (index, page) in pages.enumerated() {
                let table = try XCTUnwrap(Support.table(on: page, instanceId: UInt32(100 + index)))
                let host = try XCTUnwrap(Support.textBlock(on: page, containing: "table \(index)"))
                expect(table.frame.height).to(beCloseTo(400, within: 0.01))
                expect(table.frame.minY).to(beCloseTo(host.frame.minY + 2.83, within: 0.01))
                expect(host.frame.height).to(beCloseTo(400 + 5.66 + 6, within: 0.01))
                let line = try XCTUnwrap(Support.firstDrawnLine(of: host))
                expect(line.baselineOrigin.y)
                    .to(beCloseTo(host.frame.minY + 0.85 * 405.66, within: 0.01))
                expect(page.blocks.filter { $0.kind == .table }.count) == 1
            }
        }

        /// #218 F4 — 10pt 줄의 저작 8pt·실제 10pt 표는 줄 상단에 놓인다 (베이스라인 − 0.85 × 10).
        /// 저작 높이로 잡으면 베이스라인 − 6.8이라 1.7pt 아래였다.
        func testSmallTableAnchorsByItsLaidOutHeight() async throws {
            let host = Support.host(
                prefix: "가 ",
                table: try Support.staleTable(
                    rows: 1, instanceId: 7, width: 3000, authoredRowHeight: 800,
                    cellText: { _ in "셀" }
                ),
                suffix: " 뒤"
            )
            let pages = try await InlineControlFragmentSupport.pages(
                of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: [host])
            )
            let page = try XCTUnwrap(pages.first)
            let table = try XCTUnwrap(Support.table(on: page, instanceId: 7))
            let block = try XCTUnwrap(Support.textBlock(on: page, containing: " 뒤"))
            let line = try XCTUnwrap(Support.firstDrawnLine(of: block))
            expect(table.frame.height).to(beCloseTo(10, within: 0.01))
            expect(table.frame.minY).to(beCloseTo(line.baselineOrigin.y - 8.5, within: 0.01))
            expect(table.frame.minY).to(beCloseTo(block.frame.minY, within: 0.01))
        }

        /// 공통 높이(30pt)가 행 합(10pt)보다 커도 줄은 그려지는 높이로 잡힌다 — 최댓값이 아니다
        /// (한글 A4: `vertsize` 1282 = 행 합, 공통 3000 아님).
        func testAuthoredHeightTallerThanTheRowsDoesNotInflateTheLine() async throws {
            let host = Support.host(
                prefix: "가 ",
                table: try Support.staleTable(rows: 1, instanceId: 8, commonHeight: 3000),
                suffix: " 뒤"
            )
            let pages = try await InlineControlFragmentSupport.pages(
                of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: [host])
            )
            let page = try XCTUnwrap(pages.first)
            let table = try XCTUnwrap(Support.table(on: page, instanceId: 8))
            let block = try XCTUnwrap(Support.textBlock(on: page, containing: " 뒤"))
            expect(table.frame.height).to(beCloseTo(10, within: 0.01))
            expect(block.frame.height).to(beCloseTo(16, within: 0.01))
        }

        /// 본문 영역보다 큰 표는 새 쪽 머리에 통째로 놓인다 (한글도 나누지 않고 쪽 아래로 넘친다) —
        /// 저작 높이로 재면 앞 문단 쪽에 들어가는 것처럼 보여 그 쪽에 놓였다.
        func testInlineTableTallerThanTheBodyStartsAFreshPage() async throws {
            let host = Support.host(
                table: try Support.staleTable(rows: 80, instanceId: 9), suffix: "큰 표"
            )
            let pages = try await InlineControlFragmentSupport.pages(
                of: FloatingTablePrecedesTextSupport.paginator(bodyParagraphs: [
                    try HwpSynthetic.textParagraph("앞 문단"), host,
                    try HwpSynthetic.textParagraph("뒤 문단"),
                ])
            )
            expect(pages.count) == 3
            guard pages.count == 3 else { return }
            expect(Support.textBlock(on: pages[0], containing: "앞 문단")).toNot(beNil())
            expect(Support.table(on: pages[0], instanceId: 9)).to(beNil())
            let table = try XCTUnwrap(Support.table(on: pages[1], instanceId: 9))
            let block = try XCTUnwrap(Support.textBlock(on: pages[1], containing: "큰 표"))
            expect(table.frame.height).to(beCloseTo(800, within: 0.01))
            expect(table.frame.minY).to(beCloseTo(block.frame.minY, within: 0.01))
            expect(Support.textBlock(on: pages[2], containing: "뒤 문단")).toNot(beNil())
        }
    }
#endif
