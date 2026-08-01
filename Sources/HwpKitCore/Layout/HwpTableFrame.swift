import CoreGraphics
import CoreHwp
import Foundation

/// 셀 4방향 테두리 (pt 폭 + 색상). 폭 0이면 해당 변은 그리지 않는다.
public struct HwpBorderSet: Sendable, Hashable {
    public let top, bottom, left, right: CGFloat
    public let topColor, bottomColor, leftColor, rightColor: HwpRGBColor
    /// 이중선 여부 (표 25 종류 8-10) — 가는 선 2개로 그린다
    public let topDouble, bottomDouble, leftDouble, rightDouble: Bool

    public init(
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat,
        topColor: HwpRGBColor,
        bottomColor: HwpRGBColor,
        leftColor: HwpRGBColor,
        rightColor: HwpRGBColor,
        topDouble: Bool = false,
        bottomDouble: Bool = false,
        leftDouble: Bool = false,
        rightDouble: Bool = false
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.leftColor = leftColor
        self.rightColor = rightColor
        self.topDouble = topDouble
        self.bottomDouble = bottomDouble
        self.leftDouble = leftDouble
        self.rightDouble = rightDouble
    }

    /// rect 둘레에 **실제로 칠하는 띠 전부** (색 포함) — 페인터
    /// (`HwpPaintListBuilder.borderCommands`) 와 히트 (`HwpTableCellFrame.paints`)
    /// 가 이 하나를 공유한다 (R56).
    ///
    /// 이중선의 **둘째 줄은 원래 폭 띠 밖으로 나간다** (안쪽으로 thin + gap).
    /// 두 곳이 따로 계산하면 보이는 선과 눌리는 선이 갈린다.
    func stripes(around rect: CGRect) -> [(rect: CGRect, color: HwpRGBColor)] {
        Self.edgeStripes(
            edgeRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: top),
            width: top, isDouble: topDouble, horizontal: true, leading: true
        ).map { ($0, topColor) }
            + Self.edgeStripes(
                edgeRect: CGRect(
                    x: rect.minX, y: rect.maxY - bottom, width: rect.width, height: bottom
                ),
                width: bottom, isDouble: bottomDouble, horizontal: true, leading: false
            ).map { ($0, bottomColor) }
            + Self.edgeStripes(
                edgeRect: CGRect(x: rect.minX, y: rect.minY, width: left, height: rect.height),
                width: left, isDouble: leftDouble, horizontal: false, leading: true
            ).map { ($0, leftColor) }
            + Self.edgeStripes(
                edgeRect: CGRect(
                    x: rect.maxX - right, y: rect.minY, width: right, height: rect.height
                ),
                width: right, isDouble: rightDouble, horizontal: false, leading: false
            ).map { ($0, rightColor) }
    }

    /// 한 변의 띠 — 이중선이면 가는 선 둘, 아니면 변 띠 그대로. 폭 0이면 없음.
    ///
    /// 이중선 (표 25 종류 8-10) 은 가는 선 2개 + 사이 간격 (noori 제목 상자 실물
    /// — 1px 두 줄). 상단·좌측 (leading) 은 둘째 선을 양 (안쪽) 으로, 하단·우측
    /// (trailing) 은 far edge에서 음 (안쪽) 으로 민다 — trailing을 양으로 밀면
    /// maxY/maxX를 넘어 인접 셀·표 밖을 침범한다 (R42 #2).
    private static func edgeStripes(
        edgeRect: CGRect, width: CGFloat, isDouble: Bool, horizontal: Bool, leading: Bool
    ) -> [CGRect] {
        guard width > 0 else { return [] }
        guard isDouble else { return [edgeRect] }
        let thin = max(0.4, width * 0.4)
        let gap = max(thin, width)
        var first = edgeRect
        var second = edgeRect
        if horizontal {
            first.size.height = thin
            second.size.height = thin
            if leading {
                second.origin.y = edgeRect.minY + thin + gap
            } else {
                first.origin.y = edgeRect.maxY - thin
                second.origin.y = edgeRect.maxY - 2 * thin - gap
            }
        } else {
            first.size.width = thin
            second.size.width = thin
            if leading {
                second.origin.x = edgeRect.minX + thin + gap
            } else {
                first.origin.x = edgeRect.maxX - thin
                second.origin.x = edgeRect.maxX - 2 * thin - gap
            }
        }
        return [first, second]
    }

    public static func uniform(width: CGFloat, color: HwpRGBColor) -> HwpBorderSet {
        HwpBorderSet(
            top: width,
            bottom: width,
            left: width,
            right: width,
            topColor: color,
            bottomColor: color,
            leftColor: color,
            rightColor: color
        )
    }
}

public struct HwpTableCellFrame: @unchecked Sendable, Hashable {
    /// 표-로컬 좌표계 (origin 0,0 top-left, y-down)의 셀 영역
    public let cellFrame: CGRect
    /// grid 상 위치 (편집/히트테스트용 모델 참조)
    public let row: Int
    public let column: Int
    public let rowSpan: Int
    public let columnSpan: Int
    /// 셀 안 문단 (텍스트 + 지오메트리 + paraId)
    public let paragraphs: [HwpLaidOutParagraph]
    public let borders: HwpBorderSet
    public let fillColor: HwpRGBColor?
    /// 셀 안 중첩 표 (문단 뒤에 쌓인다)
    public let nestedTables: [HwpNestedTableFrame]
    /// 셀 안 그림 (문단 줄 위치에 배치)
    public let images: [HwpCellImage]
    /// 셀 안 도형 (문단 줄 위치에 배치, R29 #1)
    public let shapes: [HwpCellShape]
    /// 셀 안 글상자 (문단 줄 위치에 배치, R29 #1)
    public let textboxes: [HwpCellTextbox]

    public init(
        cellFrame: CGRect,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int,
        paragraphs: [HwpLaidOutParagraph],
        borders: HwpBorderSet,
        fillColor: HwpRGBColor?,
        nestedTables: [HwpNestedTableFrame] = [],
        images: [HwpCellImage] = [],
        shapes: [HwpCellShape] = [],
        textboxes: [HwpCellTextbox] = []
    ) {
        self.cellFrame = cellFrame
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.paragraphs = paragraphs
        self.borders = borders
        self.fillColor = fillColor
        self.nestedTables = nestedTables
        self.images = images
        self.shapes = shapes
        self.textboxes = textboxes
    }

    /// 이 지점에 셀이 **칠했는가** — 채움 ∪ 테두리 4띠 (표-로컬 좌표).
    ///
    /// 안 채운 셀도 칸막이는 그리므로 그 선 위의 탭은 이 셀을 가리킨다 (R55).
    /// 띠 산식은 페인터 (`HwpPaintListBuilder.borderCommands`) 와 **같아야** 한다 —
    /// 갈리면 보이는 선 위의 탭이 아래 블록으로 새거나 그 반대가 된다.
    public func paints(_ point: CGPoint) -> Bool {
        if fillColor != nil, cellFrame.contains(point) {
            return true
        }
        return borderRects.contains { $0.contains(point) }
    }

    /// 페인터가 실제로 칠하는 테두리 띠 (이중선의 둘째 줄 포함)
    private var borderRects: [CGRect] {
        borders.stripes(around: cellFrame).map(\.rect)
    }

    /// 분할 **전에** 감싼 링크를 개체에 고정한 사본 (R58).
    ///
    /// `HwpTableSplitter.splitCell`은 문단과 개체를 각자 다른 규칙으로 조각에
    /// 배정한다 — 그림은 절단면에 걸치면 **양쪽에 복사**되고, 도형·글상자는 midY로,
    /// 중첩 표는 minY로 간다. U+FFFC run이 남지 않은 조각에서는 (문단, 서수) 조회가
    /// 실패하므로 짝이 온전한 지금 해석해 실어 보낸다. 이미 고정된 값은 덮지
    /// 않는다 — 여러 페이지에 걸친 표는 조각이 **다시** 쪼개진다.
    public func resolvingWrapperURLs() -> HwpTableCellFrame {
        func resolved(_ paragraphId: UInt32, _ controlIndex: Int) -> String? {
            HwpDrawnTextLayout.wrapperHyperlinkURL(
                in: paragraphs, paragraphId: paragraphId, controlIndex: controlIndex
            )
        }
        return HwpTableCellFrame(
            cellFrame: cellFrame,
            row: row,
            column: column,
            rowSpan: rowSpan,
            columnSpan: columnSpan,
            paragraphs: paragraphs,
            borders: borders,
            fillColor: fillColor,
            nestedTables: nestedTables.map {
                $0.withWrapperURL($0.wrapperURL ?? resolved($0.paragraphId, $0.controlIndex))
            },
            images: images.map {
                $0.withWrapperURL($0.wrapperURL ?? resolved($0.paragraphId, $0.controlIndex))
            },
            shapes: shapes.map {
                $0.withWrapperURL($0.wrapperURL ?? resolved($0.paragraphId, $0.controlIndex))
            },
            textboxes: textboxes.map {
                $0.withWrapperURL($0.wrapperURL ?? resolved($0.paragraphId, $0.controlIndex))
            }
        )
    }

    /// 셀과 모든 콘텐츠 지오메트리를 deltaY만큼 이동한 사본 (분할 세그먼트 이동).
    /// 새 콘텐츠 종류가 누락되지 않게 이동 산식은 여기 한 곳에만 둔다.
    public func offsetBy(deltaY: CGFloat) -> HwpTableCellFrame {
        HwpTableCellFrame(
            cellFrame: cellFrame.offsetBy(dx: 0, dy: deltaY),
            row: row,
            column: column,
            rowSpan: rowSpan,
            columnSpan: columnSpan,
            paragraphs: paragraphs.map { paragraph in
                HwpLaidOutParagraph(
                    attributedString: paragraph.attributedString,
                    frame: paragraph.frame,
                    rect: paragraph.rect.offsetBy(dx: 0, dy: deltaY),
                    paragraphId: paragraph.paragraphId,
                    hyperlinkURL: paragraph.hyperlinkURL
                )
            },
            borders: borders,
            fillColor: fillColor,
            nestedTables: nestedTables.map {
                $0.withRect($0.rect.offsetBy(dx: 0, dy: deltaY))
            },
            images: images.map { $0.offsetBy(deltaX: 0, deltaY: deltaY) },
            shapes: shapes.map { $0.withRect($0.rect.offsetBy(dx: 0, dy: deltaY)) },
            textboxes: textboxes.map { $0.withRect($0.rect.offsetBy(dx: 0, dy: deltaY)) }
        )
    }
}

public struct HwpTableRowFrame: @unchecked Sendable, Hashable {
    public let rowFrame: CGRect
    public let cells: [HwpTableCellFrame]

    public init(rowFrame: CGRect, cells: [HwpTableCellFrame]) {
        self.rowFrame = rowFrame
        self.cells = cells
    }
}

public struct HwpTableFrame: @unchecked Sendable, Hashable {
    /// 표-로컬 좌표계의 전체 영역 (origin 0,0)
    public let outerFrame: CGRect
    public let rows: [HwpTableRowFrame]
    public let borderColor: HwpRGBColor
    public let borderWidth: CGFloat

    public init(
        outerFrame: CGRect,
        rows: [HwpTableRowFrame],
        borderColor: HwpRGBColor,
        borderWidth: CGFloat
    ) {
        self.outerFrame = outerFrame
        self.rows = rows
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

// MARK: - borderFill 참조 해석

extension HwpTableLayout {
    /// borderFill 참조는 1-based (0 = 없음) 관례를 따르되, 관례 밖 파일을 위해 원래 id도 시도한다.
    func resolvedBorderFill(id: UInt16, index: HwpIndex) -> CoreHwp.HwpBorderFill? {
        guard id > 0 else { return nil }
        return index.borderFill(id: UInt32(id) - 1) ?? index.borderFill(id: UInt32(id))
    }

    func borders(from borderFill: CoreHwp.HwpBorderFill?) -> HwpBorderSet {
        guard let borderFill, borderFill.borderLineArray.count == 4 else {
            return .uniform(width: 0.5, color: HwpRGBColor(red: 0, green: 0, blue: 0))
        }
        // 4방향 순서: 왼쪽/오른쪽/위쪽/아래쪽 (표 23)
        let lines = borderFill.borderLineArray
        func width(_ line: CoreHwp.HwpBorderLine) -> CGFloat {
            // 선 종류가 없으면 (표 25 type 0 = 선 없음) 굵기와 무관하게 안 그린다
            // (CCL 한글.app 실측: 셀 테두리 none인데 굵기 값은 남아 있다)
            guard line.type != CoreHwp.HwpBorderType.none else { return 0 }
            return CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: line.thickness))
        }
        func color(_ line: CoreHwp.HwpBorderLine) -> HwpRGBColor {
            HwpRGBColor(line.color)
        }
        func isDouble(_ line: CoreHwp.HwpBorderLine) -> Bool {
            switch line.type {
            case .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine:
                true
            default:
                false
            }
        }
        return HwpBorderSet(
            top: width(lines[2]),
            bottom: width(lines[3]),
            left: width(lines[0]),
            right: width(lines[1]),
            topColor: color(lines[2]),
            bottomColor: color(lines[3]),
            leftColor: color(lines[0]),
            rightColor: color(lines[1]),
            topDouble: isDouble(lines[2]),
            bottomDouble: isDouble(lines[3]),
            leftDouble: isDouble(lines[0]),
            rightDouble: isDouble(lines[1])
        )
    }

    func fillColor(from borderFill: CoreHwp.HwpBorderFill?) -> HwpRGBColor? {
        guard let fill = borderFill?.fill, fill.hasSolidFill,
              let background = fill.solidBackgroundColor
        else { return nil }
        return HwpRGBColor(background)
    }

    func outerBorderColor(table: CoreHwp.HwpTable, index: HwpIndex) -> HwpRGBColor {
        let resolved = resolvedBorderFill(id: table.tableProperty.borderFillId, index: index)
        guard let line = resolved?.borderLineArray.first else {
            return HwpRGBColor(red: 0, green: 0, blue: 0)
        }
        return HwpRGBColor(line.color)
    }
}

public extension HwpTableFrame {
    /// 표가 이 지점에 칠했는가 (표-로컬 좌표) — 셀 채움·테두리 ∪ 중첩 표 재귀.
    /// `tableHit`의 순회와 같은 분해라 히트 결과와 갈리지 않는다 (R55).
    func paints(_ point: CGPoint) -> Bool {
        rows.contains { row in
            row.cells.contains { cell in
                cell.paints(point) || cell.nestedTables.contains { nested in
                    nested.table.paints(CGPoint(
                        x: point.x - nested.rect.minX, y: point.y - nested.rect.minY
                    ))
                }
            }
        }
    }
}

public extension HwpRGBColor {
    init(_ color: CoreHwp.HwpColor) {
        self.init(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255
        )
    }
}
