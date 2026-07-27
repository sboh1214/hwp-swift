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

    /// 저작 셀/행 높이 상한 (pt). 미신뢰 UInt32 셀 높이가 수만 페이지를
    /// 만드는 것을 막는다 (#6). 실제 셀은 이 값의 수백분의 1이라 렌더 불변.
    static let maximumCellHeight: CGFloat = 200_000

    /// occupancy 격자 상한 (row×column). 미신뢰 rowCount/columnCount(각 UInt16)가
    /// 곱해지면 수십억 칸이 되어 OOM — 실제 문서 표는 이 한도를 한참 밑돈다.
    static let maximumGridCells = 1 << 20

    /// 표 하나가 만들 수 있는 페이지 세그먼트 상한. 본문 높이가 1pt로 몰린
    /// 병적 페이지에서 큰 행이 1pt씩 잘려 수십만 페이지가 나오는 것을 막는다
    /// (#5). 실제 표는 문서 페이지 수 이하라 이 한도를 한참 밑돈다.
    static let maximumTableSegments = 4096

    /// 표 하나를 레이아웃한다. 페이지 분할은 호출자(paginator)가 row 단위로 수행한다.
    /// 셀 안 중첩 표는 depth 3까지 재귀 레이아웃한다.
    public func layout(
        table: CoreHwp.HwpTable,
        availableWidth: CGFloat,
        index: HwpIndex,
        depth: Int = 0,
        sizeResolver: HwpObjectSizeResolver? = nil,
        clampToAvailableWidth: Bool = true
    ) -> Result<HwpTableFrame, HwpUnsupportedElement> {
        let property = table.tableProperty
        let rowCount = max(Int(property.rowCount), property.rowCellCounts.count)
        let columnCount = Int(property.columnCount)
        guard rowCount > 0, columnCount > 0 else {
            return .success(emptyFrame(availableWidth: availableWidth))
        }
        // 병적 격자 방어: occupancy Set이 수십억 칸으로 불어나 OOM되는 것을 막는다.
        guard rowCount * columnCount <= Self.maximumGridCells else {
            return .success(emptyFrame(availableWidth: availableWidth))
        }

        let outerWidth = resolvedOuterWidth(
            table: table, availableWidth: availableWidth, sizeResolver: sizeResolver,
            clampToAvailableWidth: clampToAvailableWidth
        )
        let metrics = TableMetrics(property: property)
        let context = LayoutContext(
            table: table, metrics: metrics, index: index, depth: depth, sizeResolver: sizeResolver
        )
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
        /// 상대 크기 기준 해석기 (paginator 페이지/단 기하) — 없으면 절대값 해석
        let sizeResolver: HwpObjectSizeResolver?
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

    /// 떠 있는 표 (글 앞/뒤로 — 흐름 밖 배치)는 저작 폭이 단 폭을 넘는 것이
    /// 정당하므로 clampToAvailableWidth = false로 클램프를 해제한다 (#3).
    func resolvedOuterWidth(
        table: CoreHwp.HwpTable,
        availableWidth: CGFloat,
        sizeResolver: HwpObjectSizeResolver?,
        clampToAvailableWidth: Bool = true
    ) -> CGFloat {
        let property = table.commonCtrlProperty
        let authored = HwpObjectSizeResolver.width(
            property.width, basis: property.propertyInfo.widthRelativeTo, resolver: sizeResolver
        )
        guard authored > 1 else { return availableWidth }
        return clampToAvailableWidth ? min(authored, availableWidth) : authored
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
        // fallback 자동 배치 커서 — 매 셀마다 (0,0)부터 재스캔하지 않게 (#4)
        var nextFallbackIndex = 0
        // 누적 occupancy 채우기 예산 (격자 크기) — 겹침 병적 입력 방어 (#14)
        var fillBudget = rowCount * columnCount

        for cell in context.table.cellArray {
            guard let placement = placement(
                for: cell,
                rowCount: rowCount,
                columnCount: columnCount,
                occupied: &occupied,
                nextFallbackIndex: &nextFallbackIndex,
                fillBudget: &fillBudget
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
        let spannedWidth = width(
            from: placement.column,
            span: placement.columnSpan,
            columnWidths: columnWidths,
            spacing: context.metrics.spacing
        )
        let margins = cellMargins(for: cell, metrics: context.metrics)
        let innerWidth = max(1, spannedWidth - margins.left - margins.right)
        // '문단' 기준 개체는 셀 안에서 셀 안폭을 기준으로 해석한다 (#2)
        let measurer = HwpParagraphMeasurer(
            index: context.index, fontResolver: fontResolver,
            sizeResolver: context.sizeResolver?.withParagraphWidth(innerWidth)
        )

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
                table: nested, availableWidth: innerWidth, index: context.index,
                depth: context.depth + 1,
                sizeResolver: context.sizeResolver?.withParagraphWidth(innerWidth)
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
        occupied: inout Set<GridPosition>,
        nextFallbackIndex: inout Int,
        fillBudget: inout Int
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
            // 이전 배치 다음 칸부터 이어서 첫 빈 칸을 찾는다 (매번 0부터 재스캔
            // 방지 — 점유는 단조 증가라 앞칸은 다시 비지 않는다, #4).
            let total = rowCount * columnCount
            var index = nextFallbackIndex
            while index < total {
                let position = GridPosition(row: index / columnCount, column: index % columnCount)
                if !occupied.contains(position) {
                    resolved = Placement(row: position.row, column: position.column, rowSpan: 1, columnSpan: 1)
                    break
                }
                index += 1
            }
            nextFallbackIndex = index + 1
        }
        guard let placement = resolved else { return nil }
        // 셀은 절대 거부하지 않는다 — 겹치는 셀도 원본처럼 모두 배치한다(렌더 불변).
        // 대신 누적 채우기 횟수를 격자 크기로 상한해, 같은 대영역을 겹쳐 채우는
        // 병적 입력이 occupancy 삽입을 수십억 번 반복하는 것을 막는다 (#14).
        fill: for row in placement.row ..< placement.row + placement.rowSpan {
            for column in placement.column ..< placement.column + placement.columnSpan {
                if fillBudget <= 0 {
                    break fill
                }
                occupied.insert(GridPosition(row: row, column: column))
                fillBudget -= 1
            }
        }
        return placement
    }

    /// 셀을 placement()과 동일한 규칙(명시 좌표 / fallback 커서 / 겹침 거부)으로
    /// 해석해 시작 행 → 셀 목록으로 묶는다. cellArray를 세그먼트마다 전수
    /// 스캔하지 않게 하고(#15), 좌표 없는 fallback 셀도 배치가 준 실제 행에
    /// 귀속시킨다(#23 — 예전엔 전부 행 0으로 취급). 각 셀에 원래 cellArray
    /// 인덱스를 실어, 소비 측이 인덱스로 재정렬해 문서 순서(=각주 번호 순서)를
    /// 정확히 복원한다 (행 우선 저장 가정에 의존하지 않음).
    static func cellRowIndex(
        for table: CoreHwp.HwpTable
    ) -> [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]] {
        let property = table.tableProperty
        let rowCount = max(Int(property.rowCount), property.rowCellCounts.count)
        let columnCount = Int(property.columnCount)
        guard rowCount > 0, columnCount > 0 else { return [:] }
        var occupied = Set<Int>()
        var nextFallbackIndex = 0
        var fillBudget = rowCount * columnCount
        var index: [Int: [(index: Int, cell: CoreHwp.HwpTableCell)]] = [:]
        for (cellIndex, cell) in table.cellArray.enumerated() {
            var row = 0
            var column = 0
            var rowSpan = 1
            var columnSpan = 1
            var placed = false
            if let cellProperty = cell.header.cellProperty,
               Int(cellProperty.rowAddress) < rowCount,
               Int(cellProperty.columnAddress) < columnCount
            {
                row = Int(cellProperty.rowAddress)
                column = Int(cellProperty.columnAddress)
                rowSpan = min(Int(cellProperty.rowSpan), rowCount - row)
                columnSpan = min(Int(cellProperty.columnSpan), columnCount - column)
                placed = true
            } else {
                var slot = nextFallbackIndex
                while slot < rowCount * columnCount {
                    if !occupied.contains(slot) {
                        row = slot / columnCount
                        column = slot % columnCount
                        placed = true
                        break
                    }
                    slot += 1
                }
                nextFallbackIndex = slot + 1
            }
            guard placed else { continue }
            // placement()과 동일: 셀을 거부하지 않고(겹쳐도 배치) 누적 채우기만
            // 격자 크기로 상한한다 (#14) — 렌더 배치와 각주 행 귀속을 일치시킨다.
            fillLoop: for spanRow in row ..< row + rowSpan {
                for spanColumn in column ..< column + columnSpan {
                    if fillBudget <= 0 {
                        break fillLoop
                    }
                    occupied.insert(spanRow * columnCount + spanColumn)
                    fillBudget -= 1
                }
            }
            index[row, default: []].append((cellIndex, cell))
        }
        return index
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
