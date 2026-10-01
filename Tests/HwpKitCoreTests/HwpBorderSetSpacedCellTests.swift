import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 셀 간격(`HwpBorderSet.cellSpacing`)이 있는 표의 셀 테두리 (#243) — 한글 12.30.0(build 6446,
/// macOS) PDF 실측(2026-09-28, `probes/243`)의 규칙을 고정한다. 한글은 그 표의 실선·대시·원형 점선
/// 변을 칸마다 네 변의 상자로 그리고, 모서리는 모서리마다 만나는 두 변으로 정한다: 모양·굵기가
/// 같으면(색은 보지 않는다) 맞물려 실선·대시는 가로·세로 변 모두 굵기 절반만큼 나가고 원형 점선은
/// 둘 다 모서리에서 시작한다. 다르면 가로 변은 세로 변 굵기의 절반만큼 나가고 세로 변은 가로 변
/// 굵기의 절반만큼 물러난다. 원형 점선의 원은 단 구분선과 같은 점 무늬다. 여러 줄·물결은 셀 간격이
/// 없는 표와 같다.
final class HwpBorderSetSpacedCellTests: XCTestCase {
    static let black = HwpRGBColor(red: 0, green: 0, blue: 0)
    static let red = HwpRGBColor(red: 1, green: 0, blue: 0)
    static let rect = CGRect(x: 100, y: 200, width: 300, height: 50)
    /// 1mm (표 26 index 10) — 원형 점선 점 무늬 간격 88u = 10.56pt, 칠 지름 37u = 4.44pt
    static let oneMillimetre = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: 10))
    /// 2mm (index 12)
    static let twoMillimetres = CGFloat(CoreHwp.HwpBorderFill.borderThicknessPoints(at: 12))
    /// 실선·대시의 획 — 한글처럼 장치 단위로 반올림한다 (#245): 2pt 17u, 4pt 33u, 1mm 24u(한글
    /// 1.44pt 연장의 두 배), 2mm 47u. 모서리에서 나가고 물러나는 길이도 이 획의 절반이다.
    static let stroke2: CGFloat = 17 * 0.12
    static let stroke4: CGFloat = 33 * 0.12
    static let strokeOneMillimetre: CGFloat = 24 * 0.12
    static let strokeTwoMillimetres: CGFloat = 47 * 0.12

    struct Side {
        var width: CGFloat = 0
        var shape: HwpBorderType = .line
        var color = HwpBorderSetSpacedCellTests.black

        static let none = Side()
    }

    static func set(
        top: Side = .none, bottom: Side = .none, left: Side = .none, right: Side = .none,
        cellSpacing: CGFloat = 2.83
    ) -> HwpBorderSet {
        HwpBorderSet(
            top: top.width, bottom: bottom.width, left: left.width, right: right.width,
            topColor: top.color, bottomColor: bottom.color, leftColor: left.color,
            rightColor: right.color, topShape: top.shape, bottomShape: bottom.shape,
            leftShape: left.shape, rightShape: right.shape, cellSpacing: cellSpacing
        )
    }

    static func solid(_ width: CGFloat, _ color: HwpRGBColor = black) -> Side {
        Side(width: width, shape: .line, color: color)
    }

    static func shape(_ shape: HwpBorderType, _ width: CGFloat) -> Side {
        Side(width: width, shape: shape)
    }

    /// 원 중심 (선 방향 좌표) — `horizontal`이면 x, 아니면 y
    static func centers(_ edge: HwpBorderSet.EdgeGeometry, horizontal: Bool) -> [CGFloat] {
        HwpLineShapeGeometryTests.pieces(edge.path).map { horizontal ? $0.midX : $0.midY }
    }

    enum Position { case top, bottom, left, right }

    /// `rect` 둘레 변 가운데 그 자리의 변 — 띠 중심이 변의 가운데에 가장 가까운 것. 셀 간격이 있는
    /// 칸은 세로 변을 먼저 내므로(`testSpacedCellsPaintVerticalEdgesFirst`) 차례로 찾지 않는다.
    static func edge(
        _ edges: [HwpBorderSet.EdgeGeometry], _ position: Position, around rect: CGRect = rect
    ) -> HwpBorderSet.EdgeGeometry? {
        let target = switch position {
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        }
        return edges.min { lhs, rhs in
            hypot(lhs.band.midX - target.x, lhs.band.midY - target.y)
                < hypot(rhs.band.midX - target.x, rhs.band.midY - target.y)
        }
    }

    static func box(
        _ edges: [HwpBorderSet.EdgeGeometry], _ position: Position
    ) -> CGRect? {
        edge(edges, position)?.path.boundingBoxOfPath
    }

    // MARK: - 실선·대시 모서리

    /// 네 변이 같은 실선이면 모서리마다 맞물린다 — 세로 변도 가로 변 굵기의 절반만큼 나간다 (한글
    /// 1mm: 세로 변 y −1.44 ~ 칸 높이 + 1.44; 셀 간격 0이면 모서리에서). 색은 보지 않는다.
    func testSolidCornersJoinWhenShapeAndWidthMatch() {
        let edges = Self.set(
            top: Self.solid(2), bottom: Self.solid(2), left: Self.solid(2, Self.red),
            right: Self.solid(2)
        ).edges(around: Self.rect)
        expect(edges.count) == 4
        let (thin, half) = (Self.stroke2, Self.stroke2 / 2)
        let top = CGRect(x: 100 - half, y: 200 - half, width: 300 + thin, height: thin)
        expect(Self.box(edges, .top)).to(beCloseTo(top))
        expect(Self.box(edges, .bottom)).to(beCloseTo(top.offsetBy(dx: 0, dy: 50)))
        let left = CGRect(x: 100 - half, y: 200 - half, width: thin, height: 50 + thin)
        expect(Self.box(edges, .left)).to(beCloseTo(left))
        expect(Self.box(edges, .right)).to(beCloseTo(left.offsetBy(dx: 300, dy: 0)))
        // 셀 간격이 없으면 세로 변은 모서리에서 (#191)
        let grid = Self.set(
            top: Self.solid(2), bottom: Self.solid(2), left: Self.solid(2), right: Self.solid(2),
            cellSpacing: 0
        ).edges(around: Self.rect)
        expect(Self.box(grid, .left))
            .to(beCloseTo(CGRect(x: 100 - half, y: 200, width: thin, height: 50)))
    }

    /// 모양이나 굵기가 다른 이웃이면 가로 변이 모서리를 덮고 세로 변은 가로 변 굵기의 절반만큼
    /// 물러난다 (한글: 초록 1mm 세로 변 + 파랑 2mm 가로 변 → 세로 변 y 2.88 ~ 117.36, 가로 변은 −1.44)
    func testVerticalsTuckUnderUnjoinedNeighbours() {
        // 굵기가 다르다: 위 4 · 왼 2
        let (thin, wide) = (Self.stroke2, Self.stroke4)
        let wider = Self.set(top: Self.solid(4), left: Self.solid(2)).edges(around: Self.rect)
        expect(Self.box(wider, .top)).to(beCloseTo(CGRect(
            x: 100 - thin / 2, y: 200 - wide / 2, width: 300 + thin / 2, height: wide
        )))
        expect(Self.box(wider, .left)).to(beCloseTo(CGRect(
            x: 100 - thin / 2, y: 200 + wide / 2, width: thin, height: 50 - wide / 2
        )))
        // 모양이 다르다: 위 점선 2 · 왼 실선 2 — 가로 변(점선)은 나가고 세로 변은 물러난다
        let otherShape = Self.set(top: Self.shape(.dotLine, 2), left: Self.solid(2))
            .edges(around: Self.rect)
        expect(Self.box(otherShape, .top)?.minX).to(beCloseTo(100 - thin / 2, within: 1e-9))
        expect(Self.box(otherShape, .left)).to(beCloseTo(CGRect(
            x: 100 - thin / 2, y: 200 + thin / 2, width: thin, height: 50 - thin / 2
        )))
        // 이웃이 여러 줄·물결이어도 같다 (가로 변의 반폭 = 4/2 만큼 물러난다)
        for neighbour in [HwpBorderType.doubleLine, .wave, .circle] {
            let edges = Self.set(top: Self.shape(neighbour, 4), left: Self.solid(2))
                .edges(around: Self.rect)
            expect(Self.box(edges, .left)?.minY)
                .to(beCloseTo(202, within: 1e-9), description: "\(neighbour)")
        }
        // 히트 띠는 칠한 곳을 다 담는다
        for edge in wider + otherShape {
            expect(edge.band.insetBy(dx: -1e-9, dy: -1e-9).contains(edge.path.boundingBoxOfPath))
                == true
        }
    }

    /// 대시 다섯 모양 모두 실선과 같은 상자 규칙이다 — 네 변이 같으면 세로 변도 반폭 앞에서 첫
    /// 대시를 시작하고(한글 1mm 긴 점선: −1.44 = 획 24u의 절반), 굵기가 다른 이웃이면 그 반폭만큼
    /// 물러나 시작한다. 셀 간격 0이면 세로 변은 모서리에서 시작한다.
    func testDashVerticalsFollowTheBoxCorners() throws {
        let width = Self.oneMillimetre
        let half = Self.strokeOneMillimetre / 2
        let dashes: [HwpBorderType] = [.longDotLine, .dotLine, .dashDot, .dashDotDot, .longDash]
        for shape in dashes {
            let dash = Self.shape(shape, width)
            let label = "\(shape)"
            let joined = Self.set(top: dash, bottom: dash, left: dash, right: dash)
                .edges(around: Self.rect)
            let left = try XCTUnwrap(Self.edge(joined, .left), label)
            expect(HwpLineShapeGeometryTests.pieces(left.path).first?.minY)
                .to(beCloseTo(200 - half, within: 1e-9), description: label)
            let top = try XCTUnwrap(Self.edge(joined, .top), label)
            expect(HwpLineShapeGeometryTests.pieces(top.path).first?.minX)
                .to(beCloseTo(100 - half, within: 1e-9), description: label)
            let unjoined = Self.set(top: Self.solid(4), left: dash).edges(around: Self.rect)
            let tucked = try XCTUnwrap(Self.edge(unjoined, .left), label)
            expect(HwpLineShapeGeometryTests.pieces(tucked.path).first?.minY)
                .to(beCloseTo(200 + Self.stroke4 / 2, within: 1e-9), description: label)
            let grid = Self.set(top: dash, bottom: dash, left: dash, right: dash, cellSpacing: 0)
                .edges(around: Self.rect)
            let gridLeft = try XCTUnwrap(Self.edge(grid, .left), label)
            expect(HwpLineShapeGeometryTests.pieces(gridLeft.path).first?.minY)
                .to(beCloseTo(200, within: 1e-9), description: label)
        }
    }

    /// 셀 간격이 있는 칸은 세로 변을 먼저, 가로 변을 나중에 그린다 — 한글처럼 모서리에서 가로 변이
    /// 위에 온다 (한글 PDF 그리기 순서 74표본). 셀 간격이 없는 칸은 종전 차례(위·아래·왼·오른)다.
    func testSpacedCellsPaintVerticalEdgesFirst() {
        let four = (Self.solid(2), Self.solid(3, Self.red))
        let spaced = Self.set(top: four.1, bottom: four.1, left: four.0, right: four.0)
            .edges(around: Self.rect)
        expect(spaced.map { $0.band.height > $0.band.width }) == [true, true, false, false]
        expect(spaced.map(\.color)) == [Self.black, Self.black, Self.red, Self.red]
        let grid = Self.set(
            top: four.1, bottom: four.1, left: four.0, right: four.0, cellSpacing: 0
        ).edges(around: Self.rect)
        expect(grid.map { $0.band.height > $0.band.width }) == [false, false, true, true]
    }

    // MARK: - 원형 점선

    /// 네 변이 같은 원형 점선이면 변마다 모서리에서 시작하고 점 무늬 간격으로 (한글 1mm: 간격 10.56,
    /// 칠 지름 4.44, 위 변 첫 원 = 왼 모서리, 왼 변 첫 원 = 위 모서리) 중심이 변 끝 앞인 원까지 그린다
    func testJoinedCirclesStartAtTheCornerWithTheDotPattern() throws {
        let circle = Self.shape(.circle, Self.oneMillimetre)
        let edges = Self.set(top: circle, bottom: circle, left: circle, right: circle)
            .edges(around: Self.rect)
        let topEdge = try XCTUnwrap(Self.edge(edges, .top))
        let top = Self.centers(topEdge, horizontal: true)
        // 300pt 변: 0, 10.56, …, 295.68 (29개; 다음 306.24는 끝 너머)
        expect(top.count) == 29
        for (index, center) in top.enumerated() {
            expect(center).to(beCloseTo(100 + CGFloat(index) * 10.56, within: 1e-9))
        }
        // 50pt 변: 0, 10.56, …, 42.24 (5개)
        let left = try Self.centers(XCTUnwrap(Self.edge(edges, .left)), horizontal: false)
        expect(left.count) == 5
        expect(left.first).to(beCloseTo(200, within: 1e-9))
        expect(left.last).to(beCloseTo(242.24, within: 1e-9))
        let circleBox = try XCTUnwrap(HwpLineShapeGeometryTests.pieces(topEdge.path).first)
        expect(circleBox.width).to(beCloseTo(4.44, within: 1e-9))
        // 셀 간격이 없으면 격자 — 가로 변이 세로 변 반폭만큼 나가고 간격 5.76
        let grid = Self.set(
            top: circle, bottom: circle, left: circle, right: circle, cellSpacing: 0
        ).edges(around: Self.rect)
        let gridTop = try Self.centers(XCTUnwrap(Self.edge(grid, .top)), horizontal: true)
        expect(gridTop.first).to(beCloseTo(100 - Self.oneMillimetre / 2, within: 1e-9))
        expect(gridTop[1] - gridTop[0]).to(beCloseTo(5.76, within: 1e-9))
    }

    /// 이웃이 다르면(여기서는 2mm 실선) 원형 점선 가로 변은 이웃 반폭만큼 앞에서, 세로 변은 이웃
    /// 반폭만큼 뒤에서 시작한다 (한글: 가로 첫 원 −2.70, 세로 첫 원 +2.88 — 장치 격자; 이웃 실선의
    /// 반폭은 획 47u의 절반 2.82)
    func testUnjoinedCirclesFollowTheBoxCorners() throws {
        let circle = Self.shape(.circle, Self.oneMillimetre)
        let solid = Self.solid(Self.twoMillimetres)
        let horizontal = Self.set(top: circle, left: solid, right: solid).edges(around: Self.rect)
        let top = try Self.centers(XCTUnwrap(Self.edge(horizontal, .top)), horizontal: true)
        expect(top.first).to(beCloseTo(100 - Self.strokeTwoMillimetres / 2, within: 1e-9))
        expect(top[1] - top[0]).to(beCloseTo(10.56, within: 1e-9))
        let vertical = Self.set(top: solid, bottom: solid, left: circle).edges(around: Self.rect)
        let left = try Self.centers(XCTUnwrap(Self.edge(vertical, .left)), horizontal: false)
        expect(left.first).to(beCloseTo(200 + Self.strokeTwoMillimetres / 2, within: 1e-9))
        // 굵기가 다른 원형 점선 이웃도 맞물리지 않는다
        let thicker = Self.shape(.circle, Self.twoMillimetres)
        let mixed = Self.set(top: thicker, left: circle).edges(around: Self.rect)
        expect(try Self.centers(XCTUnwrap(Self.edge(mixed, .left)), horizontal: false).first)
            .to(beCloseTo(200 + Self.twoMillimetres / 2, within: 1e-9))
        for edge in horizontal + vertical + mixed {
            expect(edge.band.insetBy(dx: -1e-9, dy: -1e-9).contains(edge.path.boundingBoxOfPath))
                == true
        }
    }

    // MARK: - 셀 간격과 무관한 모양

    /// 여러 줄·물결 변은 셀 간격이 있어도 셀 간격 0과 같은 경로다 (한글 실측: 셀 간격 0·1·283 표의
    /// 여러 줄·물결·2중 물결 벡터가 같다)
    func testMultiLineAndWaveEdgesIgnoreCellSpacing() throws {
        let shapes: [HwpBorderType] = [
            .doubleLine, .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine,
            .wave, .doubleWave,
        ]
        for shape in shapes {
            for neighbour in [HwpBorderType.line, shape, .circle] {
                let tested = Self.shape(shape, Self.oneMillimetre)
                let other = Self.shape(neighbour, Self.twoMillimetres)
                let spaced = Self.set(top: tested, bottom: other, left: tested, right: other)
                    .edges(around: Self.rect)
                let grid = Self.set(
                    top: tested, bottom: other, left: tested, right: other, cellSpacing: 0
                ).edges(around: Self.rect)
                // 위·왼 변(시험 모양)만 본다 — 아래·오른 변은 이웃 모양이라 셀 간격을 따를 수 있다
                for position in [Position.top, .left] {
                    let label = "\(shape) next to \(neighbour) edge \(position)"
                    let spacedEdge = try XCTUnwrap(Self.edge(spaced, position), label)
                    let gridEdge = try XCTUnwrap(Self.edge(grid, position), label)
                    expect(HwpLineShapeGeometryTests.pieces(spacedEdge.path)).to(
                        equal(HwpLineShapeGeometryTests.pieces(gridEdge.path)), description: label
                    )
                    expect(spacedEdge.band).to(equal(gridEdge.band), description: label)
                }
            }
        }
    }

    /// 물러나는 몫이 변보다 길면 그 세로 변은 그리지 않는다 (트랩 없이 — 가로 변이 모서리를 덮는다)
    func testInsetLongerThanTheEdgeDrawsNothing() {
        let tiny = CGRect(x: 100, y: 200, width: 30, height: 3)
        let set = Self.set(top: Self.solid(4), bottom: Self.solid(4), left: Self.solid(2))
        let edges = set.edges(around: tiny)
        expect(edges.count) == 2
        expect(set.bands(around: tiny).count) == 2
    }
}

#if canImport(CoreText)
    extension HwpTableLayoutTests {
        /// 표 조판은 표의 셀 간격(표 76, HWPUNIT16)을 칸 테두리에 싣는다 — 1HWPUNIT이어도 (#243)
        func testTableLayoutCarriesCellSpacingIntoCellBorders() {
            for (spacing, expected) in [(HWPUNIT16(283), 2.83), (1, 0.01), (0, 0)] {
                var spaced = table()
                spaced.tableProperty.cellSpacing = spacing
                let result = layout().layout(table: spaced, availableWidth: 200, index: index())
                guard case let .success(frame) = result else {
                    fail("expected table layout success")
                    return
                }
                let cells = frame.rows.flatMap(\.cells)
                expect(cells.count) == 4
                for cell in cells {
                    expect(cell.borders.cellSpacing).to(beCloseTo(CGFloat(expected), within: 1e-9))
                    expect(cell.borders.isSpacedCell) == (spacing > 0)
                }
            }
        }
    }
#endif
