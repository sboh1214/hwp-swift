import CoreGraphics
import Foundation

/// 블록 payload의 텍스트 콘텐츠를 렌더 방출 순서 그대로 순회한다.
/// `HwpPaintListBuilder`(drawText 방출)와 `HwpSelectableText`(선택 단위)가
/// 이 순회를 공유한다 — 순서·오프셋 계약은 `HwpSelectableTextPaintParityTests`가
/// 고정한다.
public enum HwpBlockContentWalker {
    /// 블록의 텍스트 콘텐츠 (길이 > 0)를 렌더 방출 순서로 방문한다.
    /// rect는 페이지 로컬 top-down — 렌더는 origin/폭을, 선택은 rect 전체를 쓴다.
    public static func walkText(
        block: AnyHwpBlock,
        visit: (NSAttributedString, CGRect) -> Void
    ) {
        switch block.payload {
        case let .table(table):
            walkTable(table, origin: block.frame.origin, onParagraphText: visit)
        case let .textbox(textbox):
            walkParagraphs(textbox.paragraphs, offset: block.frame.origin, visit: visit)
        case let .footnote(footnote):
            walkParagraphs(footnote.paragraphs, offset: block.frame.origin, visit: visit)
        case .shape, .image, .chart:
            return
        case nil:
            // 본문 텍스트 (분할된 표/글상자/각주 조각 포함) — 블록 자체가 단위
            guard [.text, .table, .textbox, .footnote].contains(block.kind),
                  let attributed = block.attributedString, attributed.length > 0
            else { return }
            visit(attributed, block.frame)
        }
    }

    /// 문단 배열 (길이 > 0)을 블록 offset을 더한 페이지 좌표로 방문한다
    /// (표 셀·글상자·각주 공용).
    public static func walkParagraphs(
        _ paragraphs: [HwpLaidOutParagraph],
        offset: CGPoint,
        visit: (NSAttributedString, CGRect) -> Void
    ) {
        for paragraph in paragraphs where paragraph.attributedString.length > 0 {
            visit(
                paragraph.attributedString,
                paragraph.rect.offsetBy(dx: offset.x, dy: offset.y)
            )
        }
    }

    /// 표를 렌더 방출 순서로 순회한다 — 셀마다
    /// onCellStart → onParagraphText* → onCellImage* → (중첩 표 재귀).
    /// 렌더는 세 이벤트를 모두 (fill/border·drawText·셀 그림), 선택은
    /// onParagraphText만 소비한다.
    public static func walkTable(
        _ table: HwpTableFrame,
        origin: CGPoint,
        onCellStart: (HwpTableCellFrame, CGRect) -> Void = { _, _ in },
        onParagraphText: (NSAttributedString, CGRect) -> Void,
        onCellImage: (HwpCellImage, CGRect) -> Void = { _, _ in }
    ) {
        for row in table.rows {
            for cell in row.cells {
                onCellStart(cell, cell.cellFrame.offsetBy(dx: origin.x, dy: origin.y))
                walkParagraphs(cell.paragraphs, offset: origin, visit: onParagraphText)
                // 셀 안 그림은 셀 콘텐츠로 순회한다 (표-로컬 rect + 블록 origin)
                for image in cell.images {
                    onCellImage(image, image.rect.offsetBy(dx: origin.x, dy: origin.y))
                }
                // 중첩 표는 셀 안 위치를 origin으로 재귀 순회한다 —
                // origin 합성 산식은 여기 한 곳에만 둔다.
                for nested in cell.nestedTables {
                    walkTable(
                        nested.table,
                        origin: CGPoint(
                            x: origin.x + nested.rect.minX,
                            y: origin.y + nested.rect.minY
                        ),
                        onCellStart: onCellStart,
                        onParagraphText: onParagraphText,
                        onCellImage: onCellImage
                    )
                }
            }
        }
    }
}
