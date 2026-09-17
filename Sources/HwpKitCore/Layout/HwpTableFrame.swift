import CoreGraphics
import CoreHwp
import Foundation

/// 셀 4방향 테두리 (pt 폭 + 색상 + 선 모양). 폭 0이거나 모양이 `none`이면 해당 변은 그리지
/// 않는다.
///
/// 선은 한글처럼 **셀 모서리에 중심**을 두고 양쪽으로 폭의 절반씩 걸친다 (한글 12.30 실측,
/// #191: 0.1~5mm 16단 모두 위 테두리 중심이 셀 위 모서리, 왼 테두리 중심이 왼 모서리) —
/// 이웃 셀과 공유하는 모서리는 양쪽 셀이 각자 자기 선을 겹쳐 그린다 (한글도 그렇다: 2중선
/// 아래 변 + 가는+굵은 위 변이 한 모서리에 둘 다 남는다). 가로 변은 그 끝에 세로 변이
/// 있으면 세로 변 폭의 절반만큼 밖으로 연장해 모서리를 메우고 (실측: 왼 테두리가 있는 왼쪽
/// 끝은 −t/2, 오른 테두리가 없는 오른쪽 끝은 모서리 그대로), 세로 변의 실선·대시·원형은
/// 연장하지 않는다 (가로 변이 이미 모서리를 메운다). 여러 줄(2중선·3중선)은 부속선마다
/// 바깥쪽에서의 거리만큼 안쪽으로 물러나 모서리에서 겹상자를 이루고 (실측: 1mm 2중선 위
/// 변의 바깥 선은 −t/2에서, 안쪽 선은 +t/4에서 시작; 물러나는 거리의 기준은 **이웃 변**의
/// 폭 절반), 물결·2중 물결은 세로 변도 가로 변 폭의 절반만큼 연장한 곳에서 시작한다 (실측:
/// 위 테두리가 있는 왼 물결 변의 첫 꼭짓점은 모서리 − t/2).
public struct HwpBorderSet: Sendable, Hashable {
    public let top, bottom, left, right: CGFloat
    public let topColor, bottomColor, leftColor, rightColor: HwpRGBColor
    /// 선 모양 (표 25) — 점선·파선·여러 줄·물결은 `HwpLineShapeGeometry`가 두께 축척으로
    /// 그린다 (#191). `none`은 폭과 무관하게 그리지 않는다.
    public let topShape, bottomShape, leftShape, rightShape: HwpBorderType

    public init(
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat,
        topColor: HwpRGBColor,
        bottomColor: HwpRGBColor,
        leftColor: HwpRGBColor,
        rightColor: HwpRGBColor,
        topShape: HwpBorderType = .line,
        bottomShape: HwpBorderType = .line,
        leftShape: HwpBorderType = .line,
        rightShape: HwpBorderType = .line
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.leftColor = leftColor
        self.rightColor = rightColor
        self.topShape = topShape
        self.bottomShape = bottomShape
        self.leftShape = leftShape
        self.rightShape = rightShape
    }

    /// 한 변의 그리기 — 페이지 좌표 채우기 경로 + 색 + 히트용 띠
    public struct EdgeGeometry: @unchecked Sendable {
        public let path: CGPath
        public let color: HwpRGBColor
        /// 이 변이 칠하는 영역의 경계 상자 (모서리에 중심을 둔 띠, 연장·물결 넘침 포함)
        public let band: CGRect
    }

    /// rect 둘레에 **실제로 칠하는 변 전부** — 페인터 (`HwpPaintListBuilder.borderCommands`)
    /// 와 히트 (`HwpTableCellFrame.paints`, `bands(around:)`) 가 이 하나를 공유한다 (R56).
    /// 두 곳이 따로 계산하면 보이는 선과 눌리는 선이 갈린다.
    func edges(around rect: CGRect) -> [EdgeGeometry] {
        drawnEdges(around: rect).compactMap(\.geometry)
    }

    /// rect 둘레에 칠하는 변들의 띠만 — 경로를 만들지 않아 히트 판정마다 싸다. 경계 상자는
    /// `edges(around:)`가 내는 `EdgeGeometry.band`와 같다.
    public func bands(around rect: CGRect) -> [CGRect] {
        drawnEdges(around: rect).compactMap(\.band)
    }

    /// rect와 그 둘레 테두리 띠를 모두 담는 경계 상자 — 히트 자격 영역이 칠한 곳을 다
    /// 덮도록 (R54 `자격 ⊇ 칠`) 셀·표 프레임에 테두리 바깥 절반을 더한다.
    public func paintedBounds(around rect: CGRect) -> CGRect {
        bands(around: rect).reduce(rect) { $0.union($1) }
    }

    private func drawnEdges(around rect: CGRect) -> [Edge] {
        func visible(_ width: CGFloat, _ shape: HwpBorderType) -> CGFloat {
            width > 0 && shape != .none ? width : 0
        }
        let widths = (
            top: visible(top, topShape), bottom: visible(bottom, bottomShape),
            left: visible(left, leftShape), right: visible(right, rightShape)
        )
        let edges: [Edge] = [
            // 가로 변: 끝에 세로 변이 있으면 그 폭의 절반만큼 연장
            Edge(
                shape: topShape, width: widths.top, color: topColor,
                start: rect.minX, end: rect.maxX, cross: rect.minY, horizontal: true,
                leadExtension: widths.left / 2, trailExtension: widths.right / 2,
                outerIsLeading: true
            ),
            Edge(
                shape: bottomShape, width: widths.bottom, color: bottomColor,
                start: rect.minX, end: rect.maxX, cross: rect.maxY, horizontal: true,
                leadExtension: widths.left / 2, trailExtension: widths.right / 2,
                outerIsLeading: false
            ),
            // 세로 변: 실선·대시·원형은 연장 없음. 여러 줄의 부속선은 가로 변이 있는 끝에서
            // 그 폭의 절반을 기준으로 겹상자로 물러나고, 물결은 그만큼 연장한 곳에서 시작한다.
            Edge(
                shape: leftShape, width: widths.left, color: leftColor,
                start: rect.minY, end: rect.maxY, cross: rect.minX, horizontal: false,
                leadExtension: widths.top / 2, trailExtension: widths.bottom / 2,
                outerIsLeading: true
            ),
            Edge(
                shape: rightShape, width: widths.right, color: rightColor,
                start: rect.minY, end: rect.maxY, cross: rect.maxX, horizontal: false,
                leadExtension: widths.top / 2, trailExtension: widths.bottom / 2,
                outerIsLeading: false
            ),
        ]
        return edges.filter { $0.width > 0 }
    }

    /// 한 변의 입력 — `HwpLineShapeGeometry`의 로컬 좌표(x = 선 방향, y = 가로지르는 축,
    /// 0 = 모서리)를 페이지 좌표로 옮기는 데 필요한 값
    private struct Edge {
        let shape: HwpBorderType
        let width: CGFloat
        let color: HwpRGBColor
        /// 선 방향 축의 셀 모서리 시작·끝
        let start: CGFloat
        let end: CGFloat
        /// 가로지르는 축의 모서리 좌표 (선 중심)
        let cross: CGFloat
        let horizontal: Bool
        /// 시작·끝 쪽 이웃 변 폭의 절반 (없으면 0)
        let leadExtension: CGFloat
        let trailExtension: CGFloat
        /// 띠의 바깥쪽이 −y/−x 쪽인지 (위·왼 변 true, 아래·오른 변 false)
        let outerIsLeading: Bool

        /// 로컬 (x, y) → 페이지: 가로 변은 (lineStart + x, cross + y), 세로 변은
        /// (cross + y, lineStart + x)
        func transform(lineStart: CGFloat) -> CGAffineTransform {
            horizontal
                ? CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: lineStart, ty: cross)
                : CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: cross, ty: lineStart)
        }

        /// 선 자체를 이웃 변 폭의 절반만큼 연장하는가 — 가로 변은 늘, 세로 변은 물결만
        /// (실선·대시·원형 세로 변은 모서리에서 시작하고, 여러 줄은 부속선별로 물러난다)
        private var extendsLine: Bool {
            horizontal || shape == .wave || shape == .doubleWave
        }

        private var lineStart: CGFloat {
            start - (extendsLine ? leadExtension : 0)
        }

        private var lineLength: CGFloat {
            end + (extendsLine ? trailExtension : 0) - lineStart
        }

        private var line: HwpLineShapeGeometry.Line {
            HwpLineShapeGeometry.Line(
                shape: shape, length: lineLength, thickness: width,
                scale: .border, placement: .border
            )
        }

        /// 이 변이 칠하는 영역의 경계 상자 (페이지 좌표) — 가로지르는 축은 모양의 띠, 선
        /// 방향은 연장 포함 [start − lead, end + trail]에 물결의 넘침·획 모서리를 더한 범위.
        /// 경로를 만들지 않는다.
        var band: CGRect? {
            guard lineLength > 0,
                  let cross = HwpLineShapeGeometry.crossExtent(of: line),
                  let along = HwpLineShapeGeometry.alongExtent(of: line)
            else { return nil }
            let alongStart = min(lineStart + along.lowerBound, start - leadExtension)
            let alongEnd = max(lineStart + along.upperBound, end + trailExtension)
            let localBand = CGRect(
                x: alongStart - lineStart, y: cross.lowerBound,
                width: alongEnd - alongStart, height: cross.upperBound - cross.lowerBound
            )
            return localBand.applying(transform(lineStart: lineStart))
        }

        /// 변의 경로 — 여러 줄은 부속선마다 물려 겹상자, 나머지는 연장 길이 전체를 한 경로로
        var geometry: EdgeGeometry? {
            let (lineStart, line) = (lineStart, line)
            guard let band, let extent = HwpLineShapeGeometry.crossExtent(of: line) else {
                return nil
            }
            let transform = transform(lineStart: lineStart)
            let path = CGMutablePath()
            let stripes = HwpLineShapeGeometry.stripes(for: line)
            if stripes.isEmpty {
                guard let shapePath = HwpLineShapeGeometry.path(for: line) else { return nil }
                path.addPath(shapePath, transform: transform)
            } else {
                for stripe in stripes {
                    // 바깥쪽에서의 거리만큼 이웃 변 쪽 끝을 물린다 (이웃 변이 없는 끝은 그대로;
                    // 거리는 **이웃 변 폭** 비율 — 같은 모양의 부속선이 맞닿는 자리, 실측은 같은 폭뿐)
                    let outerDistance = outerIsLeading
                        ? stripe.minY - extent.lowerBound
                        : extent.upperBound - stripe.maxY
                    let inset = outerDistance * 2 / width
                    let stripeStart = start - leadExtension + inset * leadExtension
                    let stripeEnd = end + trailExtension - inset * trailExtension
                    guard stripeEnd > stripeStart else { continue }
                    path.addRect(
                        CGRect(
                            x: stripeStart - lineStart, y: stripe.minY,
                            width: stripeEnd - stripeStart, height: stripe.height
                        ),
                        transform: transform
                    )
                }
            }
            guard !path.isEmpty else { return nil }
            return EdgeGeometry(path: path, color: color, band: band)
        }
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
    /// 갈리면 보이는 선 위의 탭이 아래 블록으로 새거나 그 반대가 된다. 점선·물결의
    /// 빈 자리도 띠로 친다 (한글도 선 위 탭은 셀을 가리킨다).
    public func paints(_ point: CGPoint) -> Bool {
        if fillColor != nil, cellFrame.contains(point) {
            return true
        }
        return borderRects.contains { $0.contains(point) }
    }

    /// 페인터가 실제로 칠하는 테두리 띠 (모서리 중심, 연장 포함) — 경로 없이 띠만 만든다
    private var borderRects: [CGRect] {
        borders.bands(around: cellFrame)
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
