import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 셀 테두리 변 기하(`HwpBorderSet.edges`) — 한글 12.30.0 실측(#191·#246·#253)의 배치 규칙을 고정한다:
/// 선은 셀 모서리에 중심, 단선 가로 변은 이웃 세로 변(선 없음도 저장된 굵기로) 획의 절반 연장, 단선
/// 세로 변은 연장 없음, 여러 줄·물결은 이웃이 같은 모양·굵기면 맞물리고 다르면 가로 변은 나가고
/// 세로 변은 물러남, `none`·폭 0은 그리지 않음. 히트 띠(`band`·`bands(around:)`)는 칠한 곳을 다
/// 덮는다. 표 격자의 모서리 맥락은 `HwpBorderCornerTests`가 본다.
final class HwpBorderSetEdgeTests: XCTestCase {
    static let black = HwpRGBColor(red: 0, green: 0, blue: 0)
    static let rect = CGRect(x: 100, y: 200, width: 300, height: 50)
    /// 폭 2pt 실선의 획 — 한글처럼 장치 단위로 반올림한다 (200HWPUNIT → round(16.7) = 17u, #245).
    /// 모서리에서 이웃 변이 나가는 길이도 이 획의 절반이다 (`HwpBorderSet.reachWidth`).
    static let stroke2: CGFloat = 17 * 0.12
    /// 폭 4pt 실선의 획 (400HWPUNIT → round(33.3) = 33u)
    static let stroke4: CGFloat = 33 * 0.12

    static func set(
        top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0,
        topShape: HwpBorderType = .line, bottomShape: HwpBorderType = .line,
        leftShape: HwpBorderType = .line, rightShape: HwpBorderType = .line
    ) -> HwpBorderSet {
        HwpBorderSet(
            top: top, bottom: bottom, left: left, right: right,
            topColor: black, bottomColor: black, leftColor: black, rightColor: black,
            topShape: topShape, bottomShape: bottomShape,
            leftShape: leftShape, rightShape: rightShape
        )
    }

    /// 실선 네 변: 띠는 모서리 양쪽으로 획의 절반, 가로 변은 양 끝의 세로 변 획 절반만큼
    /// 연장, 세로 변은 셀 높이 그대로 (한글 실측: 5mm 위 테두리 x0 = 모서리 − 7.08pt, 왼
    /// 테두리 y0 = 모서리). 획은 장치 단위로 반올림한 두께다 (`stroke2`·`stroke4`).
    func testSolidEdgesCenterOnCellEdgesAndHorizontalOnesExtend() throws {
        let (thin, wide) = (Self.stroke2, Self.stroke4)
        let edges = Self.set(top: 2, bottom: 2, left: 4, right: 4).edges(around: Self.rect)
        expect(edges.count) == 4
        let boxes = edges.map(\.path.boundingBoxOfPath)
        // 위 변: y 200 ± thin/2, x 100 − wide/2 ~ 400 + wide/2 (왼·오른 변 획의 절반씩 연장)
        let top = CGRect(x: 100 - wide / 2, y: 200 - thin / 2, width: 300 + wide, height: thin)
        expect(boxes[0]).to(beCloseTo(top))
        // 아래 변: y 250 ± thin/2
        expect(boxes[1]).to(beCloseTo(top.offsetBy(dx: 0, dy: 50)))
        // 왼 변: x 100 ± wide/2, y 200~250 (연장 없음)
        let left = CGRect(x: 100 - wide / 2, y: 200, width: wide, height: 50)
        expect(boxes[2]).to(beCloseTo(left))
        // 오른 변: x 400 ± wide/2
        expect(boxes[3]).to(beCloseTo(left.offsetBy(dx: 300, dy: 0)))
        // 히트 띠는 가로 변은 경로 상자와 같고, 세로 변은 이웃 가로 변 획의 절반(thin/2)만큼
        // 양 끝으로 넓다 (겹상자·물결이 그곳까지 칠한다) — `bands(around:)`도 같다
        expect(edges[0].band).to(beCloseTo(boxes[0]))
        expect(edges[1].band).to(beCloseTo(boxes[1]))
        let leftBand = CGRect(x: 100 - wide / 2, y: 200 - thin / 2, width: wide, height: 50 + thin)
        expect(edges[2].band).to(beCloseTo(leftBand))
        expect(edges[3].band).to(beCloseTo(leftBand.offsetBy(dx: 300, dy: 0)))
        let set = Self.set(top: 2, bottom: 2, left: 4, right: 4)
        expect(set.bands(around: Self.rect)).to(equal(edges.map(\.band)))
        // 모양이 달라도 `bands(around:)`는 `edges(around:)`의 띠와 같고 경로를 다 덮는다
        let mixed = Self.set(
            top: 3, bottom: 3, left: 4, right: 4, topShape: .doubleWave, bottomShape: .circle,
            leftShape: .circle, rightShape: .dashDot
        )
        let mixedEdges = mixed.edges(around: Self.rect)
        expect(mixed.bands(around: Self.rect)).to(equal(mixedEdges.map(\.band)))
        for edge in mixedEdges {
            expect(edge.band.insetBy(dx: -0.001, dy: -0.001).contains(edge.path.boundingBoxOfPath))
                == true
        }
        // 원 하나 들어갈 자리가 없는 짧은 원형 변도 첫 원(중심 = 선 시작)은 그린다 — 표 셀 테두리의
        // 원도 끝 규칙이다 (#238: 중심 < 선 끝이면 끝을 넘어도 그린다). 띠는 그 원을 담는다.
        let tiny = Self.set(top: 4, topShape: .circle)
        let tinyRect = CGRect(x: 100, y: 200, width: 1, height: 50)
        let tinyEdges = tiny.edges(around: tinyRect)
        expect(tinyEdges.count) == 1
        // 두께 4pt 원: 칠 지름 35u = 4.2 (#239 — 경로 34u + 윤곽 1u)
        let tinyCircle = try XCTUnwrap(tinyEdges.first?.path.boundingBoxOfPath)
        expect(tinyCircle.minX).to(beCloseTo(97.9, within: 1e-9))
        expect(tinyCircle.minY).to(beCloseTo(197.9, within: 1e-9))
        expect(tinyCircle.width).to(beCloseTo(4.2, within: 1e-9))
        expect(tinyCircle.height).to(beCloseTo(4.2, within: 1e-9))
        expect(tiny.bands(around: tinyRect)).to(equal(tinyEdges.map(\.band)))
        expect(tinyEdges.first?.band.insetBy(dx: -1e-9, dy: -1e-9).contains(tinyCircle)) == true
        // 칠한 곳을 다 담는 상자는 셀보다 테두리 바깥 절반만큼 크다
        expect(set.paintedBounds(around: Self.rect)).to(beCloseTo(CGRect(
            x: 100 - wide / 2, y: 200 - thin / 2, width: 300 + wide, height: 50 + thin
        )))
        expect(Self.set().paintedBounds(around: Self.rect)).to(equal(Self.rect))
    }

    /// 굵기 0인 세로 변 쪽 끝은 연장하지 않고, 선 없음(`none`) 세로 변은 그리지 않지만 저장된 굵기의
    /// 절반만큼 가로 변을 연장한다 (#246 한글 실측: 선 없음 0.5·2·5mm 이웃 옆 실선 위 변이 0.68·2.72·
    /// 7.04pt 나간다 — `so246-single`)
    func testHorizontalEdgeExtendsByTheStoredWidthOfANoneVerticalEdge() {
        let edges = Self.set(top: 2, left: 4).edges(around: Self.rect)
        expect(edges.count) == 2
        expect(edges[0].path.boundingBoxOfPath).to(beCloseTo(CGRect(
            x: 100 - Self.stroke4 / 2, y: 200 - Self.stroke2 / 2,
            width: 300 + Self.stroke4 / 2, height: Self.stroke2
        )))
        let hidden = Self.set(top: 2, left: 4, right: 4, rightShape: .none).edges(around: Self.rect)
        expect(hidden.count) == 2
        expect(hidden[0].path.boundingBoxOfPath.maxX)
            .to(beCloseTo(400 + Self.stroke4 / 2, within: 0.001))
        // 세로 변은 선 없음 이웃 쪽에서 모서리에 머문다
        let vertical = Self.set(top: 4, left: 2, topShape: .none).edges(around: Self.rect)
        expect(vertical.count) == 1
        expect(vertical[0].path.boundingBoxOfPath.minY).to(beCloseTo(200, within: 0.001))
    }

    func testZeroWidthAndNoneEdgesAreSkipped() {
        expect(Self.set().edges(around: Self.rect)).to(beEmpty())
        expect(Self.set(top: 1, topShape: .none).edges(around: Self.rect)).to(beEmpty())
    }

    /// 2중선 위·왼 변은 모서리에서 겹상자를 이룬다 — 부속선은 장치 단위 행 [−2w, −w)·[w, 2w)이고 (B =
    /// 같은 굵기 실선의 획, w = round(B/4)), 바깥 선은 이웃 띠의 먼 가장자리 −2w에서, 안쪽 선은 이웃 안쪽
    /// 부속선의 먼 가장자리 +w에서 시작한다 (#246·#253 — 한글 실측: 1mm(B 24u, w 6u) 위 변 x0 = 모서리 −
    /// 1.44 / + 0.72). 4pt: 400HWPUNIT → B 33u, w 8u — 행 [−16, −8)·[8, 16)u = ±[0.96, 1.92]pt.
    func testDoubleLineCornersNest() {
        let edges = Self.set(top: 4, left: 4, topShape: .doubleLine, leftShape: .doubleLine)
            .edges(around: Self.rect)
        expect(edges.count) == 2
        let top = HwpLineShapeGeometryTests.pieces(edges[0].path)
        expect(top.count) == 2
        // 바깥(위) 가는 선: y 198.08~199.04, x 98.08~400 (오른 변 없음 → 끝은 모서리)
        expect(top[0]).to(beCloseTo(CGRect(x: 98.08, y: 198.08, width: 301.92, height: 0.96)))
        // 안쪽 가는 선: y 200.96~201.92, x 100.96~400
        expect(top[1]).to(beCloseTo(CGRect(x: 100.96, y: 200.96, width: 299.04, height: 0.96)))
        let left = HwpLineShapeGeometryTests.pieces(edges[1].path)
        expect(left.count) == 2
        // 바깥(왼) 선: x 98.08~99.04, y 198.08~250 (아래 변 없음 → 끝은 모서리)
        expect(left[0]).to(beCloseTo(CGRect(x: 98.08, y: 198.08, width: 0.96, height: 51.92)))
        // 안쪽 선: x 100.96~101.92, y 200.96~250
        expect(left[1]).to(beCloseTo(CGRect(x: 100.96, y: 200.96, width: 0.96, height: 49.04)))
    }

    /// 굵기가 다른 2중선이 만나는 모서리는 맞물리지 않는다 (#246 한글 실측 `so246-multi` sameB2·
    /// `junction` #31): 이웃 획 B를 모서리에 놓인 행 [−⌊B/2⌋, ⌈B/2⌉)로 보고, 가로 변은 부속선 모두 그 행의
    /// 앞 가장자리 ⌊B/2⌋ 앞에서 시작하고, 세로 변은 부속선 모두 행 뒤 가장자리 ⌈B/2⌉ 뒤에서 시작한다 (#253
    /// `so253-ends`·`so246-multi` — 겹상자 없음). 히트 띠는 이웃이 그리는 폭의 절반까지 넓다.
    func testUnequalWidthCornersDoNotNest() {
        let edges = Self.set(top: 2, left: 4, topShape: .doubleLine, leftShape: .doubleLine)
            .edges(around: Self.rect)
        let top = HwpLineShapeGeometryTests.pieces(edges[0].path)
        // 위 변(폭 2: B 17u, w 4u → 행 ±[4, 8)u): 두 부속선 모두 왼 변 획(4pt = 33u)의 ⌊33/2⌋ = 16u 앞,
        // x 98.08
        let span = (x: 100 - 16 * 0.12, width: 300 + 16 * 0.12)
        expect(top[0]).to(beCloseTo(CGRect(x: span.x, y: 199.04, width: span.width, height: 0.48)))
        expect(top[1]).to(beCloseTo(CGRect(x: span.x, y: 200.48, width: span.width, height: 0.48)))
        let left = HwpLineShapeGeometryTests.pieces(edges[1].path)
        // 왼 변(폭 4): 두 부속선 모두 위 변 획(2pt = 17u)의 ⌈17/2⌉ = 9u 뒤, y 201.08 — 아래 변은 굵기 0
        let rows = (y: 200 + 9 * 0.12, height: 50 - 9 * 0.12)
        func stripe(_ x: CGFloat) -> CGRect {
            CGRect(x: x, y: rows.y, width: 0.96, height: rows.height)
        }
        expect(left[0]).to(beCloseTo(stripe(98.08)))
        expect(left[1]).to(beCloseTo(stripe(100.96)))
        // 히트 띠: 위로 위 변 2중선이 그리는 폭(±0.96)의 절반 0.96만큼
        expect(edges[1].band).to(beCloseTo(CGRect(x: 98.08, y: 199.04, width: 3.84, height: 50.96)))
        expect(edges[1].band.contains(edges[1].path.boundingBoxOfPath)) == true
    }

    /// 아래·오른 변의 여러 줄도 순서는 위→아래·왼→오른이다 (한글 실측: 가는+굵은 아래 변도 가는 선이
    /// 위). 이웃 오른 변이 실선이라 모양이 달라 겹상자 없이 부속선 모두 그 획(33u)의 행 끝 ⌈33/2⌉ − 1 =
    /// 16u까지 나간다 (#246·#253 — 한글은 끝을 이웃 행의 마지막 장치 칸에서 멈춘다).
    func testThinThickBottomEdgeKeepsTopToBottomOrder() {
        let edges = Self.set(
            bottom: 4, right: 4, bottomShape: .thinThickDoubleLine, rightShape: .line
        ).edges(around: Self.rect)
        let bottom = HwpLineShapeGeometryTests.pieces(edges[0].path)
        expect(bottom.count) == 2
        let reach: CGFloat = 16 * 0.12
        // B 33u: 가는 선 행 [−16, −8)u (y 248.08~249.04), 굵은 선 행 [0, 17)u — 홀수 폭이라 획은 중심 8u에
        // 반 칸 위 (y 249.94~251.98) — 둘 다 x 100 ~ 400 + reach
        expect(bottom[0]).to(beCloseTo(CGRect(x: 100, y: 248.08, width: 300 + reach, height: 0.96)))
        expect(bottom[1]).to(beCloseTo(CGRect(x: 100, y: 249.94, width: 300 + reach, height: 2.04)))
    }

    /// 대시·물결 변은 연장 길이 전체를 한 경로로 그린다 — 띠 상자가 연장 범위와 같다
    func testPatternedEdgeCoversTheExtendedLength() {
        let edges = Self.set(top: 2, left: 2, right: 2, topShape: .dotLine).edges(around: Self.rect)
        let box = edges[0].path.boundingBoxOfPath
        let reach = Self.stroke2 / 2
        expect(box.minX).to(beCloseTo(100 - reach, within: 1e-9))
        // 2pt 격자 점선은 점 24u·공백 36u(#245) — 선 길이 302.04pt에 주기 7.2pt가 41번 들고 마지막
        // 대시(2.88pt)가 다 들어가 397.06에서 끝난다 (다음 대시는 선 끝 401.02 뒤에서 시작한다)
        expect(box.maxX).to(beCloseTo(100 - reach + 295.2 + 2.88, within: 1e-9))
        expect(edges[0].band).to(beCloseTo(CGRect(
            x: 100 - reach, y: 200 - reach, width: 300 + Self.stroke2, height: Self.stroke2
        )))
        let wave = Self.set(left: 4, leftShape: .wave).edges(around: Self.rect)
        // 왼 변 물결 띠 (4pt: B 33u, 획 8u, 위 평탄 −28u — 홀수 B라 대각선이 −29u까지): x 100 − 3.96 ~ 100 +
        // 1.08 (대각선 중심 [−29, 5]u에 획 반폭 4u); 세로 범위는 셀 높이 50을 반주기 34u = 4.08로 채운 13개
        // 대각선 끝 = 12 × 4.08 + 3.96 = 52.92 (마지막 반주기를 끝까지 그린다)에 획 모서리 0.48/√2를 양 끝에
        // 더한 것
        let corner = 0.48 / 2.0.squareRoot()
        expect(wave[0].band.minX).to(beCloseTo(96.04, within: 1e-9))
        expect(wave[0].band.width).to(beCloseTo(5.04, within: 1e-9))
        expect(wave[0].band.minY).to(beCloseTo(200 - corner, within: 1e-9))
        expect(wave[0].band.maxY).to(beCloseTo(252.92 + corner, within: 1e-9))
        expect(wave[0].band.contains(wave[0].path.boundingBoxOfPath.insetBy(dx: 0.001, dy: 0.001)))
            == true
    }

    /// 세로 물결 변은 이웃 가로 변이 다른 모양이면 그 획의 행 [−⌊B/2⌋, ⌈B/2⌉) 뒤에서 시작한다 (#246·#253
    /// 한글 실측 `so246-multi`·`so253-ends`: 2mm 실선(47u) 이웃 옆 1mm 물결 왼 변의 첫 대각선이 모서리 + 24u =
    /// 2.88) — 자기 폭이 아니라 이웃 폭이고, 이웃이 없으면 모서리에서다. 같은 물결 이웃이면 파마다 2중선
    /// 부속선처럼 물린다 (`HwpBorderCornerTests.testSameWaveCornersShiftTheWholeEdge`).
    func testVerticalWaveEdgeStartsInsideADifferentNeighbour() {
        let corner = 0.48 / 2.0.squareRoot()

        func firstDiagonalTop(_ edge: HwpBorderSet.EdgeGeometry) -> CGFloat? {
            HwpLineShapeGeometryTests.pieces(edge.path).filter { $0.height > 2 }.map(\.minY).min()
        }
        let edges = Self.set(top: 4, left: 4, leftShape: .wave).edges(around: Self.rect)
        // 첫 대각선은 모서리 + ⌈33/2⌉ = 17u(2.04)에서 시작한다 (45° 평행사변형 상자는 획 반폭/√2 만큼 위로
        // 나간다)
        expect(firstDiagonalTop(edges[1])).to(beCloseTo(202.04 - corner, within: 1e-9))
        // 히트 띠는 이웃이 그리는 폭의 절반까지 모서리 밖을 담는다
        expect(edges[1].band.minY).to(beCloseTo(200 - Self.stroke4 / 2, within: 0.001))
        // 위 변 폭 2 / 왼 변 폭 4: 왼 변 폭이 아니라 위 변 획(2pt = 17u)의 ⌈17/2⌉ = 9u(1.08)만큼
        let unequal = Self.set(top: 2, left: 4, leftShape: .wave).edges(around: Self.rect)
        expect(firstDiagonalTop(unequal[1])).to(beCloseTo(201.08 - corner, within: 1e-9))
        // 위 변이 없으면 모서리에서
        let alone = Self.set(left: 4, leftShape: .wave).edges(around: Self.rect)
        expect(alone[0].path.boundingBoxOfPath.minY).to(beCloseTo(200 - corner, within: 1e-9))
        let solid = Self.set(top: 4, left: 4).edges(around: Self.rect)
        expect(solid[1].path.boundingBoxOfPath.minY).to(beCloseTo(200, within: 0.001))
    }

    /// `HwpTableLayout.borders(from:)`는 표 23의 네 방향 선 종류·굵기를 그대로 싣는다
    /// (왼·오른·위·아래 순서, 종류 0도 굵기를 싣는다)
    func testBordersFromBorderFillCarryShapes() throws {
        // 표 23 payload: 속성 u16 + 네 방향 (종류 u8, 굵기 u8, 색 u32) + 대각선 + 채움
        var payload = Data([0, 0])
        for (type, thickness) in [(UInt8(2), UInt8(1)), (12, 1), (8, 1), (0, 1)] {
            payload.append(contentsOf: [type, thickness, 0, 0, 0, 0])
        }
        payload.append(contentsOf: [0, 0, 0, 0, 0, 0])
        let fill = try CoreHwp.HwpBorderFill.load(payload)
        let borders = HwpTableLayout().borders(from: fill)
        expect(borders.leftShape) == HwpBorderType.longDotLine
        expect(borders.rightShape) == HwpBorderType.wave
        expect(borders.topShape) == HwpBorderType.doubleLine
        expect(borders.bottomShape) == HwpBorderType.none
        // 선 없음도 저장된 굵기(0.12mm)를 싣는다 — 한글은 그 굵기로 모서리를 셈한다 (#246)
        expect(borders.bottom).to(beCloseTo(0.12 * 72 / 25.4, within: 0.001))
        expect(borders.top).to(beCloseTo(0.12 * 72 / 25.4, within: 0.001))
    }
}
