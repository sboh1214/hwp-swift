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

    public init(
        cellFrame: CGRect,
        row: Int,
        column: Int,
        rowSpan: Int,
        columnSpan: Int,
        paragraphs: [HwpLaidOutParagraph],
        borders: HwpBorderSet,
        fillColor: HwpRGBColor?
    ) {
        self.cellFrame = cellFrame
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.paragraphs = paragraphs
        self.borders = borders
        self.fillColor = fillColor
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
