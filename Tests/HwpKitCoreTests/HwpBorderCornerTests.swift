import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 표 셀 테두리의 모서리 끝 자리와 그리는 차례 (#246) — 한글 12.30.0(build 6523, macOS) PDF 실측
/// (2026-10-02, 로컬 `probes/246`의 `so246-*` 문서 8종)을 칸 로컬 좌표(pt)로 고정한다. 한글 값은
/// 0.12pt 장치 격자에 표 원점을 맞추고 선 끝을 장치 한 칸 더 그려 1~1.5u 흔들리므로 0.2 안에서 맞춘다.
final class HwpBorderCornerTests: XCTestCase {
    typealias Chaining = HwpBorderChainingTests
    typealias Side = HwpBorderChainingTests.Side
    typealias Cell = HwpBorderChainingTests.Cell

    static let tolerance: CGFloat = 0.2
    static let green = HwpBorderChainingTests.green
    static let blue = HwpBorderChainingTests.blue
    static let magenta = HwpRGBColor(red: 1, green: 0, blue: 1)
    static let cyan = HwpRGBColor(red: 0, green: 1, blue: 1)
    /// 표 26 굵기 (pt)
    static let mm05: CGFloat = 0.5 * 72 / 25.4
    static let mm1: CGFloat = 72 / 25.4
    static let mm2: CGFloat = 2 * 72 / 25.4

    static func side(
        _ shape: HwpBorderType, _ width: CGFloat, _ color: HwpRGBColor = green
    ) -> Side {
        Side(width: width, shape: shape, color: color)
    }

    /// 칸 하나 (rect 0,0 – w,h)의 변 조각 (원·대시·부속선 하나하나의 경계 상자) — 색별
    static func pieces(
        _ borders: HwpBorderSet, width: CGFloat = 200, height: CGFloat = 120,
        color: HwpRGBColor = green
    ) -> [CGRect] {
        borders.edges(around: CGRect(x: 0, y: 0, width: width, height: height))
            .filter { $0.color == color }
            .flatMap { HwpLineShapeGeometryTests.pieces($0.path) }
    }

    /// 표의 한 색 조각 (표 로컬)
    static func pieces(_ table: HwpTableFrame, color: HwpRGBColor) -> [CGRect] {
        Chaining.elements(table).filter { $0.color == color }.map(\.rect)
    }

    // MARK: - 단선

    /// 셀 간격이 없는 표에서 단선은 여러 줄·물결 이웃 쪽 끝을 가로·세로 모두 이웃 획의 절반만큼 물린다
    /// (`so246-single`·`so243-neighbors0`: 2mm 2중선·물결 이웃 옆 1mm 실선 위 변 2.80 ~ 197.32, 왼 변
    /// 2.76 ~ 117.24; 0.4mm 2중선 이웃 0.52 ~ 199.60). 원형 점선의 첫 원도 그 자리다.
    func testSingleLineRetractsFromAFramedNeighbourInAGrid() {
        for neighbour in [HwpBorderType.doubleLine, .wave, .thinThickThinTripleLine, .doubleWave] {
            let framed = Self.side(neighbour, Self.mm2, Self.blue)
            let top = Self.pieces(Chaining.borders(
                top: Self.side(.line, Self.mm1), left: framed, right: framed
            ))
            expect(top.first?.minX).to(beCloseTo(2.80, within: Self.tolerance))
            expect(top.first?.maxX).to(beCloseTo(197.32, within: Self.tolerance))
            let left = Self.pieces(Chaining.borders(
                top: framed, bottom: framed, left: Self.side(.line, Self.mm1)
            ))
            expect(left.first?.minY).to(beCloseTo(2.76, within: Self.tolerance))
            expect(left.first?.maxY).to(beCloseTo(117.24, within: Self.tolerance))
        }
        let thin = Self.side(.doubleLine, 0.4 * 72 / 25.4, Self.blue)
        let narrow = Self.pieces(Chaining.borders(
            top: Self.side(.line, Self.mm1), left: thin, right: thin
        ))
        expect(narrow.first?.minX).to(beCloseTo(0.52, within: Self.tolerance))
        expect(narrow.first?.maxX).to(beCloseTo(199.60, within: Self.tolerance))
        // 원형 점선: 첫 원 중심 = 선 시작 (한글 2.80)
        let framed = Self.side(.doubleLine, Self.mm2, Self.blue)
        let circles = Self.pieces(Chaining.borders(
            top: Self.side(.circle, Self.mm1), left: framed, right: framed
        ))
        expect(circles.map(\.midX).min()).to(beCloseTo(2.80, within: Self.tolerance))
    }

    /// 셀 간격이 있는 표는 여러 줄·물결 이웃도 맞물리지 않은 모서리다 — 가로 변은 나가고 세로 변은
    /// 물러난다 (#243, `so246-single` s283: 2mm 3중선 이웃 옆 1mm 실선 위 변 −2.70 ~ 202.86, 왼 변
    /// 2.88 ~ 117.36)
    func testSpacedSingleLineExtendsHorizontallyAndRetractsVertically() {
        let (solid, triple) = (Self.mm1, Self.mm2)
        let top = Self.pieces(HwpBorderSet(
            top: solid, bottom: 0, left: triple, right: triple,
            topColor: Self.green, bottomColor: Self.green,
            leftColor: Self.blue, rightColor: Self.blue,
            topShape: .line, bottomShape: .none, leftShape: .thinThickThinTripleLine,
            rightShape: .thinThickThinTripleLine, cellSpacing: 2.83
        ))
        expect(top.first?.minX).to(beCloseTo(-2.70, within: Self.tolerance))
        expect(top.first?.maxX).to(beCloseTo(202.86, within: Self.tolerance))
        let left = Self.pieces(HwpBorderSet(
            top: triple, bottom: triple, left: solid, right: 0,
            topColor: Self.blue, bottomColor: Self.blue,
            leftColor: Self.green, rightColor: Self.green,
            topShape: .thinThickThinTripleLine, bottomShape: .thinThickThinTripleLine,
            leftShape: .line, rightShape: .none, cellSpacing: 2.83
        ))
        expect(left.first?.minY).to(beCloseTo(2.88, within: Self.tolerance))
        expect(left.first?.maxY).to(beCloseTo(117.36, within: Self.tolerance))
    }

    /// 선 없음(`none`) 이웃도 저장된 굵기로 모서리를 셈한다 — 가로 변은 나가고, 셀 간격이 없으면 세로
    /// 변은 모서리에서, 있으면 물러난다 (`so246-single`: 선 없음 5mm 이웃 위 변 −7.04 ~ 207.16, 왼 변
    /// 0 ~ 120; s283 왼 변 7.08 ~ 113.04)
    func testNoneNeighbourCountsWithItsStoredWidth() {
        let none = Side(width: 5 * 72 / 25.4, shape: .none, color: Self.blue)
        let solid = Self.side(.line, Self.mm1)
        let top = Self.pieces(Chaining.borders(top: solid, left: none, right: none))
        expect(top.first?.minX).to(beCloseTo(-7.04, within: Self.tolerance))
        expect(top.first?.maxX).to(beCloseTo(207.16, within: Self.tolerance))
        let left = Self.pieces(Chaining.borders(top: none, bottom: none, left: solid))
        expect(left.first?.minY).to(beCloseTo(0, within: 1e-9))
        expect(left.first?.maxY).to(beCloseTo(120, within: 1e-9))
        let spaced = HwpBorderSet(
            top: none.width, bottom: none.width, left: Self.mm1, right: 0,
            topColor: Self.blue, bottomColor: Self.blue,
            leftColor: Self.green, rightColor: Self.blue,
            topShape: .none, bottomShape: .none, leftShape: .line, rightShape: .none,
            cellSpacing: 2.83
        )
        let spacedLeft = Self.pieces(spaced)
        expect(spacedLeft.first?.minY).to(beCloseTo(7.08, within: Self.tolerance))
        expect(spacedLeft.first?.maxY).to(beCloseTo(113.04, within: Self.tolerance))
    }

    // MARK: - 여러 줄·물결 — 다른 모양·굵기 이웃

    /// 이웃이 모양·굵기가 다르면 여러 줄은 겹상자 없이 부속선 모두 같은 자리다 — 가로 변은 이웃 획의
    /// 절반만큼 나가고 세로 변은 그만큼 물러난다 (`so246-multi`: 2mm 실선·선 없음·2중선 2mm·3중선
    /// 1mm 이웃 옆 1mm 2중선 위 변 −2.72 ~ 202.84, 왼 변 2.88 ~ 117.24; 0.5mm 이웃 ∓0.68·0.72)
    func testFramedEdgeAgainstADifferentNeighbourMovesAllStripesTogether() {
        let neighbours: [(Side, CGFloat)] = [
            (Self.side(.line, Self.mm2, Self.blue), 2.82),
            (Side(width: Self.mm2, shape: .none, color: Self.blue), 2.82),
            (Self.side(.doubleLine, Self.mm2, Self.blue), 2.82),
            (Self.side(.thinThickThinTripleLine, Self.mm1, Self.blue), 1.44),
            (Self.side(.line, Self.mm05, Self.blue), 0.72),
        ]
        for (neighbour, half) in neighbours {
            let shapes: [HwpBorderType] = [
                .doubleLine, .thinThickDoubleLine, .thinThickThinTripleLine,
            ]
            // 같은 모양·굵기 이웃(3중선 1mm 옆 3중선)은 맞물린 모서리라 뺀다
            for shape in shapes where !(shape == neighbour.shape && neighbour.width == Self.mm1) {
                let top = Self.pieces(Chaining.borders(
                    top: Self.side(shape, Self.mm1), left: neighbour, right: neighbour
                ))
                expect(top.count) == (shape == .thinThickThinTripleLine ? 3 : 2)
                for stripe in top {
                    expect(stripe.minX).to(beCloseTo(-half, within: Self.tolerance))
                    expect(stripe.maxX).to(beCloseTo(200 + half, within: Self.tolerance))
                }
                let left = Self.pieces(Chaining.borders(
                    top: neighbour, bottom: neighbour, left: Self.side(shape, Self.mm1)
                ))
                for stripe in left {
                    expect(stripe.minY).to(beCloseTo(half, within: Self.tolerance))
                    expect(stripe.maxY).to(beCloseTo(120 - half, within: Self.tolerance))
                }
            }
        }
    }

    /// 같은 모양·굵기 이웃은 색과 무관하게 맞물린다 — 비대칭 2중선 1×1 모서리의 끝 자리는 부속선마다
    /// 이웃 부속선의 먼 가장자리다 (`so246-multi` #44 가는+굵은: 바깥 가는 선 −1.40 ~ 201.52·안쪽 굵은
    /// 선 0.04 ~ 199.36, #76 굵은+가는: 바깥 굵은 선 −1.40 ~ 201.52·안쪽 가는 선 0.76 ~ 200.08 — 종전
    /// 겹상자 산식은 #44의 굵은 선 끝이 200이었다)
    func testSameShapeCornersNestStripeByStripe() {
        let top = Self.pieces(Chaining.borders(
            top: Self.side(.thinThickDoubleLine, Self.mm1),
            left: Self.side(.thinThickDoubleLine, Self.mm1, Self.blue),
            right: Self.side(.thinThickDoubleLine, Self.mm1, Self.blue)
        )).sorted { $0.minY < $1.minY }
        expect(top.count) == 2
        expect(top[0].minX).to(beCloseTo(-1.40, within: Self.tolerance))
        expect(top[0].maxX).to(beCloseTo(201.52, within: Self.tolerance))
        expect(top[1].minX).to(beCloseTo(0.04, within: Self.tolerance))
        expect(top[1].maxX).to(beCloseTo(199.36, within: Self.tolerance))
        let reversed = Self.pieces(Chaining.borders(
            top: Self.side(.thickThinDoubleLine, Self.mm1),
            left: Self.side(.thickThinDoubleLine, Self.mm1, Self.blue),
            right: Self.side(.thickThinDoubleLine, Self.mm1, Self.blue)
        )).sorted { $0.minY < $1.minY }
        expect(reversed[0].minX).to(beCloseTo(-1.40, within: Self.tolerance))
        expect(reversed[0].maxX).to(beCloseTo(201.52, within: Self.tolerance))
        expect(reversed[1].minX).to(beCloseTo(0.76, within: Self.tolerance))
        expect(reversed[1].maxX).to(beCloseTo(200.08, within: Self.tolerance))
    }

    // MARK: - 여러 줄 — 표 격자의 교차점

    /// 같은 모양·굵기 2중선 격자는 교차점에서 ╬처럼 부속선마다 꺾인다 — 수직 격자선이 그 쪽에 있으면
    /// 가장 가까운 부속선에서 멈추고, 없으면 띠 끝까지 나가 바깥 부속선이 이어진다 (`so246-junction`
    /// #0·#1: 2×2 칸 80×40, 칸 (0,0) 위 변 바깥 −1.44 ~ 81.48·안쪽 0.72 ~ 79.32, 아래 변 두 부속선
    /// 0.72 ~ 79.32, 왼 변 바깥 −1.44 ~ 41.52·안쪽 0.72 ~ 39.36, 오른 변 두 부속선 0.72 ~ 39.36)
    func testSameShapeDoubleGridFormsJunctions() {
        let colours = [Self.green, Self.blue, Self.magenta, Self.cyan]
        let cells = (0 ..< 4).map { index -> Cell in
            let edge = Self.side(.doubleLine, Self.mm1, colours[index])
            return Cell(index / 2, index % 2, 1, 1, Chaining.borders(
                top: edge, bottom: edge, left: edge, right: edge
            ))
        }
        let table = Chaining.table(widths: [80, 80], heights: [40, 40], cells: cells)
        let green = Self.pieces(table, color: Self.green)
        func stripe(horizontal: Bool, cross: ClosedRange<CGFloat>) -> CGRect? {
            green.first { piece in
                (horizontal ? piece.width > piece.height : piece.height > piece.width)
                    && cross.contains(horizontal ? piece.midY : piece.midX)
            }
        }
        struct Expected {
            let horizontal: Bool
            let cross: ClosedRange<CGFloat>
            let span: ClosedRange<CGFloat>
        }
        let expected = [
            Expected(horizontal: true, cross: -2 ... -0.5, span: -1.44 ... 81.48),
            Expected(horizontal: true, cross: 0.5 ... 2, span: 0.72 ... 79.32),
            Expected(horizontal: true, cross: 38 ... 39.5, span: 0.72 ... 79.32),
            Expected(horizontal: true, cross: 40.5 ... 42, span: 0.72 ... 79.32),
            Expected(horizontal: false, cross: -2 ... -0.5, span: -1.44 ... 41.52),
            Expected(horizontal: false, cross: 0.5 ... 2, span: 0.72 ... 39.36),
            Expected(horizontal: false, cross: 78 ... 79.5, span: 0.72 ... 39.36),
            Expected(horizontal: false, cross: 80.5 ... 82, span: 0.72 ... 39.36),
        ]
        for item in expected {
            let (horizontal, cross) = (item.horizontal, item.cross)
            let (start, end) = (item.span.lowerBound, item.span.upperBound)
            let piece = stripe(horizontal: horizontal, cross: cross)
            let label = "\(horizontal ? "H" : "V") \(cross)"
            expect(horizontal ? piece?.minX : piece?.minY)
                .to(beCloseTo(start, within: Self.tolerance), description: label)
            expect(horizontal ? piece?.maxX : piece?.maxY)
                .to(beCloseTo(end, within: Self.tolerance), description: label)
        }
    }

    /// 다른 모양 이웃과 만나는 여러 줄은 표 격자로 끝 자리가 갈린다 (`so246-cells` #3·#4, `junction`
    /// #24·#28): 가로 변은 같은 2중선으로 이어지는 모서리에서 멈추고 세로 실선이 위아래로 지나가는
    /// 모서리에서 물러나며, 세로 변은 가로선이 좌우로 지나가는 모서리에서 물러나고 같은 2중선으로 이어지는
    /// 모서리에서 멈춘다.
    func testFramedEdgesFollowTheGridAtJunctions() {
        let colours = [Self.green, Self.blue, Self.magenta, Self.cyan]
        let horizontal = Chaining.table(widths: [80, 80], heights: [40, 40], cells: (0 ..< 4).map {
            let double = Self.side(.doubleLine, Self.mm1, colours[$0])
            let solid = Self.side(.line, Self.mm1, colours[$0])
            return Cell($0 / 2, $0 % 2, 1, 1, Chaining.borders(
                top: double, bottom: double, left: solid, right: solid
            ))
        })
        let green = Self.pieces(horizontal, color: Self.green).filter { $0.width > $0.height }
        // 위 변 (y 0): 왼 모서리 −1.44 (L), 오른 모서리 80.04 (이어짐); 아래 변 (y 40): 1.44 (세로선이
        // 지나감) ~ 80.04 (이어짐)
        for stripe in green {
            let bottom = stripe.midY > 20
            expect(stripe.minX).to(beCloseTo(bottom ? 1.44 : -1.44, within: Self.tolerance))
            expect(stripe.maxX).to(beCloseTo(80, within: Self.tolerance))
        }
        let blue = Self.pieces(horizontal, color: Self.blue).filter { $0.width > $0.height }
        for stripe in blue {
            // 칸 (0,1) 아래 변: 오른 모서리에 세로선이 지나가 158.52
            let bottom = stripe.midY > 20
            expect(stripe.minX).to(beCloseTo(80, within: Self.tolerance))
            expect(stripe.maxX).to(beCloseTo(bottom ? 158.52 : 161.28, within: Self.tolerance))
        }
        let vertical = Chaining.table(widths: [80, 80], heights: [40, 40], cells: (0 ..< 4).map {
            let double = Self.side(.doubleLine, Self.mm1, colours[$0])
            let solid = Self.side(.line, Self.mm1, colours[$0])
            return Cell($0 / 2, $0 % 2, 1, 1, Chaining.borders(
                top: solid, bottom: solid, left: double, right: double
            ))
        })
        let greenV = Self.pieces(vertical, color: Self.green).filter { $0.height > $0.width }
        for stripe in greenV {
            // 왼 변 (x 0): 1.44 ~ 39.96 (같은 2중선으로 이어짐), 오른 변 (x 80): 1.44 ~ 38.52 (가로선이
            // 지나감)
            let right = stripe.midX > 40
            expect(stripe.minY).to(beCloseTo(1.44, within: Self.tolerance))
            expect(stripe.maxY).to(beCloseTo(right ? 38.52 : 40, within: Self.tolerance))
        }
    }

    // MARK: - 물결

    /// 같은 물결 이웃과 맞물린 물결은 파를 2중선의 부속선처럼 물린다 (#246·#253) — 시작 모서리의 수직선이
    /// 물결 띠 쪽(첫 파는 위·왼)에 그린 변을 가지면 이웃 안쪽 부속선의 먼 가장자리 +w 뒤로, 아니면 이웃 띠의
    /// 먼 가장자리 −2w 앞으로 옮기고 길이는 칸 변 그대로다 (한글 실측 `so246-wave`·`so253-tables`: 1mm(B 24u,
    /// w 6u) 물결 위·왼 변 −1.44, 아래·오른 변 0.72, 2×2 아래 행 위 변 0.72)
    func testSameWaveCornersShiftTheWholeEdge() {
        let wave = Self.side(.wave, Self.mm1)
        let set = Chaining.borders(top: wave, bottom: wave, left: wave, right: wave)
        let edges = set.edges(around: CGRect(x: 0, y: 0, width: 100, height: 40))
        let unit: CGFloat = 0.12
        let corner = 6 * unit / 2 / 2.0.squareRoot()
        // 첫 대각선의 시작 (획 모서리만큼 앞으로 나간 상자를 되돌린다)

        func start(_ edge: HwpBorderSet.EdgeGeometry, horizontal: Bool) -> CGFloat {
            let box = edge.path.boundingBoxOfPath
            return (horizontal ? box.minX : box.minY) + corner
        }
        expect(start(edges[0], horizontal: true)).to(beCloseTo(-12 * unit, within: 1e-9))
        expect(start(edges[1], horizontal: true)).to(beCloseTo(6 * unit, within: 1e-9))
        expect(start(edges[2], horizontal: false)).to(beCloseTo(-12 * unit, within: 1e-9))
        expect(start(edges[3], horizontal: false)).to(beCloseTo(6 * unit, within: 1e-9))
        // 아래 행 위 변은 시작 모서리 위에 왼 변이 있어 뒤로 옮긴다
        let table = Chaining.table(widths: [80, 80], heights: [40, 40], cells: (0 ..< 4).map {
            Cell($0 / 2, $0 % 2, 1, 1, set)
        })
        let lower = table.rows[1].cells[0]
        let lowerTop = lower.borders.edges(around: lower.cellFrame, context: lower.borderContext)
        expect(start(lowerTop[0], horizontal: true)).to(beCloseTo(6 * unit, within: 1e-9))
    }

    // MARK: - 실선 사슬

    /// 셀 간격이 없는 표의 실선도 격자선을 따라 잇는다 — 안쪽 모서리의 2중선과 무관하게 한 선이고 자리
    /// 0을 담은 조각(여기서는 첫 조각)이 한 번에 긋는다. 색이 다른 조각은 사슬을 끊어 그 끝에서 물러난다 (`so246-cells` #7·
    /// `solidchain` #3: 1×3 위 변 −0.16 ~ 180.08 한 선, 가운데 칸만 파랑이면 초록 −0.16 ~ 57.2)
    func testSolidChainsIgnoreInteriorCorners() {
        let double = Self.side(.doubleLine, Self.mm2, Self.blue)
        let solid = Self.side(.line, Self.mm1)
        let row = Chaining.row([
            Chaining.borders(top: solid, right: double),
            Chaining.borders(top: solid, left: double, right: double),
            Chaining.borders(top: solid, left: double),
        ], width: 60, height: 30)
        let green = Self.pieces(row, color: Self.green)
        expect(green.count) == 1
        expect(green.first?.minX).to(beCloseTo(0, within: 1e-9))
        expect(green.first?.maxX).to(beCloseTo(180, within: 1e-9))
        // 뒤 칸들의 위 변은 칠하지 않아도 선 위라 띠를 낸다
        for cell in row.rows[0].cells.dropFirst() {
            let bands = cell.borders.bands(around: cell.cellFrame, context: cell.borderContext)
            expect(bands.contains { $0.contains(CGPoint(x: cell.cellFrame.midX, y: 0)) }) == true
        }
        let broken = Chaining.row([
            Chaining.borders(top: solid, right: double),
            Chaining.borders(
                top: Self.side(.line, Self.mm1, Self.blue), left: double, right: double
            ),
            Chaining.borders(top: solid, left: double),
        ], width: 60, height: 30)
        let pieces = Self.pieces(broken, color: Self.green).sorted { $0.minX < $1.minX }
        expect(pieces.count) == 2
        expect(pieces[0].maxX).to(beCloseTo(57.2, within: Self.tolerance))
        expect(pieces[1].minX).to(beCloseTo(122.72, within: Self.tolerance))
    }
}

// MARK: - 교차점의 3중선·그리는 차례

extension HwpBorderCornerTests {
    /// 3중선 가운데 부속선은 교차점을 엇갈려 지난다 (`so246-junction` #2: 2×2 칸 80×40, 칸 (0,0) 아래
    /// 변 가운데 부속선 −0.48 ~ 80.52)
    func testTripleCenterStripesCrossAtJunctions() {
        let colours = [Self.green, Self.blue, Self.magenta, Self.cyan]
        let triple = Chaining.table(widths: [80, 80], heights: [40, 40], cells: (0 ..< 4).map {
            let edge = Self.side(.thinThickThinTripleLine, Self.mm1, colours[$0])
            return Cell($0 / 2, $0 % 2, 1, 1, Chaining.borders(
                top: edge, bottom: edge, left: edge, right: edge
            ))
        })
        let middle = Self.pieces(triple, color: Self.green).first {
            $0.width > $0.height && abs($0.midY - 40) < 0.1
        }
        expect(middle?.minX).to(beCloseTo(-0.48, within: Self.tolerance))
        expect(middle?.maxX).to(beCloseTo(80.52, within: Self.tolerance))
    }

    // MARK: - 그리는 차례

    /// 셀 간격이 없는 표의 그리는 차례 (`so246-cells` #2 2×2 실선 칸마다 다른 색): 세로 격자선 x 차례
    /// (격자선 안은 사슬을 만든 차례) → 가로 격자선 y 차례 → 바깥 테두리 덧그리기(세로 마지막·첫 무리,
    /// 가로 마지막·첫 무리 — 첫 무리는 사슬을 거꾸로). 여러 줄·물결 변은 그 모두보다 먼저 칸 차례다.
    func testGridPaintOrderFollowsHangul() {
        let colours = [Self.green, Self.blue, Self.magenta, Self.cyan]
        let table = Chaining.table(widths: [80, 80], heights: [40, 40], cells: (0 ..< 4).map {
            let edge = Self.side(.line, Self.mm1, colours[$0])
            return Cell($0 / 2, $0 % 2, 1, 1, Chaining.borders(
                top: edge, bottom: edge, left: edge, right: edge
            ))
        })
        let names = ["G", "B", "M", "C"]
        var ranked: [(Int, String)] = []
        for (index, cell) in table.rows.flatMap(\.cells).enumerated() {
            let order = cell.borderContext.paintOrder
            let letters: [(HwpBorderSet.Position, String)] = [
                (.top, "T"), (.bottom, "B"), (.left, "L"), (.right, "R"),
            ]
            for (position, letter) in letters {
                ranked.append((order?[position] ?? -1, names[index] + letter))
            }
        }
        let sequence = ranked.sorted { $0.0 < $1.0 }.map(\.1)
        expect(sequence) == [
            "GR", "BL", "MR", "CL", // 세로 가운데 격자선 (덧그리지 않는 것만 남는다)
            "GB", "MT", "BB", "CT", // 가로 가운데 격자선
            "BR", "CR", "ML", "GL", // 세로 마지막 무리, 첫 무리(거꾸로)
            "MB", "CB", "BT", "GT", // 가로 마지막 무리, 첫 무리(거꾸로)
        ]
        // 여러 줄 변은 단선보다 먼저 칸 차례(왼·오른·위·아래)다 — 위 변 2중선이 왼·오른 실선 아래에 깔린다
        let mixed = Chaining.row([Chaining.borders(
            top: Self.side(.doubleLine, Self.mm1), bottom: Self.side(.doubleLine, Self.mm1),
            left: Self.side(.line, Self.mm2, Self.blue),
            right: Self.side(.line, Self.mm2, Self.blue)
        )])
        let order = mixed.rows[0].cells[0].borderContext.paintOrder
        expect(order.map { [$0.top, $0.bottom].max()! < [$0.left, $0.right].min()! }) == true
    }

    /// 셀 간격이 있는 표는 칸마다 왼·오른·위·아래다 (`so246-order` s283 49표본)
    func testSpacedPaintOrderIsPerCell() {
        let edge = Self.side(.doubleLine, Self.mm1)
        let spaced = HwpBorderSet(
            top: edge.width, bottom: edge.width, left: Self.mm2, right: Self.mm2,
            topColor: Self.green, bottomColor: Self.green,
            leftColor: Self.blue, rightColor: Self.blue,
            topShape: .doubleLine, bottomShape: .doubleLine, leftShape: .line, rightShape: .line,
            cellSpacing: 2.83
        )
        let table = Chaining.table(
            widths: [80, 80], heights: [40], spacing: 2.83,
            cells: [Cell(0, 0, 1, 1, spaced), Cell(0, 1, 1, 1, spaced)]
        )
        let orders = table.rows[0].cells.compactMap(\.borderContext.paintOrder)
        expect(orders.count) == 2
        for (index, order) in orders.enumerated() {
            expect([order.left, order.right, order.top, order.bottom])
                == (0 ..< 4).map { index * 4 + $0 }
        }
    }
}
