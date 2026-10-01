import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble

// MARK: - 모서리 맥락의 굵기·맞물린 물결의 길이·모양 차례

extension HwpBorderCornerTests {
    /// 여러 줄 가로 변이 모서리 너머로 **이어진다**는 것은 같은 모양·**굵기**다 (색은 보지 않는다) —
    /// 굵기가 다른 2중선으로 이어지면 이어지지 않은 것이라 이웃 반폭만큼 나간다 (`so246-junction`
    /// #10·#12: 1×2 칸 80×30, 세로 변 실선 2mm, 칸 0 위 변 2중선 1mm — 칸 1이 2중선 2mm이면 끝 82.80,
    /// 다른 색 2중선 1mm이면 80)
    func testFramedEndContinuesOnlyIntoTheSameWidth() {
        let solid = Self.side(.line, Self.mm2, Self.blue)
        func ends(next: Side) -> [CGFloat] {
            let row = Chaining.row([
                Chaining.borders(top: Self.side(.doubleLine, Self.mm1), left: solid, right: solid),
                Chaining.borders(top: next, left: solid, right: solid),
            ], width: 80, height: 30)
            return Self.pieces(row, color: Self.green).filter { $0.width > $0.height }.map(\.maxX)
        }
        let wider = ends(next: Self.side(.doubleLine, Self.mm2, Self.magenta))
        expect(wider.count) == 2
        for end in wider {
            expect(end).to(beCloseTo(82.80, within: Self.tolerance))
        }
        let same = ends(next: Self.side(.doubleLine, Self.mm1, Self.magenta))
        expect(same.count) == 2
        for end in same {
            expect(end).to(beCloseTo(80, within: Self.tolerance))
        }
    }

    /// 이은 실선은 **자리 0을 담은 조각**이 사슬 전체를 한 번 긋는다 — 첫 칸이 제 물러남(이웃 2중선
    /// 반폭 2.82)보다 좁으면 사슬 원점이 첫 칸 밖이라 둘째 조각이 긋는다. 첫 조각이 늘 긋는다고 보면
    /// 선이 빠지거나 두 번 그려진다.
    func testSolidChainIsDrawnByThePieceHoldingItsOrigin() {
        let solid = Self.side(.line, Self.mm1)
        let table = Chaining.table(widths: [1, 60], heights: [30], cells: [
            Cell(0, 0, 1, 1, Chaining.borders(
                top: solid, left: Self.side(.doubleLine, Self.mm2, Self.blue)
            )),
            Cell(0, 1, 1, 1, Chaining.borders(top: solid)),
        ])
        let green = Self.pieces(table, color: Self.green)
        expect(green.count) == 1
        expect(green.first?.minX).to(beCloseTo(HwpBorderSet.reachWidth(Self.mm2) / 2, within: 1e-6))
        expect(green.first?.maxX).to(beCloseTo(61, within: 1e-6))
        let painters = Chaining.elements(table).filter { $0.color == Self.green }.map(\.column)
        expect(painters) == [1]
    }

    /// 맞물린 물결은 변을 통째로 옮길 뿐 **길이는 칸 변 그대로다** — 끝 모서리의 맥락은 보지 않는다
    /// (`so246-wave`: 칸 폭·높이를 1u씩 늘리면 대각선이 느는 자리가 끝 모서리 + 옮긴 길이). 길이
    /// `칸 변`의 물결을 옮긴 자리에 그린 경로와 같아야 한다.
    func testSameWaveEdgesKeepTheCellEdgeLength() {
        let wave = Self.side(.wave, Self.mm1)
        let set = Chaining.borders(top: wave, bottom: wave, left: wave, right: wave)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let edges = set.edges(around: rect)
        let half = HwpBorderSet.reachWidth(Self.mm1) / 2
        func reference(length: CGFloat) -> CGRect? {
            HwpLineShapeGeometry.path(for: HwpLineShapeGeometry.Line(
                shape: .wave, length: length,
                thickness: HwpBorderSet.visibleWidth(Self.mm1, .wave),
                scale: .border, placement: .border
            ))?.boundingBoxOfPath
        }
        guard edges.count == 4, let across = reference(length: 100),
              let down = reference(length: 40)
        else {
            fail("물결 변 넷과 기준 경로가 있어야 한다")
            return
        }
        let expected: [(CGRect, CGFloat)] = [
            (across, -half), (across, half / 2), (down, -half), (down, half / 2),
        ]
        for (index, (box, shift)) in expected.enumerated() {
            let actual = edges[index].path.boundingBoxOfPath
            // 가로 변은 선 방향이 x, 세로 변은 y (세로 변의 로컬 좌표는 x·y를 바꿔 놓는다)
            let horizontal = index < 2
            let (start, length) = horizontal
                ? (actual.minX, actual.width) : (actual.minY, actual.height)
            expect(length).to(beCloseTo(box.width, within: 1e-6))
            expect(start).to(beCloseTo(box.minX + shift, within: 1e-6))
        }
    }

    /// 셀 간격이 없는 표의 단선 무리(격자선 × 모양)는 **모양(표 25 값) 차례가 먼저**이고 같은
    /// 모양 안에서 격자선 차례다 — 바깥 테두리 덧긋기도 그 차례의 마지막·첫 무리다 (`so246-solidchain`
    /// #15: 2×2 칸 80×40 위 변 점선 1mm·아래 변 원형 점선 1mm·왼 변 2중선 2mm·오른 변 점선 2mm, 칸마다
    /// 다른 색 + 빈 칸 20pt + 빨강 실선 0.1mm 칸 30pt — 실선 세로 x 180·210이 점선 세로 x 80·160보다
    /// 먼저, 가로 점선 y 40이 원형 점선 y 40보다 먼저, 덧긋기는 점선 x 160·실선 x 180·원형 점선 y 80·
    /// 실선 y 0)
    func testGridPaintOrderGroupsByShapeFirst() {
        let colours = [Self.green, Self.blue, Self.magenta, Self.cyan]
        let red = Self.side(.line, 0.1 * 72 / 25.4, HwpRGBColor(red: 1, green: 0, blue: 0))
        let cells = (0 ..< 4).map {
            let colour = colours[$0]
            return Cell($0 / 2, $0 % 2, 1, 1, Chaining.borders(
                top: Self.side(.dotLine, Self.mm1, colour),
                bottom: Self.side(.circle, Self.mm1, colour),
                left: Self.side(.doubleLine, Self.mm2, colour),
                right: Self.side(.dotLine, Self.mm2, colour)
            ))
        } + [
            Cell(0, 2, 2, 1, Chaining.borders()),
            Cell(0, 3, 2, 1, Chaining.borders(top: red, bottom: red, left: red, right: red)),
        ]
        let table = Chaining.table(widths: [80, 80, 20, 30], heights: [40, 40], cells: cells)
        let names = [[0: "G", 1: "B", 3: "R"], [0: "M", 1: "C"]]
        var single: [(Int, String)] = []
        var framed: [Int] = []
        let letters: [(HwpBorderSet.Position, String)] = [
            (.top, "T"), (.bottom, "B"), (.left, "L"), (.right, "R"),
        ]
        for (rowIndex, row) in table.rows.enumerated() {
            for cell in row.cells {
                guard let name = names[rowIndex][cell.column],
                      let order = cell.borderContext.paintOrder
                else { continue }
                for (position, letter) in letters {
                    if position == .left, name != "R" {
                        framed.append(order[position])
                    } else {
                        single.append((order[position], name + letter))
                    }
                }
            }
        }
        let sequence = single.sorted { $0.0 < $1.0 }.map(\.1)
        expect(sequence) == [
            "RR", "GR", "MR", // 세로: 실선 x 210 → 점선 x 80 (실선 x 180·점선 x 160은 덧긋기에 남는다)
            "RB", "GT", "BT", "MT", "CT", "GB", "BB", // 가로: 실선 y 80 → 점선 y 0·40 → 원형 점선 y 40
            "BR", "CR", "RL", // 세로 마지막 무리(점선 x 160), 첫 무리(실선 x 180)
            "MB", "CB", "RT", // 가로 마지막 무리(원형 점선 y 80), 첫 무리(실선 y 0)
        ]
        // 2중선 왼 변은 단선보다 먼저 칸 차례다
        expect(framed.count) == 4
        expect(framed.max()).to(beLessThan(single.map(\.0).min()))
    }
}
