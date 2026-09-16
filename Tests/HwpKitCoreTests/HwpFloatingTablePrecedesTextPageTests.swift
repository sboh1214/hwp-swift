import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글줄 앞 자리 차지 표(#190)가 문단의 **첫 콘텐츠**가 되면서 쪽에 묶이는 것들 — 개요의
    /// 시작 쪽, 앞선 쪽 장식의 등록 시점, 조각을 못 낸 표, 나누지 않는 표의 목적지 여백
    /// (PR #212 리뷰). 빌더는 `FloatingTablePrecedesTextSupport`다.
    final class HwpFloatingTablePrecedesTextPageTests: XCTestCase {
        private typealias Support = FloatingTablePrecedesTextSupport

        private static func pageChrome(_ paginator: HwpPaginator) async throws -> [[String]] {
            var out: [[String]] = []
            for index in await 0 ..< (paginator.totalPages()) {
                let page = try await paginator.page(at: index)
                out.append((page?.blocks ?? []).filter { $0.role != .body }
                    .compactMap { $0.attributedString?.string })
            }
            return out
        }

        /// 컨트롤 문자 21(쪽 번호 위치)·11(표) 뒤에 `table anchor`가 이어지는 문단.
        private static func hostWithPageNumber(rowCount: Int) throws -> CoreHwp.HwpParagraph {
            var host = try Support.host(rowCount: rowCount)
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [
                CoreHwp.HwpChar(type: .extended, value: 21),
                CoreHwp.HwpChar(type: .extended, value: 11),
            ] + "table anchor".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            host.paraText = paraText
            host.ctrlHeaderArray = [
                HwpSynthetic.pageNumberPositionControl(numberFormat: 0, displayPosition: 5),
            ] + (host.ctrlHeaderArray ?? [])
            return host
        }

        /// 개요 제목 문단의 표가 글줄보다 앞서 여러 쪽에 걸치면 개요의 시작 쪽은 표의 첫 조각이
        /// 놓인 쪽이다 — 문단의 첫 콘텐츠가 쪽에 놓이는 지점이 개요 쪽이라는 계약(루트 AGENTS
        /// "쪽 기준이 둘이다"). 글줄 쪽으로 보고하면 목록이 두 쪽 늦다.
        func testOutlinePageIsTheFirstTableSegmentPage() async throws {
            var heading = Support.paragraphWithInlineControl(suffix: "제목")
            heading.ctrlHeaderArray = try Support.host(rowCount: 12).ctrlHeaderArray
            heading.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(pageHeight: 30000))],
                bodyParagraphs: [try Support.flow("앞 문단"), heading, try Support.flow("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                fontResolver: .testDeterministic
            )
            let total = await paginator.totalPages()
            let outline = await paginator.outline()
            var firstTablePage = 0
            var textPage = 0
            for index in 0 ..< total {
                let blocks = try await Support.blocks(of: paginator, page: index)
                if firstTablePage == 0, blocks.contains(where: { $0.kind == .table }) {
                    firstTablePage = index + 1
                }
                if blocks.contains(where: { $0.text.contains("제목") }) {
                    textPage = index + 1
                }
            }
            // 12행 표는 1쪽 5행·2쪽 6행·3쪽 1행이고 글줄은 3쪽이다.
            expect(total).to(equal(3))
            expect(firstTablePage).to(equal(1))
            expect(textPage).to(equal(3))
            expect(outline.map(\.pageNumber)).to(equal([firstTablePage]))
        }

        /// 표보다 앞선 쪽 장식은 표의 **첫 조각이 놓이는 순간** 등록된다 — 첫 행이 이 쪽에 안
        /// 들어가 다음 쪽으로 넘어가면 문단이 없는 이 쪽에는 번호가 없어야 한다 (종전엔 글줄이
        /// 넘어간 뒤 등록돼 그랬다). 놓기 전에 등록하면 이 쪽이 `- 1 -`을 받는다.
        func testPageChromePrecedingTheTableWaitsForItsFirstSegment() async throws {
            // 본문 200.8pt: 템플릿 + 앞 문단 열하나(192) → 남은 8.8. 첫 행 30이 안 들어가 표는
            // 2쪽 상단부터다.
            let fillers = try (0 ..< 11).map { try Support.flow("앞 문단 \($0)") }
            let host = try Self.hostWithPageNumber(rowCount: 10)
            let paginator = Support.paginator(pageHeight: 30000, bodyParagraphs: fillers + [host])
            let chrome = try await Self.pageChrome(paginator)
            expect(chrome).to(equal([[], ["- 2 -"], ["- 3 -"]]))
        }

        /// 조각을 하나도 안 낸 표(행 없는 표)는 글줄 앞에 놓인 것이 아니다 — 문단 위 간격을
        /// 걷지 않고, 그 문단의 재시도도 종전 경로다.
        func testEmptyTableDoesNotCountAsPlacedBeforeText() async throws {
            let index = HwpSynthetic.outlineIndex(paraShapes: [
                7: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 4000, tabDefId: 0
                ),
            ])
            var host = Support.paragraphWithInlineControl(suffix: "table anchor")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(cellWidth: 20000, rowHeights: [], cellParagraphs: []),
                treatAsChar: false, margins: [283, 283, 283, 283]
            ))]
            host.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 7, paraStyleId: 0)
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [try Support.flow("앞 문단"), host, try Support.flow("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let blocks = try await Support.blocks(of: paginator)
            let texts = blocks.filter { $0.kind == .text }
            expect(blocks.filter { $0.kind == .table }.map(\.rowCount)).to(equal([]))
            guard texts.count == 4 else {
                fail("본문 블록 4개(템플릿·앞·표 문단·뒤)를 기대: \(texts.map(\.text))")
                return
            }
            // 표가 놓이지 않았으므로 문단 위 간격 20pt가 그대로 든다.
            expect(texts[2].frame.minY).to(beCloseTo(texts[1].frame.maxY + 20, within: 0.01))
        }

        /// 나누지 않는 표는 목적지 용량으로 여백을 다시 잰다 — 표만 빈 쪽에 들어가고 여백까지는
        /// 안 들어가면 여백을 버려 표가 아래 여백·각주 자리로 넘치지 않게 한다.
        func testUnsplittableTableDropsMarginsThatDoNotFitTheDestination() async throws {
            // 본문 200.8pt: 앞 문단 뒤 190pt 표 + 여백 10·10은 이 쪽에 안 들어가 다음 쪽으로
            // 가는데, 빈 쪽에도 210 > 200.8이라 여백 없이 상단에 놓인다.
            var host = Support.paragraphWithInlineControl(suffix: "table anchor")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [19000], property: 0,
                    cellParagraphs: [[[try HwpSynthetic.textParagraph("행")]]]
                ),
                treatAsChar: false, margins: [283, 283, 1000, 1000]
            ))]
            let paginator = Support.paginator(pageHeight: 30000, bodyParagraphs: [
                try Support.flow("앞 문단"), host, try Support.flow("뒤 문단"),
            ])
            let first = try await Support.blocks(of: paginator)
            let second = try await Support.blocks(of: paginator, page: 1)
            expect(first.filter { $0.kind == .table }).to(beEmpty())
            let table = try XCTUnwrap(second.first { $0.kind == .table })
            let contentTop = first[0].frame.minY
            expect(table.frame.minY).to(beCloseTo(contentTop, within: 0.01))
            expect(table.frame.height).to(beCloseTo(190, within: 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(contentTop + 200.8 + 0.01))
        }

        // MARK: 셀 각주 예약

        private static func footnote(_ text: String) -> CoreHwp.HwpCtrlId {
            .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [
                HwpSynthetic.noteParagraph(
                    text, autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                ),
            ]))
        }

        /// 나누지 않는 표는 자기 셀 각주의 예약을 미리 반영해 여백·목적지를 정한다 — 예약 전엔
        /// 표 + 여백이 들어가고 예약 뒤엔 안 들어가는 자리에서 위 여백을 남기면 표가 각주
        /// 영역으로 넘친다 (수정 전 17pt 겹침).
        func testUnsplittableTableAnticipatesItsOwnCellFootnotes() async throws {
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [Self.footnote(String(repeating: " 긴 셀 각주", count: 20))]
            var host = Support.paragraphWithInlineControl(suffix: "table anchor")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [3000, 3000], property: 0,
                    cellParagraphs: [[[cell]], [[try HwpSynthetic.textParagraph("행 2")]]]
                ),
                treatAsChar: false, margins: [283, 283, 3000, 3000]
            ))]
            // 본문 200.8pt: 템플릿 + 앞 문단 넷(80) → 남은 120.8에 표 60 + 여백 60은 들어가지만
            // 셀 각주 48pt 예약 뒤에는 안 들어간다.
            let fillers = try (0 ..< 4).map { try Support.flow("앞 문단 \($0)") }
            let paginator = Support.paginator(
                pageHeight: 30000, bodyParagraphs: fillers + [host, try Support.flow("뒤 문단")]
            )
            let total = await paginator.totalPages()
            for index in 0 ..< total {
                let page = try await paginator.page(at: index)
                let blocks = try await Support.blocks(of: paginator, page: index)
                guard let table = blocks.first(where: { $0.kind == .table }) else { continue }
                // 표(여백 포함)는 그 쪽의 각주 영역과 겹치지 않는다.
                for note in (page?.blocks ?? []).filter({ $0.kind == .footnote }) {
                    expect(table.frame.maxY).to(beLessThanOrEqualTo(note.frame.minY + 0.01))
                }
            }
        }

        /// 제목 행 반복은 진입 쪽의 각주 예약이 아니라 **조각이 놓이는 쪽의 용량**으로 판정한다 —
        /// 앞 문단의 큰 각주가 남은 쪽에서 표가 시작해 첫 조각이 바로 넘어가도 이어지는 조각의
        /// 제목 행은 그대로다 (수정 전엔 표 전체의 반복이 꺼져 3쪽 조각이 `행 5`로 시작했다).
        func testRepeatedHeaderSurvivesAFootnoteReservationOnTheEntryPage() async throws {
            var noteHost = try Support.flow("각주 문단")
            noteHost.ctrlHeaderArray = [Self.footnote(String(repeating: " 긴 각주 본문", count: 60))]
            var host = Support.paragraphWithInlineControl(suffix: "table anchor")
            let rows = [6000] + Array(repeating: UInt32(3000), count: 10)
            let cells = try (0 ..< rows.count).map { [[try HwpSynthetic.textParagraph("행 \($0)")]] }
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: rows, property: 2 | (1 << 2),
                    headerRowCount: 1, cellParagraphs: cells
                ),
                treatAsChar: false, margins: [283, 283, 283, 283]
            ))]
            let paginator = Support.paginator(pageHeight: 30000, bodyParagraphs: [
                noteHost, host, try Support.flow("뒤 문단"),
            ])
            let total = await paginator.totalPages()
            var firstCellTexts: [String] = []
            for index in 0 ..< total {
                let page = try await paginator.page(at: index)
                for block in page?.blocks ?? [] where block.kind == .table {
                    guard case let .table(frame)? = block.payload else { continue }
                    let firstCell = frame.rows.first?.cells.first?.paragraphs.first
                    firstCellTexts.append(firstCell?.attributedString.string ?? "")
                }
            }
            // 1쪽은 각주 예약으로 표가 안 들어가 2쪽부터 시작하고, 3쪽 조각도 제목 행으로 시작한다.
            expect(firstCellTexts.count).to(beGreaterThanOrEqualTo(2))
            expect(Set(firstCellTexts)).to(equal(["행 0"]))
        }

        /// 셀 각주 예약이 넘긴 조각도 목적지 용량으로 여백을 다시 잰다 — 행 100 + 예약 78 +
        /// 여백 30은 빈 쪽에 안 들어가지만 여백을 버리면 통째로 들어간다 (수정 전엔 낡은 여백을
        /// 든 채 92.6 + 7.4로 갈려 쪽이 하나 늘었다).
        func testCellNoteAdvanceRefitsMarginsOnTheDestination() async throws {
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [Self.footnote(String(repeating: " 긴 셀 각주 본문", count: 20))]
            var host = Support.paragraphWithInlineControl(suffix: "table anchor")
            host.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [10000], cellParagraphs: [[[cell]]]
                ),
                treatAsChar: false, margins: [283, 283, 1500, 1500]
            ))]
            // 본문 200.8pt: 템플릿 + 앞 문단(32) 뒤 행 100은 들어가지만 각주 예약 78을 넣으면
            // 안 들어가 셀 각주 경로가 다음 쪽으로 넘긴다.
            let paginator = Support.paginator(pageHeight: 30000, bodyParagraphs: [
                try Support.flow("앞 문단"), host, try Support.flow("뒤 문단"),
            ])
            let total = await paginator.totalPages()
            var tables: [(page: Int, block: FloatingTablePrecedesTextSupport.Placed)] = []
            for index in 0 ..< total {
                let blocks = try await Support.blocks(of: paginator, page: index)
                tables += blocks.filter { $0.kind == .table }.map { (index + 1, $0) }
            }
            let first = try await Support.blocks(of: paginator)
            // 2쪽 상단에 여백 없이 통째로 놓이고 다른 쪽엔 조각이 없다.
            expect(tables.map(\.page)).to(equal([2]))
            expect(tables.map(\.block.frame.height)).to(equal([100]))
            expect(tables.first?.block.frame.minY ?? 0)
                .to(beCloseTo(first[0].frame.minY, within: 0.01))
        }

        /// 진단(`unsupportedElements`)의 쪽은 종전대로 문단이 **들어선** 쪽이고, 표의 첫 조각
        /// 쪽을 따르는 것은 개요뿐이다 — 공개 출력의 쪽이 표 착지 쪽으로 바뀌면 안 된다.
        func testDiagnosticPageStaysTheEntryPageWhileOutlineFollowsTheTable() async throws {
            var heading = Support.paragraphWithInlineControl(suffix: "제목")
            heading.ctrlHeaderArray = try Support.host(rowCount: 2).ctrlHeaderArray
            heading.paraHeader = try HwpSynthetic.outlineParaHeader(paraShapeId: 1, paraStyleId: 0)
            // 본문 200.8pt: 템플릿 + 앞 문단 열하나(192) → 첫 행 30이 안 들어가 표·글줄이 2쪽이다.
            let fillers = try (0 ..< 11).map { try Support.flow("앞 문단 \($0)") }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(pageHeight: 30000))],
                bodyParagraphs: fillers + [heading]
            )
            // 번호 정의 없는 개요 문단 → 문단 머리 진단이 뜬다.
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpSynthetic.outlineIndex(
                    paraShapes: [1: HwpSynthetic.outlineParaShape(levelRawValue: 0)]
                ),
                fontResolver: .testDeterministic
            )
            let total = await paginator.totalPages()
            let outline = await paginator.outline()
            let diagnostics = await paginator.unsupportedElements()
            expect(total).to(equal(2))
            expect(outline.map(\.pageNumber)).to(equal([2]))
            expect(diagnostics.map(\.page)).to(equal([1]))
        }
    }
#endif
