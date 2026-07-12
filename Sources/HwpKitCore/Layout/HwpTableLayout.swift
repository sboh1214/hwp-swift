import CoreGraphics
import CoreHwp
import CoreText
import Foundation

public struct HwpTableLayout {
    let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    /// 재귀 중첩 표 레이아웃 깊이 상한 (바깥 표 = 0)
    static let maximumNestingDepth = 3

    /// 표 하나를 레이아웃한다. 페이지 분할은 호출자(paginator)가 row 단위로 수행한다.
    /// 셀 안 중첩 표는 depth 3까지 재귀 레이아웃한다.
    public func layout(
        table: CoreHwp.HwpTable,
        availableWidth: CGFloat,
        index: HwpIndex,
        depth: Int = 0
    ) -> Result<HwpTableFrame, HwpUnsupportedElement> {
        let property = table.tableProperty
        let rowCount = max(Int(property.rowCount), property.rowCellCounts.count)
        let columnCount = Int(property.columnCount)
        guard rowCount > 0, columnCount > 0 else {
            return .success(emptyFrame(availableWidth: availableWidth))
        }

        let outerWidth = resolvedOuterWidth(table: table, availableWidth: availableWidth)
        let metrics = TableMetrics(property: property)
        let context = LayoutContext(table: table, metrics: metrics, index: index, depth: depth)
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

extension HwpTableLayout {
    struct TableMetrics {
        let spacing: CGFloat
        let innerLeft: CGFloat
        let innerRight: CGFloat
        let innerTop: CGFloat
        let innerBottom: CGFloat

        var innerWidthAdjustment: CGFloat {
            innerLeft + innerRight
        }

        var innerHeightAdjustment: CGFloat {
            innerTop + innerBottom
        }

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
        /// 현재 표의 중첩 깊이 (바깥 표 = 0)
        let depth: Int
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

    /// 셀 안 문단 하나의 레이아웃 결과 (문단 텍스트 + 그 문단에 붙은 중첩 표)
    struct PlacedCellContent {
        let paragraph: CoreHwp.HwpParagraph
        let frame: HwpParagraphFrame
        let nestedTables: [(instanceId: UInt32, frame: HwpTableFrame)]

        var totalHeight: CGFloat {
            frame.totalHeight + nestedTables.reduce(CGFloat(0)) {
                $0 + $1.frame.outerFrame.height
            }
        }
    }

    struct PlacedCell {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let contentHeight: CGFloat
        let authoredHeight: CGFloat
        /// 셀 문단 전부가 라인 캐시 높이로 측정되었는지 — 참이면 저작된 셀
        /// 높이 (표 80 = 한글 계산값)를 그대로 신뢰한다 (헌법주석 실측:
        /// 캐시 합 + 여백이 저작 높이를 넘겨 표가 부풀면 페이지가 밀린다)
        let hasCachedContent: Bool
        let cell: CoreHwp.HwpTableCell
        let contents: [PlacedCellContent]
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
        var placedCells: [PlacedCell] = []
        var occupied = Set<GridPosition>()

        for cell in context.table.cellArray {
            guard let placement = placement(
                for: cell,
                rowCount: rowCount,
                columnCount: columnCount,
                occupied: &occupied
            ) else { continue }
            placedCells.append(placedCell(
                for: cell,
                at: placement,
                context: context,
                columnWidths: columnWidths
            ))
        }
        return placedCells
    }

    /// 셀 하나의 문단/중첩 표 콘텐츠를 레이아웃해 PlacedCell로 만든다.
    func placedCell(
        for cell: CoreHwp.HwpTableCell,
        at placement: Placement,
        context: LayoutContext,
        columnWidths: [CGFloat]
    ) -> PlacedCell {
        let measurer = HwpParagraphMeasurer(index: context.index, fontResolver: fontResolver)
        let spannedWidth = width(
            from: placement.column,
            span: placement.columnSpan,
            columnWidths: columnWidths,
            spacing: context.metrics.spacing
        )
        let margins = cellMargins(for: cell, metrics: context.metrics)
        let innerWidth = max(1, spannedWidth - margins.left - margins.right)

        let measured = measuredCellContents(
            of: cell,
            innerWidth: innerWidth,
            measurer: measurer,
            context: context
        )
        let contents = measured.contents
        let contentHeight = contents.reduce(CGFloat(0)) { $0 + $1.totalHeight }
            + margins.top + margins.bottom
        let authoredHeight = cell.header.cellProperty.map {
            HwpUnits.points(fromHwpUnitU: $0.height)
        } ?? 0

        return PlacedCell(
            row: placement.row,
            column: placement.column,
            rowSpan: placement.rowSpan,
            columnSpan: placement.columnSpan,
            contentHeight: contentHeight,
            authoredHeight: authoredHeight,
            hasCachedContent: measured.allCached,
            cell: cell,
            contents: contents
        )
    }

    /// 셀 문단들을 측정한다. 셀 높이는 한글 라인 캐시를 우선한다 (각주와 동일
    /// 철학) — 폰트 대체로 CT 줄 수가 부풀어 row가 한글보다 커지는 것을 막는다.
    private func measuredCellContents(
        of cell: CoreHwp.HwpTableCell,
        innerWidth: CGFloat,
        measurer: HwpParagraphMeasurer,
        context: LayoutContext
    ) -> (contents: [PlacedCellContent], allCached: Bool) {
        var contents: [PlacedCellContent] = []
        var allCached = !cell.paragraphArray.isEmpty
        for paragraph in cell.paragraphArray {
            // 문단 위 간격 절반: CT는 프레임 첫 문단에 paragraphSpacingBefore를
            // 적용하지 않으므로 (셀은 문단별 개별 조판) 항상 직접 더한다.
            // 렌더 배치에서 같은 값만큼 문단 상단을 내린다 (noori 부제 실물)
            let measured = measurer.measure(
                paragraph,
                width: innerWidth,
                options: .init(preferCachedHeight: true, addHalfSpacingBefore: true)
            )
            if !measured.usedCachedHeight {
                allCached = false
            }
            contents.append(PlacedCellContent(
                paragraph: paragraph,
                frame: measured.frame,
                nestedTables: nestedTableFrames(
                    in: paragraph,
                    innerWidth: innerWidth,
                    context: context
                )
            ))
        }
        return (contents, allCached)
    }

    /// 셀 문단에 붙은 중첩 표들을 재귀 레이아웃한다 (깊이 상한 초과분은 생략).
    func nestedTableFrames(
        in paragraph: CoreHwp.HwpParagraph,
        innerWidth: CGFloat,
        context: LayoutContext
    ) -> [(instanceId: UInt32, frame: HwpTableFrame)] {
        guard context.depth < Self.maximumNestingDepth,
              let ctrls = paragraph.ctrlHeaderArray
        else { return [] }
        return ctrls.compactMap { ctrl in
            guard case let .table(nested) = ctrl else { return nil }
            guard case let .success(frame) = layout(
                table: nested,
                availableWidth: innerWidth,
                index: context.index,
                depth: context.depth + 1
            ) else { return nil }
            return (nested.commonCtrlProperty.instanceId, frame)
        }
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
}
