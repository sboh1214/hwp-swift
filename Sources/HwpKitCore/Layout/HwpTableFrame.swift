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

/// 셀 안에 재귀 레이아웃된 중첩 표.
public struct HwpNestedTableFrame: @unchecked Sendable, Hashable {
    /// 바깥 표-로컬 좌표계에서 중첩 표가 차지하는 영역
    public let rect: CGRect
    /// 중첩 표 자체 레이아웃 (origin 0,0 좌표계)
    public let table: HwpTableFrame
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 글 뒤로 배치 (표 70 textWrap) — 표도 그림·도형과 같은 페인트 평면을 갖는다
    /// (R47 #1). 이 값이 없으면 walker가 표를 무조건 마지막에 그려 글 뒤로 표가
    /// 텍스트 앞에 나온다.
    public let paintsBehindText: Bool
    /// 같은 평면 안 정렬 키 (zOrder → 원본 ctrlHeaderArray 순서)
    public let zOrder: Int32
    public let sourceOrder: Int
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int

    public init(
        rect: CGRect,
        table: HwpTableFrame,
        controlInstanceId: UInt32,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlIndex: Int = -1
    ) {
        self.rect = rect
        self.table = table
        self.controlInstanceId = controlInstanceId
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlIndex = controlIndex
    }
}

/// 셀 안 그림 (표-로컬 rect + BinItem 참조).
/// 한글은 셀 안 개체를 셀 콘텐츠로 배치한다 — 페이지 흐름 블록으로 방출하면
/// 큰 그림이 페이지를 밀어내 페이지 수가 한글과 어긋난다 (noori 실측 3쪽).
public struct HwpCellImage: Sendable, Hashable {
    /// 표-로컬 좌표계의 그림 영역
    public let rect: CGRect
    public let binItemId: UInt32
    public let style: HwpImageRenderStyle?
    /// 테두리 색 (없으면 테두리 없음)
    public let borderColor: HwpRGBColor?
    /// 테두리 두께 (pt)
    public let borderWidth: CGFloat
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 (ctrlHeaderArray) 순서 — 동순위
    /// tiebreak이 종류-버킷 순서로 무너지지 않게 한다 (R31 #3)
    public let sourceOrder: Int
    /// 페이지 절단면에 걸친 그림의 가시 영역 (표-로컬, nil = 전체).
    /// rect는 저작 기하를 유지한다 — rect 축소는 스케일 왜곡 (R32 #2)
    public let clipRect: CGRect?
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int

    public init(
        rect: CGRect,
        binItemId: UInt32,
        style: HwpImageRenderStyle?,
        borderColor: HwpRGBColor? = nil,
        borderWidth: CGFloat = 0,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        clipRect: CGRect? = nil,
        controlInstanceId: UInt32,
        controlIndex: Int = -1
    ) {
        self.rect = rect
        self.binItemId = binItemId
        self.style = style
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.clipRect = clipRect
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
    }

    /// rect만 바꾼 사본 — 분할/정렬 이동 시 나머지 필드 누락을 막는다.
    public func withRect(_ rect: CGRect) -> HwpCellImage {
        HwpCellImage(
            rect: rect,
            binItemId: binItemId,
            style: style,
            borderColor: borderColor,
            borderWidth: borderWidth,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            clipRect: clipRect,
            controlInstanceId: controlInstanceId
        )
    }

    /// 가시 영역만 바꾼 사본 (분할 조각 배정)
    public func withClip(_ clipRect: CGRect?) -> HwpCellImage {
        HwpCellImage(
            rect: rect,
            binItemId: binItemId,
            style: style,
            borderColor: borderColor,
            borderWidth: borderWidth,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            clipRect: clipRect,
            controlInstanceId: controlInstanceId
        )
    }

    /// rect·clipRect를 함께 이동한 사본 — 분할 세그먼트 rebase에서 클립이
    /// 제자리에 남지 않게 한다 (R32 #2)
    public func offsetBy(deltaX: CGFloat, deltaY: CGFloat) -> HwpCellImage {
        withRect(rect.offsetBy(dx: deltaX, dy: deltaY))
            .withClip(clipRect?.offsetBy(dx: deltaX, dy: deltaY))
    }
}

/// 셀/글상자 안 도형 (컨테이너-로컬 rect + 지오메트리).
/// 한글은 컨테이너 안 개체를 컨테이너 콘텐츠로 배치한다 — 페이지 흐름
/// 블록으로 방출하면 컨테이너 밖 좌표에 그려진다 (R29 #1).
public struct HwpCellShape: @unchecked Sendable, Hashable {
    public let rect: CGRect
    public let geometry: HwpShapeGeometry
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 순서 (R31 #3)
    public let sourceOrder: Int
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int

    public init(
        rect: CGRect,
        geometry: HwpShapeGeometry,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlInstanceId: UInt32,
        controlIndex: Int = -1
    ) {
        self.rect = rect
        self.geometry = geometry
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
    }

    public func withRect(_ rect: CGRect) -> HwpCellShape {
        HwpCellShape(
            rect: rect,
            geometry: geometry,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId
        )
    }
}

/// 셀 안 글상자 (표-로컬 rect + 글상자 레이아웃).
public struct HwpCellTextbox: @unchecked Sendable, Hashable {
    public let rect: CGRect
    /// 글상자 자체 레이아웃 (origin 0,0 좌표계)
    public let textbox: HwpTextboxFrame
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 순서 (R31 #3)
    public let sourceOrder: Int
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int

    public init(
        rect: CGRect,
        textbox: HwpTextboxFrame,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlInstanceId: UInt32,
        controlIndex: Int = -1
    ) {
        self.rect = rect
        self.textbox = textbox
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
    }

    public func withRect(_ rect: CGRect) -> HwpCellTextbox {
        HwpCellTextbox(
            rect: rect,
            textbox: textbox,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId
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
            nestedTables: nestedTables.map { nested in
                HwpNestedTableFrame(
                    rect: nested.rect.offsetBy(dx: 0, dy: deltaY),
                    table: nested.table,
                    controlInstanceId: nested.controlInstanceId
                )
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

public extension HwpRGBColor {
    init(_ color: CoreHwp.HwpColor) {
        self.init(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255
        )
    }
}
