import CoreGraphics
import Foundation

/// 선택 가능한 텍스트 단위 하나 — `.drawText` 명령과 동형인
/// (attributedString, 페이지 로컬 rect) 쌍.
public struct HwpTextUnit {
    public let blockIndex: Int
    public let unitIndex: Int
    public let attributedString: NSAttributedString
    /// 페이지 로컬 top-down — `HwpPaintListBuilder`의 drawText origin/width와 동일
    public let rect: CGRect
}

/// 페이지의 블록을 문서 순서의 텍스트 단위로 전개한다. 전개 규칙은
/// `HwpPaintListBuilder`의 drawText 방출 규칙을 그대로 미러해 선택
/// 지오메트리가 렌더와 같은 입력을 쓰게 한다.
public enum HwpSelectableText {
    public static func units(in page: HwpPage) -> [HwpTextUnit] {
        var units: [HwpTextUnit] = []
        for (blockIndex, block) in page.blocks.enumerated() {
            // 머리말/꼬리말/쪽 번호는 본문 선택·복사에서 제외한다
            guard block.role == .body else { continue }
            var unitIndex = 0
            func append(_ attributed: NSAttributedString, _ rect: CGRect) {
                guard attributed.length > 0 else { return }
                units.append(HwpTextUnit(
                    blockIndex: blockIndex,
                    unitIndex: unitIndex,
                    attributedString: attributed,
                    rect: rect
                ))
                unitIndex += 1
            }

            appendUnits(of: block, append: append)
        }
        return units
    }

    private static func appendUnits(
        of block: AnyHwpBlock,
        append: (NSAttributedString, CGRect) -> Void
    ) {
        switch block.payload {
        case let .table(table):
            appendTable(table, origin: block.frame.origin, append: append)
        case let .textbox(textbox):
            for paragraph in textbox.paragraphs {
                append(
                    paragraph.attributedString,
                    paragraph.rect.offsetBy(
                        dx: block.frame.origin.x, dy: block.frame.origin.y
                    )
                )
            }
        case let .footnote(footnote):
            for paragraph in footnote.paragraphs {
                append(
                    paragraph.attributedString,
                    paragraph.rect.offsetBy(dx: block.frame.minX, dy: block.frame.minY)
                )
            }
        case .shape, .image, .chart:
            return
        case nil:
            // 본문 텍스트 (분할된 표/글상자/각주 조각 포함) — 블록 자체가 단위
            guard [.text, .table, .textbox, .footnote].contains(block.kind),
                  let attributed = block.attributedString
            else { return }
            append(attributed, block.frame)
        }
    }

    private static func appendTable(
        _ table: HwpTableFrame,
        origin: CGPoint,
        append: (NSAttributedString, CGRect) -> Void
    ) {
        for row in table.rows {
            for cell in row.cells {
                for paragraph in cell.paragraphs {
                    append(
                        paragraph.attributedString,
                        paragraph.rect.offsetBy(dx: origin.x, dy: origin.y)
                    )
                }
                for nested in cell.nestedTables {
                    appendTable(
                        nested.table,
                        origin: CGPoint(
                            x: origin.x + nested.rect.minX,
                            y: origin.y + nested.rect.minY
                        ),
                        append: append
                    )
                }
            }
        }
    }
}
