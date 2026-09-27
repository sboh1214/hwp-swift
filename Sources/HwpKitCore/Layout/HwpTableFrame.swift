import CoreGraphics
import CoreHwp
import Foundation

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
    /// 이웃 칸과 이은 대시·원형 점선 변의 자리 (#238) — 셀 혼자로는 알 수 없어 표가 셀 배치에서
    /// 셈해 싣는다 (`HwpTableFrame.init`, `HwpBorderChaining`). 기본은 이음 없음.
    var borderChains: HwpBorderChains = .none

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
    /// 갈리면 보이는 선 위의 탭이 아래 블록으로 새거나 그 반대가 된다. 점선·물결의
    /// 빈 자리도 띠로 친다 (한글도 선 위 탭은 셀을 가리킨다).
    public func paints(_ point: CGPoint) -> Bool {
        if fillColor != nil, cellFrame.contains(point) {
            return true
        }
        return borderRects.contains { $0.contains(point) }
    }

    /// 페인터가 실제로 칠하는 테두리 띠 (모서리 중심, 연장 포함, 이은 변은 제 몫) — 경로 없이
    /// 띠만 만든다
    private var borderRects: [CGRect] {
        borders.bands(around: cellFrame, chains: borderChains)
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
        let copy = HwpTableCellFrame(
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
        return copy.withBorderChains(borderChains)
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
                    hyperlinkURL: paragraph.hyperlinkURL,
                    heightIsMeasured: paragraph.heightIsMeasured
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
        // 이음 자리는 칸 모서리 기준이라 옮겨도 그대로다
        .withBorderChains(borderChains)
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

    /// 셀 테두리의 대시·원형 점선은 이 표의 셀 배치로 이웃 칸과 잇는다 (#238) — `rows`의 칸이
    /// 싣고 온 이음 자리는 버리고 새로 셈한다 (쪽 조각·옮겨 온 칸도 이 표 기준이 된다).
    public init(
        outerFrame: CGRect,
        rows: [HwpTableRowFrame],
        borderColor: HwpRGBColor,
        borderWidth: CGFloat
    ) {
        self.outerFrame = outerFrame
        self.rows = HwpBorderChaining.chained(rows)
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
        return HwpBorderSet(
            top: width(lines[2]),
            bottom: width(lines[3]),
            left: width(lines[0]),
            right: width(lines[1]),
            topColor: color(lines[2]),
            bottomColor: color(lines[3]),
            leftColor: color(lines[0]),
            rightColor: color(lines[1]),
            topShape: lines[2].type ?? .line,
            bottomShape: lines[3].type ?? .line,
            leftShape: lines[0].type ?? .line,
            rightShape: lines[1].type ?? .line
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

extension HwpTableCellFrame {
    /// `paints` ∪ 이 셀 안 중첩 표의 칠(재귀) — `tableGridPosition`용 모듈 안 헬퍼 (PR 리뷰)
    func paintsIncludingNestedTables(_ point: CGPoint) -> Bool {
        paints(point) || nestedTables.contains {
            $0.table.paints(CGPoint(x: point.x - $0.rect.minX, y: point.y - $0.rect.minY))
        }
    }
}

public extension HwpTableFrame {
    /// 표가 이 지점에 칠했는가 (표-로컬 좌표) — 셀 채움·테두리 ∪ 중첩 표 재귀.
    /// `tableHit`의 순회와 같은 분해라 히트 결과와 갈리지 않는다 (R55).
    func paints(_ point: CGPoint) -> Bool {
        rows.contains { $0.cells.contains { $0.paintsIncludingNestedTables(point) } }
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

public extension HwpTableCellFrame {
    /// 셀이 하이퍼링크를 품는지 (문단·개체·글상자·중첩 표 재귀, R61)
    var hasHyperlink: Bool {
        paragraphs.contains { $0.hasHyperlink }
            || images.contains { $0.wrapperURL != nil }
            || shapes.contains { $0.wrapperURL != nil }
            || textboxes.contains { $0.wrapperURL != nil || $0.textbox.hasHyperlink }
            || nestedTables.contains { $0.wrapperURL != nil || $0.table.hasHyperlink }
    }
}

public extension HwpTableFrame {
    /// 표가 하이퍼링크를 품는지 (셀 재귀, R61)
    var hasHyperlink: Bool {
        rows.contains { $0.cells.contains { $0.hasHyperlink } }
    }
}
