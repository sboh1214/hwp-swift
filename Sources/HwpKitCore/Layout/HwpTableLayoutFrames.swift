import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

// MARK: - 행/셀 프레임 조립 (레이아웃 결과 → HwpTableRowFrame/HwpTableCellFrame)

extension HwpTableLayout {
    /// 행 높이 = max(저작된 셀 높이, 콘텐츠 높이). span 셀은 마지막 행에 나머지를 반영.
    func resolvedRowHeights(
        placed: [PlacedCell],
        rowCount: Int,
        defaultHeight: CGFloat
    ) -> [CGFloat] {
        var heights = [CGFloat](repeating: 0, count: rowCount)
        for cell in placed where cell.rowSpan == 1 {
            heights[cell.row] = max(
                heights[cell.row],
                max(cell.contentHeight, cell.authoredHeight)
            )
        }
        for cell in placed where cell.rowSpan > 1 {
            let needed = max(cell.contentHeight, cell.authoredHeight)
            let spanEnd = min(cell.row + cell.rowSpan, rowCount)
            let current = heights[cell.row ..< spanEnd].reduce(CGFloat(0), +)
            if needed > current {
                heights[spanEnd - 1] += needed - current
            }
        }
        return heights.map { $0 > 0 ? $0 : defaultHeight }
    }

    func rows(
        placed: [PlacedCell],
        rowHeights: [CGFloat],
        columnWidths: [CGFloat],
        context: LayoutContext
    ) -> [HwpTableRowFrame] {
        var result: [HwpTableRowFrame] = []
        result.reserveCapacity(rowHeights.count)
        var rowOrigins: [CGFloat] = []
        var yOffset = context.metrics.spacing
        for height in rowHeights {
            rowOrigins.append(yOffset)
            yOffset += height + context.metrics.spacing
        }

        let rowWidth = columnWidths.reduce(CGFloat(0), +)
            + context.metrics.spacing * CGFloat(columnWidths.count + 1)

        for row in rowHeights.indices {
            let cells = placed
                .filter { $0.row == row }
                .sorted { $0.column < $1.column }
                .map { cell in
                    cellFrame(
                        for: cell,
                        rowOrigins: rowOrigins,
                        rowHeights: rowHeights,
                        columnWidths: columnWidths,
                        context: context
                    )
                }
            result.append(HwpTableRowFrame(
                rowFrame: CGRect(
                    x: 0,
                    y: rowOrigins[row],
                    width: rowWidth,
                    height: rowHeights[row]
                ),
                cells: cells
            ))
        }
        return result
    }

    func cellFrame(
        for cell: PlacedCell,
        rowOrigins: [CGFloat],
        rowHeights: [CGFloat],
        columnWidths: [CGFloat],
        context: LayoutContext
    ) -> HwpTableCellFrame {
        let metrics = context.metrics
        let cellRect = CGRect(
            x: xOffset(for: cell.column, columnWidths: columnWidths, spacing: metrics.spacing),
            y: rowOrigins[cell.row],
            width: width(
                from: cell.column,
                span: cell.columnSpan,
                columnWidths: columnWidths,
                spacing: metrics.spacing
            ),
            height: height(
                from: cell.row,
                span: cell.rowSpan,
                rowHeights: rowHeights,
                spacing: metrics.spacing
            )
        )
        let margins = cellMargins(for: cell.cell, metrics: metrics)
        let laidOut = laidOutContents(
            for: cell,
            in: cellRect,
            margins: margins,
            index: context.index
        )

        let resolved = resolvedBorderFill(
            id: cell.cell.header.cellProperty?.borderFillId
                ?? context.table.tableProperty.borderFillId,
            index: context.index
        )
        return HwpTableCellFrame(
            cellFrame: cellRect,
            row: cell.row,
            column: cell.column,
            rowSpan: cell.rowSpan,
            columnSpan: cell.columnSpan,
            paragraphs: laidOut.paragraphs,
            borders: borders(from: resolved),
            fillColor: fillColor(from: resolved),
            nestedTables: laidOut.nestedTables
        )
    }

    /// 셀 안 문단과 중첩 표를 셀 여백 안쪽에 위에서 아래로 쌓는다.
    func laidOutContents(
        for cell: PlacedCell,
        in cellRect: CGRect,
        margins: CellMargins,
        index: HwpIndex
    ) -> (paragraphs: [HwpLaidOutParagraph], nestedTables: [HwpNestedTableFrame]) {
        let textBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        var cursorY = cellRect.minY + margins.top
        let innerX = cellRect.minX + margins.left
        let innerWidth = max(1, cellRect.width - margins.left - margins.right)
        var paragraphs: [HwpLaidOutParagraph] = []
        var nestedTables: [HwpNestedTableFrame] = []
        for content in cell.contents {
            let rect = CGRect(
                x: innerX,
                y: cursorY,
                width: innerWidth,
                height: content.frame.totalHeight
            )
            paragraphs.append(HwpLaidOutParagraph(
                attributedString: textBuilder.build(paragraph: content.paragraph),
                frame: content.frame,
                rect: rect,
                paragraphId: content.paragraph.paraHeader.paraId
            ))
            cursorY += content.frame.totalHeight
            for nested in content.nestedTables {
                nestedTables.append(HwpNestedTableFrame(
                    rect: CGRect(
                        x: innerX,
                        y: cursorY,
                        width: nested.frame.outerFrame.width,
                        height: nested.frame.outerFrame.height
                    ),
                    table: nested.frame,
                    controlInstanceId: nested.instanceId
                ))
                cursorY += nested.frame.outerFrame.height
            }
        }
        return (paragraphs, nestedTables)
    }

    func width(from column: Int, span: Int, columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let last = min(column + span, columnWidths.count)
        let widths = columnWidths[column ..< last].reduce(CGFloat(0), +)
        return widths + spacing * CGFloat(max(0, span - 1))
    }

    func xOffset(for column: Int, columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        spacing + columnWidths.prefix(column).reduce(CGFloat(0), +) + spacing * CGFloat(column)
    }

    func height(from row: Int, span: Int, rowHeights: [CGFloat], spacing: CGFloat) -> CGFloat {
        let last = min(row + span, rowHeights.count)
        let heights = rowHeights[row ..< last].reduce(CGFloat(0), +)
        return heights + spacing * CGFloat(max(0, span - 1))
    }
}
