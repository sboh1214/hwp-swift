import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 셀 내용이 저작 높이보다 키운 글자처럼 취급 표가 **그려지는 높이**로 줄을 잡는지 (#214·#218).
///
/// 오라클은 `inline-table-actual-height` 쌍(한글 12.30.0이 2026-09-23에 저장)이다. 한글은 저장할 때
/// 표 공통 속성의 높이를 실제 높이로 고쳐 쓰므로 저장본은 그대로 열면 문제가 드러나지 않는다 —
/// 그래서 표 높이를 원본 합성 문서의 **낡은** 값(행마다 2.82pt인 저작 셀 높이의 합, `A4`만 30pt)으로
/// 되돌리고 모든 줄 캐시(각주·셀 안 포함)를 지워 이슈의 조건을 재현한 뒤, 그 재조판이 한글이 저장한
/// 캐시 배치와 같은 자리에 표를 놓는지 본다. 캐시 배치 자리는 한글 PDF와 0.1pt 안이다(README의 표).
/// 종전 재조판은 줄이 낡은 높이를 예약해 `A1`부터 표가 뒤 문단을 덮었고, 32행 표 셋이 한 쪽에
/// 101.90pt 간격으로 겹쳐 4쪽이 2쪽이 됐다. 폰트는 `testDeterministic` — 줄 상자는 글꼴 지표의
/// 함수가 아니다.
final class FixtureInlineTableActualHeightTests: XCTestCase {
    private static let id = "inline-table-actual-height"

    private static func fixtureURL(hwpx: Bool) -> URL {
        hwpx
            ? FixtureRoot.url(from: #file, subdirectory: "HwpxFixtures")
            .appendingPathComponent(id).appendingPathComponent("document.hwpx")
            : FixtureRoot.url(from: #file).appendingPathComponent(id)
            .appendingPathComponent("document.hwp")
    }

    /// 표 하나가 놓인 자리 — 쪽, 상단, 높이.
    private struct PlacedTable: Equatable {
        let page: Int
        let top: Double
        let height: Double
    }

    /// 원본 합성 문서의 공통 속성 높이 — 저작 셀 높이의 합. `A4`는 행 합보다 큰 30pt였다.
    private static func staleHeight(
        of table: CoreHwp.HwpTable, in paragraph: CoreHwp.HwpParagraph
    ) -> UInt32 {
        let units = (paragraph.paraText?.charArray ?? []).filter { $0.type == .char }.map(\.value)
        let text = String(decoding: units, as: UTF16.self)
        if text.hasPrefix("A4") {
            return 3000
        }
        return table.cellArray.reduce(0) { $0 + ($1.header.cellProperty?.height ?? 0) }
    }

    /// 글자처럼 취급 표의 높이를 낡은 값으로 되돌리고 모든 줄 캐시를 지운 사본 (각주·셀 안까지).
    private static func stale(_ paragraphs: [CoreHwp.HwpParagraph]) -> [CoreHwp.HwpParagraph] {
        paragraphs.map { paragraph in
            var copy = paragraph
            copy.paraLineSeg.paraLineSegInternalArray = []
            copy.ctrlHeaderArray = copy.ctrlHeaderArray?.map { control in
                switch control {
                case var .table(table):
                    if table.commonCtrlProperty.propertyInfo.treatAsChar {
                        table.commonCtrlProperty.height = staleHeight(of: table, in: paragraph)
                    }
                    table.cellArray = table.cellArray.map { cell in
                        var cell = cell
                        cell.paragraphArray = stale(cell.paragraphArray)
                        return cell
                    }
                    return .table(table)
                case var .footnote(note):
                    note.listArray = note.listArray.map { list in
                        var list = list
                        list.paragraphArray = stale(list.paragraphArray)
                        return list
                    }
                    return .footnote(note)
                default:
                    return control
                }
            }
            return copy
        }
    }

    private struct Rendered {
        let pageCount: Int
        /// 본문 표 (문서 순서)
        let tables: [PlacedTable]
        /// 각주 안 표 — 각주 블록 기준 상단과 높이
        let noteTable: CGRect?
        /// 각주 글줄 베이스라인 − 각주 문단 상단
        let noteBaselineOffset: Double?
    }

    private static func render(hwpx: Bool, stale useStale: Bool) async throws -> Rendered {
        let file = try CoreHwp.HwpFile(fromPath: fixtureURL(hwpx: hwpx).path)
        var sections = file.displaySectionArray
        if useStale {
            for index in sections.indices {
                sections[index].paragraph = stale(sections[index].paragraph)
            }
        }
        let paginator = HwpPaginator(
            sections: sections, index: HwpIndex(from: file), fontResolver: .testDeterministic,
            imageStore: HwpImageStore(from: file)
        )
        var tables: [PlacedTable] = []
        var noteTable: CGRect?
        var noteBaselineOffset: Double?
        var pageIndex = 0
        while let page = try await paginator.page(at: pageIndex) {
            for block in page.blocks {
                switch block.payload {
                case .table:
                    tables.append(PlacedTable(
                        page: pageIndex,
                        top: (Double(block.frame.minY) * 100).rounded() / 100,
                        height: (Double(block.frame.height) * 100).rounded() / 100
                    ))
                case let .footnote(note):
                    noteTable = note.nestedTables.first?.rect
                    if let paragraph = note.paragraphs.first,
                       let line = HwpDrawnTextLayout.lines(
                           attributedString: paragraph.attributedString,
                           origin: paragraph.rect.origin, lineWidth: paragraph.rect.width
                       ).first
                    {
                        noteBaselineOffset = Double(line.baselineOrigin.y - paragraph.rect.minY)
                    }
                default:
                    break
                }
            }
            pageIndex += 1
        }
        return Rendered(
            pageCount: pageIndex, tables: tables, noteTable: noteTable,
            noteBaselineOffset: noteBaselineOffset
        )
    }

    /// 낡은 높이·캐시 없는 재조판이 한글의 캐시 배치와 같은 쪽·자리에 모든 표를 놓는다 (HWP·HWPX).
    func testStaleHeightReflowPlacesTablesWhereHancomDid() async throws {
        for hwpx in [false, true] {
            let label = hwpx ? "HWPX" : "HWP"
            let cached = try await Self.render(hwpx: hwpx, stale: false)
            let reflowed = try await Self.render(hwpx: hwpx, stale: true)
            expect(cached.pageCount).to(equal(4), description: label)
            expect(reflowed.pageCount).to(equal(4), description: label)
            expect(reflowed.tables.count).to(equal(12), description: label)
            expect(reflowed.tables).to(equal(cached.tables), description: label)
            expect(reflowed.noteTable?.minY).to(beCloseTo(0, within: 0.01), description: label)
            expect(reflowed.noteTable?.height)
                .to(beCloseTo(38.46, within: 0.01), description: label)
            let offset = try XCTUnwrap(reflowed.noteBaselineOffset, label)
            expect(offset).to(
                beCloseTo(cached.noteBaselineOffset ?? .nan, within: 0.01), description: label
            )
            expect(offset).to(beCloseTo(0.85 * 38.46, within: 0.01), description: label)
        }
    }

    /// 한글 PDF의 표 상단(테두리 선 중심, 선 굵기의 절반쯤 아래로 찍힌다)과 캐시 줄 상단 + 위 여백 —
    /// 재조판이 같은 값을 내므로 한 벌만 핀한다 (README의 표).
    func testReflowedTableTopsMatchTheHancomPdf() async throws {
        let reflowed = try await Self.render(hwpx: false, stale: true)
        let expected: [PlacedTable] = [
            .init(page: 0, top: 118.03, height: 51.28), // A1 (여백 2.83)
            .init(page: 0, top: 178.14, height: 51.28), // A2
            // A3 2행 (위 여백 7) — 방출 순서는 문단 안 서수
            .init(page: 0, top: 266.61, height: 25.64),
            .init(page: 0, top: 235.42, height: 64.10), // A3 5행
            .init(page: 0, top: 305.52, height: 12.82), // A4 (공통 30pt 아님)
            .init(page: 0, top: 324.34, height: 10.00), // A5 (#218 F4)
            .init(page: 0, top: 340.34, height: 51.28), // A6 (40pt 줄)
            .init(page: 0, top: 415.62, height: 40.00), // A7 (대조군)
            .init(page: 0, top: 477.62, height: 38.46), // A8 둘째 줄
            .init(page: 1, top: 102.03, height: 410.24), // table SOLID
            .init(page: 2, top: 102.03, height: 410.24), // table DOT
            .init(page: 3, top: 102.03, height: 410.24), // table DASH
        ]
        expect(reflowed.tables) == expected
    }
}
