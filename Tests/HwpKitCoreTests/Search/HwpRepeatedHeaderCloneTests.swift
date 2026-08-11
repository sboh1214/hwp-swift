import CoreGraphics
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 반복 표 머리행 클론 표식(#21/#25/#75)의 계약 — **실제 분할기 산출물**로 건다.
///
/// 합성 블록의 top-level `attributedString` 에 표식을 달아 검증하면 통과해도
/// 아무것도 증명하지 못한다: 프로덕션 반복 머리행 블록은 `attributedString` 이
/// nil 인 `.table` 이고, 표식은 셀 문단과 **셀 글상자 문단**에 붙는다
/// (#75 리뷰 8차가 그 구멍으로 들어왔다).
@MainActor
final class HwpRepeatedHeaderCloneTests: XCTestCase {
    private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    private static let black = HwpRGBColor(red: 0, green: 0, blue: 0)

    private static func paragraph(_ text: String, id: UInt32) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ),
            frame: HwpParagraphFrame(totalHeight: 14, lines: []),
            rect: CGRect(x: 0, y: 0, width: 100, height: 14),
            paragraphId: id
        )
    }

    /// 셀 문단 하나 + 셀 글상자 문단 하나를 가진 제목 행.
    private static func headerRow() -> HwpTableRowFrame {
        HwpTableRowFrame(
            rowFrame: CGRect(x: 0, y: 0, width: 200, height: 20),
            cells: [HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 0, width: 200, height: 20),
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [paragraph("머리행", id: 7)],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil,
                textboxes: [HwpCellTextbox(
                    rect: CGRect(x: 120, y: 0, width: 70, height: 18),
                    textbox: HwpTextboxFrame(
                        outerFrame: CGRect(x: 0, y: 0, width: 70, height: 18),
                        paragraphs: [paragraph("상자표제", id: 9)],
                        borderColor: nil,
                        borderWidth: 0,
                        fillColor: nil
                    ),
                    controlInstanceId: 1
                )]
            )]
        )
    }

    private static func bodyRow() -> HwpTableRowFrame {
        HwpTableRowFrame(
            rowFrame: CGRect(x: 0, y: 20, width: 200, height: 20),
            cells: [HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 20, width: 200, height: 20),
                row: 1, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [paragraph("본문칸", id: 11)],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil
            )]
        )
    }

    private static func table(rows: [HwpTableRowFrame]) -> HwpTableFrame {
        HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 40),
            rows: rows,
            borderColor: black,
            borderWidth: 0.5
        )
    }

    /// 뒷 페이지 조각 — 제목 행이 클론으로 얹힌다 (프로덕션 경로).
    private static func continuationSegment() -> HwpTableFrame {
        guard let frame = HwpTableSplitter.segmentFrame(
            rows: [bodyRow()],
            original: table(rows: [headerRow(), bodyRow()]),
            repeatedHeaderRows: [headerRow()]
        ) else {
            preconditionFailure("segmentFrame이 nil을 냈다 — 픽스처가 잘못됐다")
        }
        return frame
    }

    /// 첫 페이지 조각 — 제목 행이 원본 그대로다.
    private static func firstSegment() -> HwpTableFrame {
        guard let frame = HwpTableSplitter.segmentFrame(
            rows: [headerRow()],
            original: table(rows: [headerRow(), bodyRow()]),
            repeatedHeaderRows: []
        ) else {
            preconditionFailure("segmentFrame이 nil을 냈다 — 픽스처가 잘못됐다")
        }
        return frame
    }

    private static func tableBlock(_ frame: HwpTableFrame, y: CGFloat) -> AnyHwpBlock {
        AnyHwpBlock(
            frame: CGRect(x: 0, y: y, width: 200, height: frame.outerFrame.height),
            kind: .table,
            payload: .table(frame),
            role: .body
        )
    }

    /// 클론 표식만 뗀 쌍둥이 — 문자열·좌표·paraId는 그대로다.
    private static func strippingCloneMarker(_ frame: HwpTableFrame) -> HwpTableFrame {
        func stripped(_ paragraph: HwpLaidOutParagraph) -> HwpLaidOutParagraph {
            HwpLaidOutParagraph(
                attributedString: NSAttributedString(
                    string: paragraph.attributedString.string,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                ),
                frame: paragraph.frame,
                rect: paragraph.rect,
                paragraphId: paragraph.paragraphId,
                hyperlinkURL: paragraph.hyperlinkURL
            )
        }
        return HwpTableFrame(
            outerFrame: frame.outerFrame,
            rows: frame.rows.map { row in
                HwpTableRowFrame(
                    rowFrame: row.rowFrame,
                    cells: row.cells.map { cell in
                        HwpTableCellFrame(
                            cellFrame: cell.cellFrame,
                            row: cell.row,
                            column: cell.column,
                            rowSpan: cell.rowSpan,
                            columnSpan: cell.columnSpan,
                            paragraphs: cell.paragraphs.map(stripped),
                            borders: cell.borders,
                            fillColor: cell.fillColor,
                            nestedTables: cell.nestedTables,
                            images: cell.images,
                            shapes: cell.shapes,
                            textboxes: cell.textboxes.map { box in
                                box.withTextbox(
                                    box.textbox.withParagraphs(
                                        box.textbox.paragraphs.map(stripped)
                                    )
                                )
                            }
                        )
                    }
                )
            },
            borderColor: frame.borderColor,
            borderWidth: frame.borderWidth
        )
    }

    // MARK: - 표식이 붙는 자리

    func testSplitterMarksClonedHeaderCellParagraph() {
        let header = Self.continuationSegment().rows[0]
        let cell = header.cells[0]

        expect(cell.paragraphs[0].isRepeatedTableHeaderClone) == true
    }

    /// 셀 글상자 문단도 같은 표식을 받아야 한다 — `HwpSelectableText` 가 그
    /// 문단을 선택·검색 단위로 내므로, 빠지면 반복 머리행 안 글상자 텍스트만
    /// 페이지마다 중복으로 잡힌다 (#75 리뷰 8차).
    func testSplitterMarksClonedHeaderTextboxParagraph() {
        let header = Self.continuationSegment().rows[0]
        let textbox = header.cells[0].textboxes[0]

        expect(textbox.textbox.paragraphs[0].isRepeatedTableHeaderClone) == true
    }

    func testSplitterLeavesBodyRowUnmarked() {
        let body = Self.continuationSegment().rows[1]

        expect(body.cells[0].paragraphs[0].isRepeatedTableHeaderClone) == false
    }

    // MARK: - 동등성 전파

    /// 표식은 페이로드 **안**에 있으므로 `HwpLaidOutParagraph` 동등성이 그것을
    /// 봐야 블록까지 전파된다. `AnyHwpBlock` 의 top-level 속성만 보면 실제
    /// 반복 머리행 블록은 `attributedString` 이 nil 이라 늘 같다고 나온다.
    func testCloneMarkerBreaksTablePayloadEquality() {
        let clone = Self.continuationSegment()
        let twin = Self.strippingCloneMarker(clone)

        expect(Self.tableBlock(clone, y: 0)) != Self.tableBlock(twin, y: 0)
    }

    func testStrippedTwinDiffersOnlyByCloneMarker() {
        let clone = Self.continuationSegment()
        let twin = Self.strippingCloneMarker(clone)

        // 쌍둥이가 문자열·좌표까지 다르면 위 테스트가 표식을 증명하지 못한다
        expect(twin.rows[0].cells[0].paragraphs[0].attributedString.string)
            == clone.rows[0].cells[0].paragraphs[0].attributedString.string
        expect(twin.rows[0].cells[0].paragraphs[0].rect)
            == clone.rows[0].cells[0].paragraphs[0].rect
        expect(twin.rows[0].cells[0].paragraphs[0].isRepeatedTableHeaderClone) == false
    }

    // MARK: - 검색 결과

    /// 목록은 dedup, 하이라이트는 전량 — 글상자 문단에도 성립해야 한다.
    func testRepeatedHeaderTextboxMatchIsDeduplicated() {
        let page = HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: [
                Self.tableBlock(Self.firstSegment(), y: 0),
                Self.tableBlock(Self.continuationSegment(), y: 100),
            ],
            pageNumber: 1
        )
        let raw = HwpTextSearcher.matches(
            in: page, pageIndex: 0, query: HwpSearchQuery(text: "상자표제")
        )
        let deduplicated = HwpTextSearcher.deduplicatingRepeatedTableHeaders(raw)

        expect(raw.count) == 2
        expect(deduplicated.count) == 1
    }
}
