import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

/// 셀 4방향 테두리 (pt 폭 + 색상). 폭 0이면 해당 변은 그리지 않는다.
public struct HwpBorderSet: Sendable, Hashable {
    public let top, bottom, left, right: CGFloat
    public let topColor, bottomColor, leftColor, rightColor: HwpRGBColor

    public init(
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat,
        topColor: HwpRGBColor,
        bottomColor: HwpRGBColor,
        leftColor: HwpRGBColor,
        rightColor: HwpRGBColor
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.leftColor = leftColor
        self.rightColor = rightColor
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

    public init(rect: CGRect, table: HwpTableFrame, controlInstanceId: UInt32) {
        self.rect = rect
        self.table = table
        self.controlInstanceId = controlInstanceId
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
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32

    public init(
        rect: CGRect,
        binItemId: UInt32,
        style: HwpImageRenderStyle?,
        controlInstanceId: UInt32
    ) {
        self.rect = rect
        self.binItemId = binItemId
        self.style = style
        self.controlInstanceId = controlInstanceId
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
        images: [HwpCellImage] = []
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
            // 선 종류가 없으면(문서가 none을 쓰면) 굵기 0으로 취급
            CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: line.thickness))
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
            rightColor: color(lines[1])
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
