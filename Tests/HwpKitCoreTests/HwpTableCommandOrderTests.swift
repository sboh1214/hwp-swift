import CoreGraphics
import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 표 페인트 명령의 순서 (#191 리뷰) — 셀 테두리는 표의 **모든 셀 채움 뒤**에 모아서 내고, 셀
/// 내용(텍스트·개체·중첩 표)은 종전처럼 테두리 위에 온다. 모서리에 중심을 둔 선은 이웃 셀 안으로
/// t/2 걸치므로 셀 순서대로 섞어 내면 나중 셀의 채움이 앞 셀 테두리의 바깥 절반을 덮어 반 굵기로
/// 보이고, 내용까지 테두리 아래로 내리면 히트 역순(`tableHit`: 내용 → 칸막이)과 갈린다. 중첩
/// 표·각주 안 표는 자기 채움 → 테두리 → 내용 덩어리로 walker가 방문한 자리에 든다
/// (`HwpTableCommandBuffer`).
final class HwpTableCommandOrderTests: XCTestCase {
    private static let black = HwpRGBColor(red: 0, green: 0, blue: 0)

    private enum Step: Equatable {
        case fill, text(String), image, border, other
    }

    private static func steps(_ commands: [HwpPaintCommand]) -> [Step] {
        commands.map {
            switch $0 {
            case .fillRect: .fill
            case let .drawText(attributed, _, _): .text(attributed.string)
            case .drawImageReference, .drawPlaceholder: .image
            case let .drawPath(_, fill, stroke, _) where fill != nil && stroke == nil: .border
            default: .other
            }
        }
    }

    private static func paragraph(_ text: String, rect: CGRect) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: text),
            frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
            rect: rect, paragraphId: 1, hyperlinkURL: nil
        )
    }

    /// 셀 하나짜리 표 (채움 + 폭 1 테두리 + 텍스트)
    private static func table(
        _ text: String, size: CGSize, fill: HwpRGBColor? = HwpRGBColor(red: 0, green: 255, blue: 0)
    ) -> HwpTableFrame {
        let rect = CGRect(origin: .zero, size: size)
        return HwpTableFrame(
            outerFrame: rect,
            rows: [HwpTableRowFrame(rowFrame: rect, cells: [HwpTableCellFrame(
                cellFrame: rect, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [paragraph(text, rect: rect)],
                borders: .uniform(width: 1, color: black), fillColor: fill
            )])],
            borderColor: black, borderWidth: 1
        )
    }

    private static func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
        HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
            blocks: blocks, pageNumber: 1
        )
    }

    func testCellBordersFollowAllFillsAndPrecedeCellContents() {
        let inner = CGRect(x: 10, y: 5, width: 60, height: 30)
        let nested = HwpNestedTableFrame(
            rect: inner, table: Self.table("n", size: inner.size), controlInstanceId: 9
        )
        let cells = (0 ..< 2).map { column in
            let frame = CGRect(x: CGFloat(column) * 100, y: 0, width: 100, height: 40)
            return HwpTableCellFrame(
                cellFrame: frame,
                row: 0, column: column, rowSpan: 1, columnSpan: 1,
                paragraphs: [Self.paragraph("c\(column)", rect: frame)],
                borders: .uniform(width: 2, color: Self.black),
                fillColor: HwpRGBColor(red: 255, green: 255, blue: 0),
                nestedTables: column == 1 ? [nested] : [],
                images: column == 0 ? [HwpCellImage(
                    rect: CGRect(x: 60, y: 0, width: 50, height: 40), binItemId: 3, style: nil,
                    clipRect: nil, controlInstanceId: 3
                )] : []
            )
        }
        let tableRect = CGRect(x: 0, y: 0, width: 200, height: 40)
        let table = HwpTableFrame(
            outerFrame: tableRect,
            rows: [HwpTableRowFrame(rowFrame: tableRect, cells: cells)],
            borderColor: Self.black, borderWidth: 1
        )
        let list = HwpPaintListBuilder().build(for: Self.page([
            AnyHwpBlock(frame: tableRect, kind: .table, payload: .table(table)),
        ]))
        let steps = Self.steps(list.commands)
        // 바깥 표: 채움 2 → 테두리 8 → 내용 (c0 텍스트·그림 → c1 텍스트 → 중첩 표 덩어리)
        expect(Array(steps.prefix(10))) == [.fill, .fill] + Array(repeating: .border, count: 8)
        let contents = Array(steps.dropFirst(10))
        expect(Array(contents.prefix(3))) == [.text("c0"), .image, .text("c1")]
        // 중첩 표 덩어리: 채움 → 테두리 4 → 텍스트
        expect(Array(contents.dropFirst(3)))
            == [.fill] + Array(repeating: .border, count: 4) + [.text("n")]
    }

    /// 각주 안 표는 평면·zOrder 정렬에 낀다 (R47 #1) — 글 뒤로 표의 채움·테두리·텍스트 덩어리는
    /// 각주 본문 텍스트 **앞**에, 글 앞으로 표는 뒤에 그대로 놓인다 (테두리만 뒤로 빠지지 않는다)
    func testFootnoteTableBordersStayInTheTablePlane() {
        let frame = CGRect(x: 50, y: 600, width: 400, height: 40)
        func footnote(paintsBehindText: Bool) -> HwpFootnoteBlock {
            HwpFootnoteBlock(
                frame: frame,
                paragraphs: [Self.paragraph(
                    "각주 본문", rect: CGRect(x: 0, y: 0, width: 400, height: 20)
                )],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                nestedTables: [HwpNestedTableFrame(
                    rect: CGRect(x: 0, y: 0, width: 80, height: 20),
                    table: Self.table("t", size: CGSize(width: 80, height: 20)),
                    controlInstanceId: 9, paintsBehindText: paintsBehindText
                )]
            )
        }
        func steps(_ block: HwpFootnoteBlock) -> [Step] {
            Self.steps(HwpPaintListBuilder(fontResolver: .testDeterministic)
                .footnoteCommands(block, blockFrame: frame, drawSeparator: false))
        }
        let tableUnit: [Step] = [.fill] + Array(repeating: .border, count: 4) + [.text("t")]
        expect(steps(footnote(paintsBehindText: true))) == tableUnit + [.text("각주 본문")]
        expect(steps(footnote(paintsBehindText: false))) == [.text("각주 본문")] + tableUnit
    }
}
