import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 표 셀 테두리 무늬 이어 그리기 (#238) — 한글 12.30 실측(2026-09-27, 합성 HWPX → PDF 벡터)의
/// 규칙을 손으로 만든 표로 고정한다. 한글은 같은 격자선에서 모양·굵기·색이 같은 이웃 칸의
/// 대시·원형 점선 변을 한 선으로 잇고, 격자선마다 선 모양마다 "지금 사슬" 하나를 위(왼) 칸의
/// 아래(오른) 변부터 본다. 두께 4pt 원형 점선은 칠 지름 4.2(35u)·간격 7.92(66u)다 (#239 —
/// 두께를 장치 단위로 반올림한 33u가 단위).
final class HwpBorderChainingTests: XCTestCase {
    // MARK: - 이음

    /// 1×3 위 변 원형 점선 (한글 so238-main #0): 칸 경계에서 다시 시작하지 않고 한 간격으로
    /// 이어지며 원마다 한 번만 그린다. 끝은 사슬 끝(90) 앞 원(87.12)까지 — 칸 경계(30·60)마다 다시
    /// 시작했다면 0·7.92·15.84·23.76 · 30·37.92·45.84·53.76 · 60·67.92·75.84·83.76이다.
    func testSameStyleNeighboursContinueOnePattern() {
        let table = Self.row(Array(repeating: Self.borders(top: .circle()), count: 3))
        expect(Self.circlesX(table, y: 0)) == Self.circleCenters(from: 0, 0 ..< 12)
        // 칸 경계에 걸친 원은 자리를 맡은 칸 하나가 통째로 그린다 (23.76은 첫 칸, 칸 경계 30에
        // 걸친 31.68 [29.58, 33.78]은 둘째 칸)
        let owners = Self.elements(table).map { ($0.column, $0.rect.midX) }
        expect(owners.filter { abs($0.1 - 23.76) < 1e-6 }.map(\.0)) == [0]
        expect(owners.filter { abs($0.1 - 31.68) < 1e-6 }.map(\.0)) == [1]
    }

    /// 세로 변이 있으면 가로 사슬의 무늬 원점은 첫 칸의 연장 포함 시작(−t/2)이고 끝도 마지막 칸의
    /// 연장까지다 (한글 so238-main #2·#3: 1mm 원 −1.44에서 시작, 칸 사이 세로 변과 무관하게 이어짐).
    func testChainOriginIsTheFirstPiecesExtendedStart() {
        let side = Self.borders(
            top: .circle(), left: .shape(.line), right: .shape(.line)
        )
        let table = Self.row([side, side, side])
        // 원점 −2, 끝 92: 중심 −2 … 85.12 (93.04는 끝 뒤)
        expect(Self.circlesX(table, y: 0)) == Self.circleCenters(from: -2, 0 ..< 12)
        // 끝 모서리 뒤 연장 구간 [93, 95)의 원(93.04)도 마지막 칸이 그린다 — 칸 폭 31
        let wide = Self.row([side, side, side], width: 31)
        expect(Self.circlesX(wide, y: 0)) == Self.circleCenters(from: -2, 0 ..< 13)
    }

    /// 대시는 사슬 전체로 이어지고 칸 경계에 걸친 대시는 시작 칸이 통째로 그린다 — 그 칸의 띠가
    /// 넘친 몫까지 덮는다 (R54 `자격 ⊇ 칠`). 사슬 끝에서만 잘린다.
    func testDashesContinueAndTheStartingCellDrawsTheWholeDash() throws {
        // 긴 점선 두께 3: 단위 22/15 × 3 = 4.4, 대시 22 · 공백 13.2 (주기 35.2)
        let table = Self.row(Array(repeating: Self.borders(top: .shape(.longDotLine, 3)), count: 3))
        let dashes = Self.elements(table).sorted { $0.rect.minX < $1.rect.minX }
        expect(dashes.map { ($0.rect.minX * 100).rounded() / 100 }) == [0, 35.2, 70.4]
        expect(dashes.map(\.column)) == [0, 1, 2]
        // 둘째 대시 [35.2, 57.2]는 둘째 칸, 셋째 [70.4, 90]은 사슬 끝(90)에서 잘린다
        expect(dashes[1].rect.maxX).to(beCloseTo(57.2, within: 1e-9))
        expect(dashes[2].rect.maxX).to(beCloseTo(90, within: 1e-9))
        // 첫 대시 [0, 22]는 첫 칸 안 — 둘째 칸으로 넘친 대시가 있는 표: 폭 20 칸
        let narrow = Self.row(
            Array(repeating: Self.borders(top: .shape(.longDotLine, 3)), count: 3), width: 20
        )
        let first = try XCTUnwrap(narrow.rows.first?.cells.first)
        let firstEdges = first.borders.edges(around: first.cellFrame, chains: first.borderChains)
        let overhang = try XCTUnwrap(firstEdges.first)
        expect(overhang.path.boundingBoxOfPath.maxX).to(beCloseTo(22, within: 1e-9))
        expect(overhang.band.maxX).to(beCloseTo(22, within: 1e-9))
        expect(first.paints(CGPoint(x: 21.5, y: 0))) == true
        // 둘째 칸 [20, 40)은 35.2에서 시작하는 대시를 맡고, 셋째 칸 [40, 60)은 맡을 자리가 없다
        // (다음 대시 70.4는 사슬 끝 60 뒤) — 셋째 칸 위 변은 경로가 없다
        expect(Self.elements(narrow).map(\.column).sorted()) == [0, 1]
    }

    /// 칸 변 모양이 이어 그리기 대상이 아니면 (실선·여러 줄·물결) 이음 자리가 없다 — 물결은 한글도
    /// 칸마다 다시 시작한다 (so238-main #17). 조각 하나뿐인 사슬도 싣지 않는다.
    func testOnlyDashesAndCirclesChain() {
        for shape: HwpBorderType in [.line, .doubleLine, .wave, .doubleWave, .thick3D] {
            let table = Self.row(Array(repeating: Self.borders(top: .shape(shape)), count: 3))
            expect(Self.unchained(table)) == true
        }
        let lone = Self.row([Self.borders(top: .circle())])
        expect(lone.rows[0].cells[0].borderChains) == HwpBorderChains.none
        let chained = Self.row([Self.borders(top: .circle()), Self.borders(top: .circle())])
        expect(chained.rows[0].cells.map { $0.borderChains.top != nil }) == [true, true]
    }

    // MARK: - 같은 격자선의 두 쪽

    /// 없는 쪽은 사슬을 끊지 않는다 — 다른 쪽 조각이 잇는다 (한글 F1: 위 [원, 없음, 원], 아래
    /// [없음, 원, 없음]이 한 간격). 양쪽 다 없으면 끊긴다 (F10).
    func testMissingSideIsBridgedByTheOtherSide() {
        let bridged = Self.twoRows(
            upper: [.circle(), .none, .circle()], lower: [.none, .circle(), .none]
        )
        expect(Self.circlesX(bridged, y: 20)) == Self.circleCenters(from: 0, 0 ..< 12)
        let broken = Self.twoRows(
            upper: [.circle(), .none, .none], lower: [.none, .none, .circle()]
        )
        expect(Self.circlesX(broken, y: 20))
            == Self.circleCenters(from: 0, 0 ..< 4) + Self.circleCenters(from: 60, 0 ..< 4)
    }

    /// 같은 모양의 다른 색(굵기)은 다른 쪽에 있어도 사슬을 끊는다 — 격자선의 "지금 사슬"이 그 조각으로
    /// 바뀌기 때문이다. 한글 F5: 위 [초록 ×3], 아래 [초록, 파랑, 초록] → 초록은 둘째 칸까지 잇고 셋째
    /// 칸에서 다시 시작한다. 거울(O1: 위 [초록, 파랑, 초록], 아래 [초록 ×3])은 위 칸 변을 먼저 보므로
    /// 초록이 **둘째 칸에서** 다시 시작해 셋째 칸으로 잇는다.
    func testSameShapeWithOtherColorBreaksTheChainInVisitOrder() {
        let blue = Side.circle(4, Self.blue)
        let green3: [Side] = [.circle(), .circle(), .circle()]
        let lowerBreak = Self.twoRows(upper: green3, lower: [.circle(), blue, .circle()])
        // 첫 칸은 두 쪽이 같은 원을 두 번 그린다 (한글도 두 번)
        let doubled = Self.circleCenters(from: 0, 0 ..< 4).flatMap { [$0, $0] }
        expect(Self.circlesX(lowerBreak, y: 20))
            == (doubled + Self.circleCenters(from: 0, 4 ..< 8)
                + Self.circleCenters(from: 60, 0 ..< 4).flatMap { [$0, $0] }).sorted()
        expect(Self.circlesX(lowerBreak, y: 20, color: Self.blue))
            == Self.circleCenters(from: 30, 0 ..< 4)

        let upperBreak = Self.twoRows(upper: [.circle(), blue, .circle()], lower: green3)
        expect(Self.circlesX(upperBreak, y: 20))
            == (doubled + Self.circleCenters(from: 30, 0 ..< 4)
                + Self.circleCenters(from: 30, 4 ..< 8).flatMap { [$0, $0] }).sorted()
        expect(Self.circlesX(upperBreak, y: 20, color: Self.blue))
            == Self.circleCenters(from: 30, 0 ..< 4)

        // 굵기가 달라도 같다 (O5)
        let thin = Side.circle(2)
        let widthBreak = Self.twoRows(upper: green3, lower: [.circle(), thin, .circle()])
        expect(Self.circlesX(widthBreak, y: 20).filter { $0 >= 60 })
            == Self.circleCenters(from: 60, 0 ..< 4).flatMap { [$0, $0] }
    }

    /// 모양이 다른 조각은 끊지 않는다 — 실선(F2)·다른 대시(O4)는 제 사슬을 따로 둔다
    func testOtherShapesDoNotBreakTheChain() {
        let solidInside = Self.twoRows(
            upper: [.circle(), .shape(.line, 1), .circle()],
            lower: [.circle(), .circle(), .circle()]
        )
        let circles = Self.circlesX(solidInside, y: 20)
        expect(Self.unique(circles)) == Self.circleCenters(from: 0, 0 ..< 12)
        let dashInside = Self.twoRows(
            upper: Array(repeating: .shape(.longDotLine, 3), count: 3),
            lower: [.shape(.longDotLine, 3), .shape(.dotLine, 3), .shape(.longDotLine, 3)]
        )
        let longDots = Self.elements(dashInside).filter { $0.rect.width > 10 }
        expect(Set(longDots.map { ($0.rect.minX * 100).rounded() / 100 })) == [0, 35.2, 70.4]
    }

    /// 뒤에 든 조각의 연장은 무늬 원점을 바꾸지 않는다 (O7: 아래 행 첫 칸만 왼 변이 있어도 원점은
    /// 먼저 본 위 행 조각의 시작 −0.12), 먼저 본 조각의 연장이면 원점이다 (F8: −1.44)
    func testOriginComesFromTheFirstVisitedPiece() {
        let lowerLeft = Self.table(
            widths: [30, 30], heights: [20, 20],
            cells: [
                Cell(0, 0, 1, 1, Self.borders(bottom: .circle())),
                Cell(0, 1, 1, 1, Self.borders(bottom: .circle())),
                Cell(1, 0, 1, 1, Self.borders(top: .circle(), left: .shape(.line))),
                Cell(1, 1, 1, 1, Self.borders(top: .circle())),
            ]
        )
        expect(Self.unique(Self.circlesX(lowerLeft, y: 20))) == Self.circleCenters(from: 0, 0 ..< 8)
        let upperLeft = Self.table(
            widths: [30, 30], heights: [20, 20],
            cells: [
                Cell(0, 0, 1, 1, Self.borders(bottom: .circle(), left: .shape(.line))),
                Cell(0, 1, 1, 1, Self.borders(bottom: .circle())),
                Cell(1, 0, 1, 1, Self.borders(top: .circle())),
                Cell(1, 1, 1, 1, Self.borders(top: .circle())),
            ]
        )
        expect(Self.unique(Self.circlesX(upperLeft, y: 20)))
            == Self.circleCenters(from: -2, 0 ..< 8)
    }

    // MARK: - 세로·병합·간격

    /// 세로 사슬도 같다 — 원·대시는 연장 없이 모서리에서 (so238-main #6·#25), 왼 열의 오른 변을 먼저
    /// 본다 (O2·O3)
    func testVerticalChainsContinueAndVisitTheLeftColumnFirst() {
        let column = Self.table(
            widths: [20], heights: [30, 30, 30],
            cells: (0 ..< 3).map { Cell($0, 0, 1, 1, Self.borders(left: .circle())) }
        )
        expect(Self.circlesY(column, x: 0)) == Self.circleCenters(from: 0, 0 ..< 12)
        // 위·아래 변이 있어도 세로 원은 연장 없이 모서리에서 (한글 so238-main #7: 위아래 파랑 1mm인
        // 3×1 왼 변 원형 점선의 첫 원 = 위 모서리)
        let walled = Self.table(
            widths: [20], heights: [30, 30, 30],
            cells: (0 ..< 3).map {
                Cell($0, 0, 1, 1, Self.borders(
                    top: .shape(.line), bottom: .shape(.line), left: .circle()
                ))
            }
        )
        expect(Self.circlesY(walled, x: 0)) == Self.circleCenters(from: 0, 0 ..< 12)
        let blue = Side.circle(4, Self.blue)
        let mirror = Self.table(
            widths: [20, 20], heights: [30, 30, 30],
            cells: [
                Cell(0, 0, 1, 1, Self.borders(right: .circle())),
                Cell(0, 1, 1, 1, Self.borders(left: .circle())),
                Cell(1, 0, 1, 1, Self.borders(right: blue)),
                Cell(1, 1, 1, 1, Self.borders(left: .circle())),
                Cell(2, 0, 1, 1, Self.borders(right: .circle())),
                Cell(2, 1, 1, 1, Self.borders(left: .circle())),
            ]
        )
        // 왼 열 파랑이 먼저라 오른 열 초록은 둘째 행에서 다시 시작해 셋째 행으로 잇는다
        expect(Self.unique(Self.circlesY(mirror, x: 20)))
            == Self.circleCenters(from: 0, 0 ..< 4) + Self.circleCenters(from: 30, 0 ..< 8)
    }

    /// 병합 칸의 변은 한 조각으로 사슬에 들고, 겹치는 쪽의 칸들도 같은 사슬에 든다 (so238-main
    /// #13·#15, F9·O8) — 다른 색 병합 칸은 끊는다 (O9)
    func testMergedCellsJoinAndBreakLikeAnyPiece() {
        let merged = Self.table(
            widths: [30, 30, 30], heights: [20, 20],
            cells: [
                Cell(0, 0, 1, 2, Self.borders(top: .circle(), bottom: .circle())),
                Cell(0, 2, 1, 1, Self.borders(top: .circle(), bottom: .circle())),
                Cell(1, 0, 1, 1, Self.borders(top: .circle())),
                Cell(1, 1, 1, 1, Self.borders(top: .circle())),
                Cell(1, 2, 1, 1, Self.borders(top: .circle())),
            ]
        )
        expect(Self.circlesX(merged, y: 0)) == Self.circleCenters(from: 0, 0 ..< 12)
        expect(Self.unique(Self.circlesX(merged, y: 20))) == Self.circleCenters(from: 0, 0 ..< 12)
        let blue = Side.circle(4, Self.blue)
        let breaking = Self.table(
            widths: [30, 30, 30], heights: [20, 20],
            cells: [
                Cell(0, 0, 1, 1, Self.borders(bottom: .circle())),
                Cell(0, 1, 1, 1, Self.borders(bottom: .circle())),
                Cell(0, 2, 1, 1, Self.borders(bottom: .circle())),
                Cell(1, 0, 1, 1, Self.borders(top: .circle())),
                Cell(1, 1, 1, 2, Self.borders(top: blue)),
            ]
        )
        // 먼저 든 긴 병합 조각 뒤에 짧은 조각이 겹쳐 들어도 사슬 끝 모서리는 줄지 않는다 — 짧은 조각은
        // 제 구간(0~30)의 원만 한 번 더 그린다
        let shorter = Self.table(
            widths: [30, 30], heights: [20, 20],
            cells: [
                Cell(0, 0, 1, 2, Self.borders(bottom: .circle())),
                Cell(1, 0, 1, 1, Self.borders(top: .circle())),
                Cell(1, 1, 1, 1, Self.borders()),
            ]
        )
        let twice = Self.circleCenters(from: 0, 0 ..< 4).flatMap { [$0, $0] }
        expect(Self.circlesX(shorter, y: 20)) == twice + Self.circleCenters(from: 0, 4 ..< 8)
        // 초록은 둘째 칸까지 잇고 셋째 칸(60)에서 다시 시작한다
        expect(Self.unique(Self.circlesX(breaking, y: 20)))
            == Self.circleCenters(from: 0, 0 ..< 8) + Self.circleCenters(from: 60, 0 ..< 4)
        expect(Self.circlesX(breaking, y: 20, color: Self.blue))
            == Self.circleCenters(from: 30, 0 ..< 8)
    }

    /// 칸 간격이 있으면 칸이 맞닿지 않아 잇지 않는다 — 1 HWPUNIT(0.01pt) 간격도 (so238-main #21)
    func testCellSpacingKeepsEdgesApart() {
        for spacing: CGFloat in [0.01, 2] {
            let table = Self.table(
                widths: [30, 30], heights: [20], spacing: spacing,
                cells: [
                    Cell(0, 0, 1, 1, Self.borders(top: .circle())),
                    Cell(0, 1, 1, 1, Self.borders(top: .circle())),
                ]
            )
            expect(Self.unchained(table)) == true
        }
    }

    /// 셀 간격을 실은 칸은 맞닿은 배치로 옮겨 와도 잇지 않는다 — 한글은 셀 간격이 있는 표의 변을
    /// 칸마다 상자로 그리므로 (#243) 사슬 자리가 상자의 모서리 규칙과 섞이면 안 된다
    func testSpacedCellBordersNeverChain() {
        let spaced = Self.borders(top: .circle())
        let boxed = HwpBorderSet(
            top: spaced.top, bottom: 0, left: 0, right: 0,
            topColor: spaced.topColor, bottomColor: spaced.bottomColor,
            leftColor: spaced.leftColor, rightColor: spaced.rightColor,
            topShape: spaced.topShape, bottomShape: .none, leftShape: .none, rightShape: .none,
            cellSpacing: 2
        )
        let touching = Self.row([boxed, boxed, boxed])
        expect(Self.unchained(touching)) == true
        // 칸마다 제 모서리에서 다시 시작한다 (점 무늬 간격 — 두께 4pt = 400HWPUNIT → q 49u, 간격
        // 49 + 74 = 123u = 14.76pt; 30pt 칸에 3개씩)
        let centers = Self.circlesX(touching, y: 0)
        expect(centers.count) == 9
        for (index, center) in centers.enumerated() {
            let cell = CGFloat(index / 3) * 30
            expect(center).to(beCloseTo(cell + CGFloat(index % 3) * 14.76, within: 1e-3))
        }
        // 셀 간격이 없는 같은 표는 잇는다 (대조군)
        expect(Self.unchained(Self.row([spaced, spaced, spaced]))) == false
    }

    // MARK: - 표 경계

    /// 이음 자리는 표가 셀 배치로 셈한다 — 다른 표로 옮긴 칸의 낡은 자리는 새 표가 버리고 다시 셈하고,
    /// 칸을 옮기는 사본(`offsetBy`)은 자리를 그대로 싣는다 (칸 모서리 기준이라 옮겨도 같다).
    func testTableFrameRecomputesChainsForItsOwnCells() throws {
        let table = Self.row(Array(repeating: Self.borders(top: .circle()), count: 3))
        let cells = table.rows[0].cells
        let chains = try XCTUnwrap(cells[1].borderChains.top)
        expect(chains.offset) == 30
        expect(chains.length) == 90
        expect(cells[1].offsetBy(deltaY: 50).borderChains) == cells[1].borderChains
        // 가운데 칸 하나만 새 표로 — 홀로 선 변이 된다
        let alone = HwpTableFrame(
            outerFrame: .zero, rows: [HwpTableRowFrame(rowFrame: .zero, cells: [cells[1]])],
            borderColor: Self.green, borderWidth: 1
        )
        expect(alone.rows[0].cells[0].borderChains) == HwpBorderChains.none
        expect(Self.circlesX(alone, y: 0)) == Self.circleCenters(from: 30, 0 ..< 4)
    }

    /// 쪽 조각(`HwpTableSplitter.segmentFrame`)마다 세로 사슬을 새로 셈한다 — 한글도 쪽 조각의 위
    /// 모서리에서 다시 시작한다 (so238-split: 둘째 쪽 첫 원 = 조각 위 모서리)
    func testPageSegmentsRestartVerticalChains() throws {
        let column = Self.table(
            widths: [20], heights: [30, 30, 30, 30],
            cells: (0 ..< 4).map { Cell($0, 0, 1, 1, Self.borders(left: .circle())) }
        )
        let segment = try XCTUnwrap(HwpTableSplitter.segmentFrame(
            rows: Array(column.rows[1...]), original: column, repeatedHeaderRows: []
        ))
        // 원래 표에서 둘째 행은 30부터 이어진 원(31.68·39.6·47.52·55.44)이었다
        expect(Self.circlesY(column, x: 0).filter { $0 >= 30 && $0 < 60 })
            == Self.circleCenters(from: 0, 4 ..< 8)
        expect(Self.circlesY(segment, x: 0)) == Self.circleCenters(from: 0, 0 ..< 12)
    }

    // MARK: - 히트 띠

    /// 이은 변의 띠는 제 몫이 칠한 곳(이웃 칸으로 넘친 원 포함)을 다 덮고, 칠하는 변의 띠는
    /// `edges(around:chains:)`의 띠와 같다. 제 몫의 요소가 없는 이은 변은 칠하지 않지만 선 위라
    /// 제 모서리 구간의 띠를 낸다 — 점선의 빈 자리도 띠로 치는 규약(`HwpTableCellFrame.paints`).
    func testBandsCoverOwnedPaintAndTheWholeEdgeLine() {
        // 폭 5 칸 여섯: 원 간격 7.92라 자리가 없는 칸이 생긴다
        let table = Self.row(Array(repeating: Self.borders(top: .circle()), count: 6), width: 5)
        var owning = 0
        for cell in table.rows[0].cells {
            let edges = cell.borders.edges(around: cell.cellFrame, chains: cell.borderChains)
            let bands = cell.borders.bands(around: cell.cellFrame, chains: cell.borderChains)
            expect(bands.count) == 1
            expect(edges.allSatisfy { bands.contains($0.band) }) == true
            for edge in edges {
                owning += 1
                let slack = edge.band.insetBy(dx: -1e-9, dy: -1e-9)
                expect(slack.contains(edge.path.boundingBoxOfPath)) == true
                for piece in HwpLineShapeGeometryTests.pieces(edge.path) {
                    expect(cell.paints(CGPoint(x: piece.maxX - 0.01, y: piece.midY))) == true
                }
            }
            // 제 몫이 있든 없든 제 모서리 구간의 선 위(원 띠 [−2.1, 2.1]) 탭은 그 칸을 가리키고, 띠
            // 밖은 아니다 (채움 없는 칸)
            expect(cell.paints(CGPoint(x: cell.cellFrame.midX, y: 1.5))) == true
            expect(cell.paints(CGPoint(x: cell.cellFrame.midX, y: -2.5))) == false
        }
        // 사슬 길이 30 → 원 0·7.92·15.84·23.76 — 칸 [0,5)·[5,10)·[15,20)·[20,25)만 자리를 맡는다
        expect(owning) == 4
        expect(Self.circlesX(table, y: 0)) == Self.circleCenters(from: 0, 0 ..< 4)
    }

    /// 히트 자격(`HwpHitTester.hitEligibleFrame`, `HwpHitCoverage`)도 같은 자리로 잰다 — 칸 28.5
    /// 둘의 사슬 [0, 57]은 끝 원 55.44가 반지름(2.1)만큼 57.54까지 넘친다. 칸마다 셈하면 끝 칸의 원은
    /// 54.36(28.5 + 23.76 + 2.1)에서 끝나 자격이 57에서 멈추고, 칠한 57.54까지를 덮지 못한다 (R54
    /// `자격 ⊇ 칠`).
    func testHitEligibilityUsesTheChainPlacement() {
        let table = Self.row(Array(repeating: Self.borders(top: .circle()), count: 2), width: 28.5)
        expect(Self.circlesX(table, y: 0).last) == Self.circleCenters(from: 0, 7 ..< 8).first
        let block = AnyHwpBlock(
            frame: CGRect(x: 0, y: 0, width: 57, height: 20), kind: .table, payload: .table(table)
        )
        expect(HwpHitTester().hitEligibleFrame(for: block).maxX) >= 55.44 + 2.1 - 1e-9
    }

    /// 사슬 끝은 든 조각의 연장 포함 끝 가운데 가장 먼 것이다 — 원점(첫 조각)과 달리 끝 모서리에
    /// 늦게 닿은 조각의 세로 변 연장도 사슬을 민다. 한글 12.30 실측(`probes/238/review`, 2×3 격자선
    /// 긴 점선 1mm): 끝 모서리의 세로 변이 위 칸에만·아래 칸에만·양쪽에 있거나, 위·아래 병합 칸이 먼저
    /// 끝 모서리에 닿아도 마지막 대시가 모서리 + 1.44(세로 변 1mm의 절반)까지 간다. 세로 변이 둘 다
    /// 없으면 한글은 NONE 변 폭(0.1mm) 연장만큼 + 0.12, 우리는 NONE 변을 폭 0으로 보아 모서리까지다
    /// (기존 격차).
    func testChainEndTakesTheFarthestExtension() {
        let wall = Side.shape(.line)
        func lastDashEnd(_ table: HwpTableFrame) -> CGFloat? {
            Self.elements(table)
                .filter { abs($0.rect.midY - 20) < 0.01 && $0.rect.width > 10 }
                .map(\.rect.maxX).max()
        }
        // 대시 22 · 공백 13.2 (주기 35.2): 셋째 대시 70.4가 사슬 끝에서 잘린다
        expect(lastDashEnd(Self.cornerGrid(upperRight: .none, lowerRight: wall))) == 92
        expect(lastDashEnd(Self.cornerGrid(upperRight: wall, lowerRight: .none))) == 92
        expect(lastDashEnd(Self.cornerGrid(upperRight: wall, lowerRight: wall))) == 92
        expect(lastDashEnd(Self.cornerGrid(upperRight: .none, lowerRight: .none))) == 90
        let mergedUpper = Self.cornerGrid(upperRight: .none, lowerRight: wall, mergeUpper: true)
        expect(lastDashEnd(mergedUpper)) == 92
        let mergedLower = Self.cornerGrid(upperRight: wall, lowerRight: .none, mergeLower: true)
        expect(lastDashEnd(mergedLower)) == 92
    }
}
