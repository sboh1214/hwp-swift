import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation

public struct HwpBorderSet: Sendable, Hashable {
    public let top, bottom, left, right: CGFloat
    public let color: CGColor
}

public struct HwpTableCellFrame: Sendable, Hashable {
    public let cellFrame: CGRect
    public let paragraphFrames: [HwpParagraphFrame]
    public let borders: HwpBorderSet
    public let fillColor: CGColor?
}

public struct HwpTableRowFrame: Sendable, Hashable {
    public let rowFrame: CGRect
    public let cells: [HwpTableCellFrame]
}

public struct HwpTableFrame: Sendable, Hashable {
    public let outerFrame: CGRect
    public let rows: [HwpTableRowFrame]
    public let borderColor: CGColor
    public let borderWidth: CGFloat
}

public struct HwpTableLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public func layout(
        table: CoreHwp.HwpTable,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        index: HwpIndex
    ) -> Result<HwpTableFrame, HwpUnsupportedElement> {
        if containsNestedTable(table) {
            return .failure(HwpUnsupportedElement(kind: .placeholder, page: 0, hint: "표: 중첩 표"))
        }

        let rowCount = max(Int(table.tableProperty.rowCount), Int(table.tableProperty.rowSize.count / 2))
        let columnCount = Int(table.tableProperty.columnCount)
        guard rowCount > 0, columnCount > 0 else {
            return .success(emptyFrame(availableWidth: availableWidth))
        }

        let spacing = max(0, HwpUnits.points(fromHwpUnit16: table.tableProperty.cellSpacing))
        let columnWidths = Self.columnWidths(
            count: columnCount,
            availableWidth: availableWidth,
            spacing: spacing
        )
        let innerWidthAdjustment = HwpUnits.points(fromHwpUnit16: table.tableProperty.leftInnerMargin)
            + HwpUnits.points(fromHwpUnit16: table.tableProperty.rightInnerMargin)
        let innerHeightAdjustment = HwpUnits.points(fromHwpUnit16: table.tableProperty.topInnerMargin)
            + HwpUnits.points(fromHwpUnit16: table.tableProperty.bottomInnerMargin)

        let textBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout(fontResolver: fontResolver)
        var rowHeights = Array(repeating: CGFloat(0), count: rowCount)
        var placedCells: [PlacedCell] = []
        var occupied = Set<GridPosition>()

        for cell in table.cellArray {
            guard let placement = placement(
                for: cell,
                rowCount: rowCount,
                columnCount: columnCount,
                occupied: occupied
            ) else { continue }

            let columnSpan = min(placement.columnSpan, columnCount - placement.column)
            let rowSpan = min(placement.rowSpan, rowCount - placement.row)
            let spannedWidth = width(
                from: placement.column,
                span: columnSpan,
                columnWidths: columnWidths,
                spacing: spacing
            )
            let innerWidth = max(1, spannedWidth - innerWidthAdjustment)
            let paragraphFrames = cell.paragraphArray.compactMap { paragraph -> HwpParagraphFrame? in
                guard let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId)) else {
                    return nil
                }
                return paragraphLayout.layout(
                    attributedString: textBuilder.build(paragraph: paragraph),
                    paraShape: paraShape,
                    columnWidth: innerWidth
                )
            }
            let contentHeight = paragraphFrames.reduce(CGFloat(0)) { $0 + $1.totalHeight } + innerHeightAdjustment
            rowHeights[placement.row] = max(rowHeights[placement.row], contentHeight)
            placedCells.append(
                PlacedCell(
                    row: placement.row,
                    column: placement.column,
                    rowSpan: rowSpan,
                    columnSpan: columnSpan,
                    paragraphFrames: paragraphFrames
                )
            )
            markOccupied(
                row: placement.row,
                column: placement.column,
                rowSpan: rowSpan,
                columnSpan: columnSpan,
                in: &occupied
            )
        }

        let defaultRowHeight = max(1, innerHeightAdjustment)
        rowHeights = rowHeights.map { $0 > 0 ? $0 : defaultRowHeight }
        let totalHeight = rowHeights.reduce(CGFloat(0), +) + spacing * CGFloat(rowCount + 1)
        guard totalHeight <= availableHeight else {
            return .failure(HwpUnsupportedElement(kind: .placeholder, page: 0, hint: "표: 다중 페이지"))
        }

        return .success(
            HwpTableFrame(
                outerFrame: CGRect(x: 0, y: 0, width: availableWidth, height: totalHeight),
                rows: rows(
                    placedCells: placedCells,
                    rowHeights: rowHeights,
                    columnWidths: columnWidths,
                    spacing: spacing
                ),
                borderColor: Self.defaultBorderColor,
                borderWidth: 1
            )
        )
    }
}

private extension HwpTableLayout {
    struct GridPosition: Hashable {
        let row: Int
        let column: Int
    }

    struct CellPlacement: Hashable {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
    }

    struct PlacedCell: Hashable {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let paragraphFrames: [HwpParagraphFrame]
    }

    static let defaultBorderColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

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
            borderColor: Self.defaultBorderColor,
            borderWidth: 1
        )
    }

    static func columnWidths(count: Int, availableWidth: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let totalSpacing = spacing * CGFloat(count + 1)
        let width = max(1, (availableWidth - totalSpacing) / CGFloat(count))
        return Array(repeating: width, count: count)
    }

    func placement(
        for cell: CoreHwp.HwpTableCell,
        rowCount: Int,
        columnCount: Int,
        occupied: Set<GridPosition>
    ) -> CellPlacement? {
        if let decoded = decodePlacement(from: cell.header.rawTrailing),
           decoded.row < rowCount,
           decoded.column < columnCount
        {
            return decoded
        }

        for row in 0 ..< rowCount {
            for column in 0 ..< columnCount where !occupied.contains(GridPosition(row: row, column: column)) {
                return CellPlacement(row: row, column: column, rowSpan: 1, columnSpan: 1)
            }
        }
        return nil
    }

    func decodePlacement(from data: Data) -> CellPlacement? {
        guard data.count >= 8 else { return nil }
        let column = Int(uint16(at: 0, in: data))
        let row = Int(uint16(at: 2, in: data))
        let columnSpan = max(1, Int(uint16(at: 4, in: data)))
        let rowSpan = max(1, Int(uint16(at: 6, in: data)))
        return CellPlacement(row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan)
    }

    func uint16(at offset: Int, in data: Data) -> UInt16 {
        let lower = UInt16(data[data.index(data.startIndex, offsetBy: offset)])
        let upper = UInt16(data[data.index(data.startIndex, offsetBy: offset + 1)])
        return lower | (upper << 8)
    }

    func width(from column: Int, span: Int, columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let last = min(column + span, columnWidths.count)
        let widths = columnWidths[column ..< last].reduce(CGFloat(0), +)
        return widths + spacing * CGFloat(max(0, span - 1))
    }

    func markOccupied(
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int,
        in occupied: inout Set<GridPosition>
    ) {
        for rowIdx in row ..< row + rowSpan {
            for colIdx in column ..< column + columnSpan {
                occupied.insert(GridPosition(row: rowIdx, column: colIdx))
            }
        }
    }

    func rows(
        placedCells: [PlacedCell],
        rowHeights: [CGFloat],
        columnWidths: [CGFloat],
        spacing: CGFloat
    ) -> [HwpTableRowFrame] {
        var result: [HwpTableRowFrame] = []
        result.reserveCapacity(rowHeights.count)
        var yOffset = spacing

        for row in rowHeights.indices {
            let rowFrame = CGRect(
                x: 0,
                y: yOffset,
                width: rowWidth(columnWidths: columnWidths, spacing: spacing),
                height: rowHeights[row]
            )
            let cells = placedCells
                .filter { $0.row == row }
                .sorted { $0.column < $1.column }
                .map { cell in
                    HwpTableCellFrame(
                        cellFrame: CGRect(
                            x: xOffset(for: cell.column, columnWidths: columnWidths, spacing: spacing),
                            y: yOffset,
                            width: width(
                                from: cell.column,
                                span: cell.columnSpan,
                                columnWidths: columnWidths,
                                spacing: spacing
                            ),
                            height: height(from: cell.row, span: cell.rowSpan, rowHeights: rowHeights, spacing: spacing)
                        ),
                        paragraphFrames: cell.paragraphFrames,
                        borders: HwpBorderSet(top: 1, bottom: 1, left: 1, right: 1, color: Self.defaultBorderColor),
                        fillColor: nil
                    )
                }
            result.append(HwpTableRowFrame(rowFrame: rowFrame, cells: cells))
            yOffset += rowHeights[row] + spacing
        }

        return result
    }

    func rowWidth(columnWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        columnWidths.reduce(CGFloat(0), +) + spacing * CGFloat(columnWidths.count + 1)
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
