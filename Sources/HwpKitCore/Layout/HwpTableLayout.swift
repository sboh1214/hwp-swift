import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

public struct HwpTableLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    /// 표 하나를 레이아웃한다. 페이지 분할은 호출자(paginator)가 row 단위로 수행한다.
    public func layout(
        table: CoreHwp.HwpTable,
        availableWidth: CGFloat,
        index: HwpIndex
    ) -> Result<HwpTableFrame, HwpUnsupportedElement> {
        if containsNestedTable(table) {
            return .failure(HwpUnsupportedElement(kind: .placeholder, page: 0, hint: "표: 중첩 표"))
        }

        let property = table.tableProperty
        let rowCount = max(Int(property.rowCount), property.rowCellCounts.count)
        let columnCount = Int(property.columnCount)
        guard rowCount > 0, columnCount > 0 else {
            return .success(emptyFrame(availableWidth: availableWidth))
        }

        let outerWidth = resolvedOuterWidth(table: table, availableWidth: availableWidth)
        let metrics = TableMetrics(property: property)
        let context = LayoutContext(table: table, metrics: metrics, index: index)
        let columnWidths = resolvedColumnWidths(
            table: table,
            columnCount: columnCount,
            outerWidth: outerWidth,
            spacing: metrics.spacing
        )
        let placed = placeCells(
            context: context,
            rowCount: rowCount,
            columnCount: columnCount,
            columnWidths: columnWidths
        )

        let rowHeights = resolvedRowHeights(
            placed: placed,
            rowCount: rowCount,
            defaultHeight: max(1, metrics.innerHeightAdjustment)
        )
        let totalHeight = rowHeights.reduce(CGFloat(0), +)
            + metrics.spacing * CGFloat(rowCount + 1)

        let frame = HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: outerWidth, height: totalHeight),
            rows: rows(
                placed: placed,
                rowHeights: rowHeights,
                columnWidths: columnWidths,
                context: context
            ),
            borderColor: outerBorderColor(table: table, index: index),
            borderWidth: 1
        )
        return .success(frame)
    }
}

private extension HwpTableLayout {
    struct TableMetrics {
        let spacing: CGFloat
        let innerLeft: CGFloat
        let innerRight: CGFloat
        let innerTop: CGFloat
        let innerBottom: CGFloat

        var innerWidthAdjustment: CGFloat { innerLeft + innerRight }
        var innerHeightAdjustment: CGFloat { innerTop + innerBottom }

        init(property: CoreHwp.HwpTableProperty) {
            spacing = max(0, HwpUnits.points(fromHwpUnit16: property.cellSpacing))
            innerLeft = max(0, HwpUnits.points(fromHwpUnit16: property.leftInnerMargin))
            innerRight = max(0, HwpUnits.points(fromHwpUnit16: property.rightInnerMargin))
            innerTop = max(0, HwpUnits.points(fromHwpUnit16: property.topInnerMargin))
            innerBottom = max(0, HwpUnits.points(fromHwpUnit16: property.bottomInnerMargin))
        }
    }

    /// 표 하나를 레이아웃하는 동안 공유되는 입력 (표 모델 + 여백 지표 + id 매핑 인덱스)
    struct LayoutContext {
        let table: CoreHwp.HwpTable
        let metrics: TableMetrics
        let index: HwpIndex
    }

    /// 셀 4방향 안쪽 여백 (pt)
    struct CellMargins {
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat
        let bottom: CGFloat
    }

    struct GridPosition: Hashable {
        let row: Int
        let column: Int
    }

    struct PlacedCell {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let contentHeight: CGFloat
        let authoredHeight: CGFloat
        let cell: CoreHwp.HwpTableCell
        let paragraphSources: [(paragraph: CoreHwp.HwpParagraph, frame: HwpParagraphFrame)]
    }

    func containsNestedTable(_ table: CoreHwp.HwpTable) -> Bool {
        table.cellArray.contains { cell in
            cell.paragraphArray.contains { paragraph in
                paragraph.ctrlHeaderArray?.contains { ctrl in
                    if case .table = ctrl { return true }
                    return false
                } ?? false
            }
        }
    }

    func emptyFrame(availableWidth: CGFloat) -> HwpTableFrame {
        HwpTableFrame(
            outerFrame: CGRect(x: 0, y: 0, width: availableWidth, height: 0),
            rows: [],
            borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
            borderWidth: 1
        )
    }

    func resolvedOuterWidth(table: CoreHwp.HwpTable, availableWidth: CGFloat) -> CGFloat {
        let authored = HwpUnits.points(fromHwpUnitU: table.commonCtrlProperty.width)
        guard authored > 1 else { return availableWidth }
        return min(authored, availableWidth)
    }

    /// colSpan == 1 셀의 저작된 폭으로 열 폭을 복원하고, 남는 열은 균등 분배한다.
    func resolvedColumnWidths(
        table: CoreHwp.HwpTable,
        columnCount: Int,
        outerWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: columnCount)
        for cell in table.cellArray {
            guard let property = cell.header.cellProperty,
                  property.columnSpan == 1,
                  Int(property.columnAddress) < columnCount
            else { continue }
            let width = HwpUnits.points(fromHwpUnitU: property.width)
            guard width > 0 else { continue }
            widths[Int(property.columnAddress)] = max(widths[Int(property.columnAddress)], width)
        }

        let totalSpacing = spacing * CGFloat(columnCount + 1)
        let contentWidth = max(1, outerWidth - totalSpacing)
        let knownSum = widths.reduce(CGFloat(0), +)
        let unknownCount = widths.filter { $0 <= 0 }.count
        if unknownCount > 0 {
            let fallback = max(1, (contentWidth - knownSum) / CGFloat(unknownCount))
            widths = widths.map { $0 > 0 ? $0 : fallback }
        }

        // 저작된 폭 합계가 표 폭과 다르면 비례 배분으로 맞춘다.
        let sum = widths.reduce(CGFloat(0), +)
        if sum > 0, abs(sum - contentWidth) > 0.5 {
            let scale = contentWidth / sum
            widths = widths.map { max(1, $0 * scale) }
        }
        return widths
    }

    func placeCells(
        context: LayoutContext,
        rowCount: Int,
        columnCount: Int,
        columnWidths: [CGFloat]
    ) -> [PlacedCell] {
        let textBuilder = HwpTextRunBuilder(index: context.index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout()
        var placedCells: [PlacedCell] = []
        var occupied = Set<GridPosition>()

        for cell in context.table.cellArray {
            guard let placement = placement(
                for: cell,
                rowCount: rowCount,
                columnCount: columnCount,
                occupied: &occupied
            ) else { continue }

            let spannedWidth = width(
                from: placement.column,
                span: placement.columnSpan,
                columnWidths: columnWidths,
                spacing: context.metrics.spacing
            )
            let margins = cellMargins(for: cell, metrics: context.metrics)
            let innerWidth = max(1, spannedWidth - margins.left - margins.right)

            var paragraphSources: [(CoreHwp.HwpParagraph, HwpParagraphFrame)] = []
            for paragraph in cell.paragraphArray {
                let attributed = textBuilder.build(paragraph: paragraph)
                let paraShape = context.index.paraShape(
                    id: UInt32(paragraph.paraHeader.paraShapeId)
                ) ?? context.index.paraShape(id: 0) ?? CoreHwp.HwpParaShape()
                let frame = paragraphLayout.layout(
                    attributedString: attributed,
                    paraShape: paraShape,
                    columnWidth: innerWidth
                )
                paragraphSources.append((paragraph, frame))
            }
            let contentHeight = paragraphSources.reduce(CGFloat(0)) { $0 + $1.1.totalHeight }
                + margins.top + margins.bottom
            let authoredHeight = cell.header.cellProperty.map {
                HwpUnits.points(fromHwpUnitU: $0.height)
            } ?? 0

            placedCells.append(PlacedCell(
                row: placement.row,
                column: placement.column,
                rowSpan: placement.rowSpan,
                columnSpan: placement.columnSpan,
                contentHeight: contentHeight,
                authoredHeight: authoredHeight,
                cell: cell,
                paragraphSources: paragraphSources.map { ($0.0, $0.1) }
            ))
        }
        return placedCells
    }

    struct Placement {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
    }

    func placement(
        for cell: CoreHwp.HwpTableCell,
        rowCount: Int,
        columnCount: Int,
        occupied: inout Set<GridPosition>
    ) -> Placement? {
        var resolved: Placement?
        if let property = cell.header.cellProperty,
           Int(property.rowAddress) < rowCount,
           Int(property.columnAddress) < columnCount
        {
            resolved = Placement(
                row: Int(property.rowAddress),
                column: Int(property.columnAddress),
                rowSpan: min(Int(property.rowSpan), rowCount - Int(property.rowAddress)),
                columnSpan: min(Int(property.columnSpan), columnCount - Int(property.columnAddress))
            )
        } else {
            outer: for row in 0 ..< rowCount {
                for column in 0 ..< columnCount
                    where !occupied.contains(GridPosition(row: row, column: column))
                {
                    resolved = Placement(row: row, column: column, rowSpan: 1, columnSpan: 1)
                    break outer
                }
            }
        }
        guard let placement = resolved else { return nil }
        for row in placement.row ..< placement.row + placement.rowSpan {
            for column in placement.column ..< placement.column + placement.columnSpan {
                occupied.insert(GridPosition(row: row, column: column))
            }
        }
        return placement
    }

    /// 셀 고유 여백을 쓰는 셀은 셀 속성의 여백, 아니면 표 안쪽 여백.
    func cellMargins(
        for cell: CoreHwp.HwpTableCell,
        metrics: TableMetrics
    ) -> CellMargins {
        if cell.header.cellPropertyInfo.appliesInnerMargin,
           let property = cell.header.cellProperty,
           property.marginArray.count == 4
        {
            return CellMargins(
                left: max(0, HwpUnits.points(fromHwpUnit16: property.marginArray[0])),
                right: max(0, HwpUnits.points(fromHwpUnit16: property.marginArray[1])),
                top: max(0, HwpUnits.points(fromHwpUnit16: property.marginArray[2])),
                bottom: max(0, HwpUnits.points(fromHwpUnit16: property.marginArray[3]))
            )
        }
        return CellMargins(
            left: metrics.innerLeft,
            right: metrics.innerRight,
            top: metrics.innerTop,
            bottom: metrics.innerBottom
        )
    }

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
        let paragraphs = laidOutParagraphs(
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
            paragraphs: paragraphs,
            borders: borders(from: resolved),
            fillColor: fillColor(from: resolved)
        )
    }

    /// 셀 안 문단들을 셀 여백 안쪽에 위에서 아래로 쌓는다.
    func laidOutParagraphs(
        for cell: PlacedCell,
        in cellRect: CGRect,
        margins: CellMargins,
        index: HwpIndex
    ) -> [HwpLaidOutParagraph] {
        let textBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        var paragraphY = cellRect.minY + margins.top
        var paragraphs: [HwpLaidOutParagraph] = []
        for (paragraph, frame) in cell.paragraphSources {
            let rect = CGRect(
                x: cellRect.minX + margins.left,
                y: paragraphY,
                width: max(1, cellRect.width - margins.left - margins.right),
                height: frame.totalHeight
            )
            paragraphs.append(HwpLaidOutParagraph(
                attributedString: textBuilder.build(paragraph: paragraph),
                frame: frame,
                rect: rect,
                paragraphId: paragraph.paraHeader.paraId
            ))
            paragraphY += frame.totalHeight
        }
        return paragraphs
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
