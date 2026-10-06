import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 폭이 다른 단으로 옮긴 조각의 글자처럼 취급 표 예약 **폭** (#254 PR 리뷰) — 조각을 다시 풀 때
    /// (`HwpPaginator.placedFragment`) 상대 기준 표의 예약 폭은 그 단의 기준 폭 100%로만 풀렸는데,
    /// 레이아웃은 칸이 1pt 하한에 걸리면 그보다 넓게 그린다(`HwpTableLayout.coveringWidth`). 예약도
    /// 그 단에서 그려질 바깥 폭이어야 표가 뒤 글자를 덮지 않고 앵커가 그려진 표와 맞는다.
    final class HwpInlineTableRescaledWidthTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport
        private static let index = HwpIndex(from: CoreHwp.HwpFile())

        /// 비등폭 2단(268.37 / 134.16pt) — 넓은 단에서 잰 문단의 표 마커가 좁은 단 조각에 든다. 셀 간격
        /// 70pt의 단 기준 1칸 표는 넓은 단에서는 단 폭(268.37pt)이지만, 좁은 단에서는 간격 합 140pt가
        /// 단 폭을 넘어 칸이 1pt로 걸리므로 바깥 141pt로 그려진다. 좁은 단 조각의 마커도 141pt를
        /// 예약한다 — 기준 폭 100%(134.16pt)만 예약하면 표가 예약보다 6.84pt 넓다.
        func testFragmentInANarrowerColumnReservesTheDrawnTableWidth() async throws {
            let prefix = (0 ..< 14).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = (14 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let streamCount = UInt32(prefix.utf16.count + 8 + suffix.utf16.count)
            let boundary = streamCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(prefix + "X" + suffix, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 26837),
                .init(textIndex: boundary, location: 0, height: 1500, width: 13416),
                // 표(그리는 블록 141 × 80pt — 위 셀 간격 70 + 행 10pt. 줄 예약과 캐시 판정이 쓰는
                // `flowBlockHeight`에는 아래 셀 간격이 들지 않는다)를 실은 줄은 80pt 이상이어야 캐시가
                // 낡았다고 판정되지 않고 단 run대로 놓인다.
                .init(textIndex: boundary + 20, location: 2552, height: 16000, width: 13416),
            ], charCount: streamCount)
            paragraph.paraText = HwpSynthetic.paragraphWithInlineControl(
                prefix: prefix, suffix: suffix
            ).paraText
            var table = try Support.staleTable(
                rows: 1, instanceId: 7, width: 25000, cellText: { _ in "a" }
            )
            table.commonCtrlProperty.propertyInfo.widthRelativeToRawValue =
                CoreHwp.HwpCommonCtrlObjectWidthRelativeTo.column.rawValue
            table.commonCtrlProperty.propertyInfo.widthRelativeTo = .column
            table.tableProperty.cellSpacing = 7000
            paragraph.ctrlHeaderArray = [
                .table(table),
                .column(HwpSynthetic.column(count: 2, widths: [20682, 10339], gaps: [1747, 0])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section], index: Self.index, fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let placed = try XCTUnwrap(Support.table(on: page, instanceId: 7))
            expect(placed.frame.width).to(beCloseTo(141, within: 0.01))
            let attributed = try XCTUnwrap(columns[1].attributedString)
            let marker = (attributed.string as NSString).range(of: "\u{FFFC}").location
            expect(marker) != NSNotFound
            guard marker != NSNotFound else { return }
            let line = CTLineCreateWithAttributedString(
                attributed.attributedSubstring(from: NSRange(location: marker, length: 1))
            )
            expect(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
                .to(beCloseTo(placed.frame.width, within: 0.01))
        }
    }
#endif
