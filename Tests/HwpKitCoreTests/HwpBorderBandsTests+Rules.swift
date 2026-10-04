import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

// MARK: - 모서리·끝 규칙 (값 표 밖의 단위 핀)

extension HwpBorderBandsTests {
    /// 다칸 표 안쪽 격자선 — 시작 모서리의 수직 격자선이 양쪽에 그려져 있어 두 파 모두 +w에서 시작한다 (한글
    /// `so253-grid` 2×2 1.5mm 2중 물결: B 35u·w 9u — 이 문서의 1×2·2×1·2×2·3×3 표 104개가 이 규칙의 선분과 쪽마다
    /// 같다). 바깥 위 변은 1×1처럼 첫 파 −2w·둘째 파 +w다. 칸 750u × 417u.
    func testInteriorGridLinesStartBothWavesAtTheInnerSlot() {
        let side = Chaining.Side(width: Self.thickness(millimetres: 1.5), shape: .doubleWave)
        let set = Chaining.borders(top: side, bottom: side, left: side, right: side)
        let table = Chaining.table(
            widths: [750 * Self.unit, 750 * Self.unit], heights: [417 * Self.unit, 417 * Self.unit],
            cells: (0 ..< 4).map { Chaining.Cell($0 / 2, $0 % 2, 1, 1, set) }
        )

        func summaries(row: Int, column: Int, _ position: Side) -> [WaveSummary] {
            let cell = table.rows[row].cells[column]
            let edges = cell.borders.edges(around: cell.cellFrame, context: cell.borderContext)
            let index = [Side.top, .bottom, .left, .right].firstIndex(of: position) ?? 0
            let frame = cell.cellFrame
            let along = position.horizontal ? frame.minX : frame.minY
            let cross: CGFloat = switch position {
            case .top: frame.minY
            case .bottom: frame.maxY
            case .left: frame.minX
            case .right: frame.maxX
            }
            let shifted = Self.elements(
                of: edges[index].path, horizontal: position.horizontal, cross: cross
            ).map {
                Element(
                    diagonal: $0.diagonal, start: $0.start - along / Self.unit,
                    end: $0.end - along / Self.unit, cross: $0.cross, width: $0.width
                )
            }
            return Self.waveSummaries(shifted, length: position.horizontal ? 750 : 417)
        }
        func check(_ got: [WaveSummary], _ want: [[CGFloat]], _ label: String) {
            Self.expectWaves(got, want.map(WaveSummary.init), label)
        }
        // 대각선 k는 시작 + 36k, 끝은 시작 + 칸 길이 — 750u면 21개, 417u면 12개
        check(summaries(row: 0, column: 0, .top), [[-18, 21, -13], [9, 21, 14]], "outer top")
        check(summaries(row: 1, column: 0, .top), [[9, 21, 14], [9, 21, 14]], "inner top")
        check(summaries(row: 0, column: 0, .bottom), [[9, 21, 14], [9, 21, 14]], "inner bottom")
        check(summaries(row: 0, column: 1, .left), [[9, 12, 23], [9, 12, 23]], "inner left")
        check(summaries(row: 0, column: 0, .left), [[-18, 12, -4], [9, 12, 23]], "outer left")
    }

    /// 다른 모양 이웃 쪽 끝은 이웃 획 B를 모서리의 장치 단위 행 [−⌊B/2⌋, ⌈B/2⌉)로 본 자리다 (`so253-ends`·
    /// `so246-multi`): 가로 변이 덮을 때 시작은 ⌊B/2⌋ 앞·끝은 ⌈B/2⌉ − 1 뒤(한글은 끝을 행의 마지막 칸에서
    /// 멈춘다), 물러날 때 시작은 ⌈B/2⌉ 뒤·끝은 ⌊B/2⌋ 앞이다. 이어지면 0이고, 가로 변도 수직 격자선이 지나가면
    /// 물러난다.
    func testFramedReachSplitsTheNeighbourStrokeOnTheDeviceGrid() {
        func border(_ millimetres: CGFloat, _ shape: HwpBorderType = .line) -> HwpBorderSet.Border {
            HwpBorderSet.Border(
                shape: shape, width: Self.thickness(millimetres: millimetres), color: Self.blue
            )
        }

        func reach(
            _ horizontal: Bool, _ neighbour: HwpBorderSet.Border, _ corner: HwpBorderCornerContext,
            atStart: Bool
        ) -> CGFloat {
            HwpBorderSet.framedReach(
                horizontal: horizontal, neighbour: neighbour, corner: corner, atStart: atStart
            ) / Self.unit
        }
        let open = HwpBorderCornerContext(crossesNear: true)
        // (굵기, 획 B) — 2mm 47u, 0.5mm 12u, 선 없음 0.1mm 2u, 2중선 1mm 24u
        let neighbours: [(HwpBorderSet.Border, CGFloat)] = [
            (border(2), 47), (border(0.5), 12), (border(0.1, .none), 2),
            (border(1, .doubleLine), 24),
        ]
        for (neighbour, units) in neighbours {
            let low = (units / 2).rounded(.down)
            let high = units - low
            expect(reach(true, neighbour, open, atStart: true)).to(beCloseTo(low, within: 1e-9))
            expect(reach(true, neighbour, open, atStart: false))
                .to(beCloseTo(high - 1, within: 1e-9))
            expect(reach(false, neighbour, open, atStart: true)).to(beCloseTo(-high, within: 1e-9))
            expect(reach(false, neighbour, open, atStart: false)).to(beCloseTo(-low, within: 1e-9))
        }
        let passes = HwpBorderCornerContext(crossesNear: true, crossesBeyond: true)
        expect(reach(true, border(2), passes, atStart: true)).to(beCloseTo(-24, within: 1e-9))
        expect(reach(true, border(2), passes, atStart: false)).to(beCloseTo(-23, within: 1e-9))
        let continues = HwpBorderCornerContext(continues: true, crossesNear: true)
        expect(reach(true, border(2), continues, atStart: false)) == 0
        expect(reach(false, border(2), continues, atStart: true)) == 0
        // 굵기 0 이웃은 어느 쪽도 0이다 (끝에서 1u를 빼지 않는다)
        expect(reach(true, border(0), open, atStart: false)) == 0
    }

    /// 이웃이 그리는 폭(히트 띠 연장)은 여러 줄·물결이 칠하는 가로지르는 범위 전체다 — 1mm 2중선 [−12, 12]u,
    /// 물결 [−24, 6]u(위 평탄 −21u − 획 반폭 3u ~ 아래 평탄 3u + 3u), 2중 물결 [−24, 24]u
    func testFramedNeighboursReportTheirDrawnBand() {
        let millimetre = Self.thickness(millimetres: 1)
        expect(HwpBorderSet.drawnWidth(millimetre, .doubleLine) / Self.unit)
            .to(beCloseTo(24, within: 1e-9))
        expect(HwpBorderSet.drawnWidth(millimetre, .thinThickDoubleLine) / Self.unit)
            .to(beCloseTo(24, within: 1e-9))
        expect(HwpBorderSet.drawnWidth(millimetre, .wave) / Self.unit)
            .to(beCloseTo(30, within: 1e-9))
        expect(HwpBorderSet.drawnWidth(millimetre, .doubleWave) / Self.unit)
            .to(beCloseTo(48, within: 1e-9))
        expect(HwpBorderSet.drawnWidth(millimetre, .line) / Self.unit)
            .to(beCloseTo(24, within: 1e-9))
        expect(HwpBorderSet.drawnWidth(millimetre, .none)) == 0
    }

    /// 표 셀 테두리·단 구분선의 물결은 마지막 대각선 뒤 평탄도 시작이 끝 앞이면 긋는다 (한글은 평탄을 따로
    /// 긋는다 — 셀 간격 표 0.1mm 세로 변 666u: 대각선 222개 뒤 평탄 222개). 글자선은 좇지 않는다 (#252).
    func testTrailingFlatIsDrawnForBordersOnly() {
        // 1mm: 대각선 0·25·50 (끝 74 — 끝 74.5 앞)
        var border = Self.line(.wave, 10)
        border.length = 74.5 * Self.unit
        let borderElements = Self.elements(
            of: Self.path(border), horizontal: true, cross: 0
        )
        expect(borderElements.filter(\.diagonal).count) == 3
        expect(borderElements.filter { !$0.diagonal }.count) == 3
        // 범위 끝은 마지막 대각선의 획 모서리(획 6u의 반폭/√2)가 평탄 끝(75u)보다 멀다
        let corner = 6 * Self.unit / 2 / 2.0.squareRoot()
        expect(HwpLineShapeGeometry.alongExtent(of: border)?.upperBound ?? 0)
            .to(beCloseTo(74 * Self.unit + corner, within: 1e-9))
        // 0.1mm(B 2u, 획 1u): 대각선 0·3·6 뒤 평탄 [8, 9)u가 획 모서리보다 멀어 범위 끝이다
        var thin = Self.line(.wave, 0)
        thin.length = 8.5 * Self.unit
        expect(HwpLineShapeGeometry.alongExtent(of: thin)?.upperBound ?? 0)
            .to(beCloseTo(9 * Self.unit, within: 1e-9))
        // 끝이 평탄 시작과 같으면 긋지 않는다
        border.length = 74 * Self.unit
        let tied = Self.elements(
            of: Self.path(border), horizontal: true, cross: 0
        )
        expect(tied.filter { !$0.diagonal }.count) == 2
        // 글자선: 40pt 물결(r 38u, 반주기 39u) 대각선 0·39 뒤 평탄은 사이 하나뿐
        let character = HwpLineShapeGeometry.Line(
            shape: .wave, length: 77.5 * Self.unit, thickness: 1.56,
            scale: .characterLine(fontSize: 40), placement: .strikethrough
        )
        let characterElements = Self.elements(
            of: Self.path(character), horizontal: true, cross: 0
        )
        expect(characterElements.filter(\.diagonal).count) == 2
        expect(characterElements.filter { !$0.diagonal }.count) == 1
    }

    /// 선의 경로 (없으면 빈 경로)
    static func path(_ line: HwpLineShapeGeometry.Line) -> CGPath {
        HwpLineShapeGeometry.path(for: line) ?? CGMutablePath()
    }
}
