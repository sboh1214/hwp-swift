import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore

// MARK: - 표 만들기·요소 읽기

extension HwpBorderChainingTests {
    static let green = HwpRGBColor(red: 0, green: 1, blue: 0)
    static let blue = HwpRGBColor(red: 0, green: 0, blue: 1)

    /// 변 하나 — (폭, 모양, 색). 폭 0이면 없는 변
    struct Side {
        var width: CGFloat = 0
        var shape: HwpBorderType = .none
        var color = HwpBorderChainingTests.green

        static let none = Side()
        static func circle(
            _ width: CGFloat = 4, _ color: HwpRGBColor = HwpBorderChainingTests.green
        ) -> Side {
            Side(width: width, shape: .circle, color: color)
        }

        static func shape(_ shape: HwpBorderType, _ width: CGFloat = 4) -> Side {
            Side(width: width, shape: shape)
        }
    }

    static func borders(
        top: Side = .none, bottom: Side = .none, left: Side = .none, right: Side = .none
    ) -> HwpBorderSet {
        HwpBorderSet(
            top: top.width, bottom: bottom.width, left: left.width, right: right.width,
            topColor: top.color, bottomColor: bottom.color, leftColor: left.color,
            rightColor: right.color, topShape: top.shape, bottomShape: bottom.shape,
            leftShape: left.shape, rightShape: right.shape
        )
    }

    /// 칸 하나 — (행, 열, 행 병합, 열 병합, 테두리)
    struct Cell {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let borders: HwpBorderSet

        init(
            _ row: Int, _ column: Int, _ rowSpan: Int, _ columnSpan: Int, _ borders: HwpBorderSet
        ) {
            self.row = row
            self.column = column
            self.rowSpan = rowSpan
            self.columnSpan = columnSpan
            self.borders = borders
        }
    }

    /// (행, 열, 행 병합, 열 병합, 테두리)로 표를 만든다 — 칸 폭·높이는 격자 합, 칸 간격 `spacing`
    static func table(
        widths: [CGFloat], heights: [CGFloat], spacing: CGFloat = 0,
        cells: [Cell]
    ) -> HwpTableFrame {
        func origin(_ sizes: [CGFloat], _ index: Int) -> CGFloat {
            sizes.prefix(index).reduce(spacing) { $0 + $1 + spacing }
        }
        let rows = heights.indices.map { row in
            HwpTableRowFrame(
                rowFrame: CGRect(
                    x: 0, y: origin(heights, row), width: widths.reduce(0, +), height: heights[row]
                ),
                cells: cells.filter { $0.row == row }.map { cell in
                    let (column, rowSpan, columnSpan) = (cell.column, cell.rowSpan, cell.columnSpan)
                    return HwpTableCellFrame(
                        cellFrame: CGRect(
                            x: origin(widths, column), y: origin(heights, row),
                            width: widths[column ..< column + columnSpan].reduce(0, +)
                                + spacing * CGFloat(columnSpan - 1),
                            height: heights[row ..< row + rowSpan].reduce(0, +)
                                + spacing * CGFloat(rowSpan - 1)
                        ),
                        row: row, column: column, rowSpan: rowSpan, columnSpan: columnSpan,
                        paragraphs: [], borders: cell.borders, fillColor: nil
                    )
                }
            )
        }
        return HwpTableFrame(
            outerFrame: CGRect(
                x: 0, y: 0, width: widths.reduce(0, +), height: heights.reduce(0, +)
            ),
            rows: rows, borderColor: HwpRGBColor(red: 0, green: 0, blue: 0), borderWidth: 1
        )
    }

    /// 한 행 표 — 칸마다 같은 테두리를 주거나 칸별로 준다
    static func row(
        _ borders: [HwpBorderSet], width: CGFloat = 30, height: CGFloat = 20
    ) -> HwpTableFrame {
        table(
            widths: Array(repeating: width, count: borders.count), heights: [height],
            cells: borders.enumerated().map { Cell(0, $0.offset, 1, 1, $0.element) }
        )
    }

    /// 두 행 표 — 위 행 아래 변과 아래 행 위 변만 준다 (같은 격자선 y = 20의 두 쪽)
    static func twoRows(upper: [Side], lower: [Side], width: CGFloat = 30) -> HwpTableFrame {
        table(
            widths: Array(repeating: width, count: upper.count), heights: [20, 20],
            cells: upper.enumerated().map { Cell(0, $0.offset, 1, 1, borders(bottom: $0.element)) }
                + lower.enumerated().map { Cell(1, $0.offset, 1, 1, borders(top: $0.element)) }
        )
    }

    struct Element: Equatable {
        let row: Int
        let column: Int
        let color: HwpRGBColor
        let rect: CGRect
    }

    /// 칸마다 그린 테두리 요소 (원·대시 하나하나의 경계 상자, 표 로컬 좌표) — 페인터와 같은
    /// `edges(around:context:)`로
    static func elements(_ table: HwpTableFrame) -> [Element] {
        table.rows.flatMap(\.cells).flatMap { cell in
            let edges = cell.borders.edges(around: cell.cellFrame, context: cell.borderContext)
            return edges.flatMap { edge in
                HwpLineShapeGeometryTests.pieces(edge.path).map {
                    Element(row: cell.row, column: cell.column, color: edge.color, rect: $0)
                }
            }
        }
    }

    /// 가로 격자선 y의 원 중심 x (그린 횟수만큼, 오름차순)
    static func circlesX(
        _ table: HwpTableFrame, y: CGFloat, color: HwpRGBColor = green
    ) -> [CGFloat] {
        elements(table)
            .filter { $0.color == color && abs($0.rect.midY - y) < 0.01 && $0.rect.width < 10 }
            .map { ($0.rect.midX * 1000).rounded() / 1000 }
            .sorted()
    }

    /// 세로 격자선 x의 원 중심 y
    static func circlesY(
        _ table: HwpTableFrame, x: CGFloat, color: HwpRGBColor = green
    ) -> [CGFloat] {
        elements(table)
            .filter { $0.color == color && abs($0.rect.midX - x) < 0.01 && $0.rect.height < 10 }
            .map { ($0.rect.midY * 1000).rounded() / 1000 }
            .sorted()
    }

    /// 두께 4pt 원형 점선의 원 중심 간격 — 두께 400HWPUNIT을 장치 단위로 반올림한 33u의 두 배
    /// 66u (#239)
    static let circlePitch: CGFloat = 7.92

    /// 무늬 원점 `origin`에서 `indices`번째 원들의 중심 (`circlesX`·`circlesY`처럼 0.001 단위)
    static func circleCenters(from origin: CGFloat, _ indices: Range<Int>) -> [CGFloat] {
        indices.map { ((origin + CGFloat($0) * circlePitch) * 1000).rounded() / 1000 }
    }

    /// 두 쪽이 같은 원을 두 번 그린 자리를 한 번으로
    static func unique(_ values: [CGFloat]) -> [CGFloat] {
        Array(Set(values)).sorted()
    }

    /// 표의 어느 칸도 이음 자리를 싣지 않았는가
    static func unchained(_ table: HwpTableFrame) -> Bool {
        table.rows.flatMap(\.cells).allSatisfy { !$0.borderContext.hasPlacements }
    }

    /// 2×3 격자선 y = 20의 두 쪽을 긴 점선(두께 3)으로 — 끝 모서리의 세로 변(`upperRight`·
    /// `lowerRight`)과 위·아래 행 병합만 바꾼다 (`testChainEndTakesTheFarthestExtension`)
    static func cornerGrid(
        upperRight: Side, lowerRight: Side, mergeUpper: Bool = false, mergeLower: Bool = false
    ) -> HwpTableFrame {
        let dot = Side.shape(.longDotLine, 3)
        func row(_ index: Int, merged: Bool, right: Side) -> [Cell] {
            let spans = merged ? [(0, 3)] : [(0, 1), (1, 1), (2, 1)]
            return spans.map { column, span in
                let edge = column + span == 3 ? right : .none
                let borders = index == 0
                    ? Self.borders(bottom: dot, right: edge)
                    : Self.borders(top: dot, right: edge)
                return Cell(index, column, 1, span, borders)
            }
        }
        return table(
            widths: [30, 30, 30], heights: [20, 20],
            cells: row(0, merged: mergeUpper, right: upperRight)
                + row(1, merged: mergeLower, right: lowerRight)
        )
    }
}
