import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 셀 테두리 변 기하(`HwpBorderSet.edges`) — 한글 12.30.0 실측(#191)의 배치 규칙을 고정한다:
/// 선은 셀 모서리에 중심, 가로 변은 세로 변이 있는 끝만 그 폭의 절반 연장, 세로 변의
/// 실선·대시·원형은 연장 없음(물결만 가로 변 폭 절반 연장), 여러 줄은 모서리에서 겹상자,
/// `none`·폭 0은 그리지 않음. 히트 띠(`band`·`bands(around:)`)는 칠한 곳을 다 덮는다.
final class HwpBorderSetEdgeTests: XCTestCase {
    static let black = HwpRGBColor(red: 0, green: 0, blue: 0)
    static let rect = CGRect(x: 100, y: 200, width: 300, height: 50)

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

    /// 실선 네 변: 띠는 모서리 양쪽으로 폭의 절반, 가로 변은 양 끝의 세로 변 폭 절반만큼
    /// 연장, 세로 변은 셀 높이 그대로 (한글 실측: 5mm 위 테두리 x0 = 모서리 − 7.08pt, 왼
    /// 테두리 y0 = 모서리)
    func testSolidEdgesCenterOnCellEdgesAndHorizontalOnesExtend() {
        let edges = Self.set(top: 2, bottom: 2, left: 4, right: 4).edges(around: Self.rect)
        expect(edges.count) == 4
        let boxes = edges.map(\.path.boundingBoxOfPath)
        // 위 변: y 199~201, x 98~402 (왼·오른 변 폭 4의 절반씩 연장)
        expect(boxes[0]).to(equal(CGRect(x: 98, y: 199, width: 304, height: 2)))
        // 아래 변: y 249~251
        expect(boxes[1]).to(equal(CGRect(x: 98, y: 249, width: 304, height: 2)))
        // 왼 변: x 98~102, y 200~250 (연장 없음)
        expect(boxes[2]).to(equal(CGRect(x: 98, y: 200, width: 4, height: 50)))
        // 오른 변: x 398~402
        expect(boxes[3]).to(equal(CGRect(x: 398, y: 200, width: 4, height: 50)))
        // 히트 띠는 가로 변은 경로 상자와 같고, 세로 변은 이웃 가로 변 폭의 절반(1)만큼
        // 양 끝으로 넓다 (겹상자·물결이 그곳까지 칠한다) — `bands(around:)`도 같다
        expect(edges[0].band).to(equal(boxes[0]))
        expect(edges[1].band).to(equal(boxes[1]))
        expect(edges[2].band).to(equal(CGRect(x: 98, y: 199, width: 4, height: 52)))
        expect(edges[3].band).to(equal(CGRect(x: 398, y: 199, width: 4, height: 52)))
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
        // 원 하나도 안 들어가는 짧은 원형 변은 경로도 띠도 없다
        let tiny = Self.set(top: 4, topShape: .circle)
        let tinyRect = CGRect(x: 100, y: 200, width: 1, height: 50)
        expect(tiny.edges(around: tinyRect)).to(beEmpty())
        expect(tiny.bands(around: tinyRect)).to(beEmpty())
        // 칠한 곳을 다 담는 상자는 셀보다 테두리 바깥 절반만큼 크다
        expect(set.paintedBounds(around: Self.rect))
            .to(equal(CGRect(x: 98, y: 199, width: 304, height: 52)))
        expect(Self.set().paintedBounds(around: Self.rect)).to(equal(Self.rect))
    }

    /// 세로 변이 없는 끝은 연장하지 않는다 (한글 실측: 오른 테두리 없는 셀의 위 테두리는
    /// 오른 모서리에서 끝난다)
    func testHorizontalEdgeDoesNotExtendPastMissingVerticalEdge() {
        let edges = Self.set(top: 2, left: 4).edges(around: Self.rect)
        expect(edges.count) == 2
        expect(edges[0].path.boundingBoxOfPath)
            .to(equal(CGRect(x: 98, y: 199, width: 302, height: 2)))
        // `none` 모양은 폭이 있어도 없는 변이다
        let hidden = Self.set(top: 2, left: 4, right: 4, rightShape: .none).edges(around: Self.rect)
        expect(hidden.count) == 2
        expect(hidden[0].path.boundingBoxOfPath.maxX).to(beCloseTo(400, within: 0.001))
    }

    func testZeroWidthAndNoneEdgesAreSkipped() {
        expect(Self.set().edges(around: Self.rect)).to(beEmpty())
        expect(Self.set(top: 1, topShape: .none).edges(around: Self.rect)).to(beEmpty())
    }

    /// 2중선 위·왼 변은 모서리에서 겹상자를 이룬다 — 바깥 선은 모서리 −t/2에서, 안쪽 선은
    /// 모서리 +t/4에서 시작한다 (한글 실측: 1mm 2중선 위 변 x0 = 모서리 − 1.44 / + 0.72,
    /// 왼 변 y0 = 모서리 − 1.5 / + 0.66)
    func testDoubleLineCornersNest() {
        let edges = Self.set(top: 4, left: 4, topShape: .doubleLine, leftShape: .doubleLine)
            .edges(around: Self.rect)
        expect(edges.count) == 2
        let top = HwpLineShapeGeometryTests.pieces(edges[0].path)
        expect(top.count) == 2
        // 바깥(위) 가는 선: y 198~199, x 98~400 (오른 변 없음 → 끝은 모서리)
        expect(top[0]).to(equal(CGRect(x: 98, y: 198, width: 302, height: 1)))
        // 안쪽 가는 선: y 201~202, x 101~400
        expect(top[1]).to(equal(CGRect(x: 101, y: 201, width: 299, height: 1)))
        let left = HwpLineShapeGeometryTests.pieces(edges[1].path)
        expect(left.count) == 2
        // 바깥(왼) 선: x 98~99, y 198~250 (아래 변 없음 → 끝은 모서리)
        expect(left[0]).to(equal(CGRect(x: 98, y: 198, width: 1, height: 52)))
        // 안쪽 선: x 101~102, y 201~250
        expect(left[1]).to(equal(CGRect(x: 101, y: 201, width: 1, height: 49)))
    }

    /// 폭이 다른 변이 만나는 모서리: 세로 변의 부속선은 **이웃 가로 변** 폭의 절반을 기준으로
    /// 물러난다 (자기 폭 기준이면 왼 변 안쪽 선이 위 변 안쪽 선보다 아래에서 시작해 겹상자가
    /// 열린다) — 같은 모양이면 부속선이 서로 맞닿는다. 히트 띠는 바깥 선의 연장까지 담는다.
    func testUnequalWidthCornersNestAgainstTheNeighbourWidth() {
        let edges = Self.set(top: 2, left: 4, topShape: .doubleLine, leftShape: .doubleLine)
            .edges(around: Self.rect)
        let top = HwpLineShapeGeometryTests.pieces(edges[0].path)
        // 위 변(폭 2): 바깥 선 y 199~199.5는 왼 변 폭 절반(2) 연장 → x 98; 안쪽 선 y
        // 200.5~201은 바깥에서 1.5 물러난 몫을 왼 변 폭 비율(4/2)로 늘려 x 101 — 왼 변 안쪽
        // 선의 왼쪽과 같다
        expect(top[0]).to(equal(CGRect(x: 98, y: 199, width: 302, height: 0.5)))
        expect(top[1]).to(equal(CGRect(x: 101, y: 200.5, width: 299, height: 0.5)))
        let left = HwpLineShapeGeometryTests.pieces(edges[1].path)
        // 왼 변(폭 4): 바깥 선 x 98~99는 위 변 폭 절반(1) 연장 → y 199; 안쪽 선 x 101~102는
        // 바깥에서 3 물러난 몫을 위 변 폭 비율(2/4)로 줄여 y 200.5 — 위 변 안쪽 선의 위와 같다
        expect(left[0]).to(equal(CGRect(x: 98, y: 199, width: 1, height: 51)))
        expect(left[1]).to(equal(CGRect(x: 101, y: 200.5, width: 1, height: 49.5)))
        expect(edges[1].band).to(equal(CGRect(x: 98, y: 199, width: 4, height: 51)))
        expect(edges[1].band.contains(edges[1].path.boundingBoxOfPath)) == true
    }

    /// 아래·오른 변의 여러 줄은 순서가 위→아래·왼→오른으로 같고(한글 실측: 가는+굵은 아래
    /// 변도 가는 선이 위), 바깥쪽은 반대이므로 겹상자 물림이 뒤집힌다
    func testThinThickBottomEdgeKeepsTopToBottomOrder() {
        let edges = Self.set(
            bottom: 4, right: 4, bottomShape: .thinThickDoubleLine, rightShape: .line
        ).edges(around: Self.rect)
        let bottom = HwpLineShapeGeometryTests.pieces(edges[0].path)
        expect(bottom.count) == 2
        // 가는 선(위, 안쪽): y 248~249 — 바깥쪽에서 3t/4 = 3 물러나 x 100~399
        expect(bottom[0]).to(equal(CGRect(x: 100, y: 248, width: 299, height: 1)))
        // 굵은 선(아래, 바깥): y 250~252 — x 100~402
        expect(bottom[1]).to(equal(CGRect(x: 100, y: 250, width: 302, height: 2)))
    }

    /// 대시·물결 변은 연장 길이 전체를 한 경로로 그린다 — 띠 상자가 연장 범위와 같다
    func testPatternedEdgeCoversTheExtendedLength() {
        let edges = Self.set(top: 2, left: 2, right: 2, topShape: .dotLine).edges(around: Self.rect)
        let box = edges[0].path.boundingBoxOfPath
        expect(box.minX).to(beCloseTo(99, within: 0.001))
        expect(box.maxX).to(beCloseTo(401, within: 0.5)) // 마지막 대시는 패턴 위상에 따라 잘린다
        expect(edges[0].band).to(equal(CGRect(x: 99, y: 199, width: 302, height: 2)))
        let wave = Self.set(left: 4, leftShape: .wave).edges(around: Self.rect)
        // 왼 변 물결 띠: x 100 − 4 ~ 100 + 1 (−7/8·+1/8 두께 + 획 반폭 1/8); 세로 범위는 셀
        // 높이 50을 반주기 4.12로 채운 13개 대각선 끝 = 13 × 4.12 − 0.12 = 53.44 (마지막
        // 반주기를 끝까지 그린다)에 획 모서리 0.5/√2를 양 끝에 더한 것
        let corner = 0.5 / 2.0.squareRoot()
        expect(wave[0].band.minX).to(beCloseTo(96, within: 0.001))
        expect(wave[0].band.width).to(beCloseTo(5, within: 0.001))
        expect(wave[0].band.minY).to(beCloseTo(200 - corner, within: 0.001))
        expect(wave[0].band.maxY).to(beCloseTo(253.44 + corner, within: 0.001))
        expect(wave[0].band.contains(wave[0].path.boundingBoxOfPath.insetBy(dx: 0.001, dy: 0.001)))
            == true
    }

    /// 세로 물결 변은 가로 변이 있는 끝에서 **그 가로 변** 폭의 절반만큼 연장한 곳에서 시작한다
    /// (한글 4mm 실측: 위 테두리가 있는 왼 물결 변의 첫 꼭짓점이 모서리 − t/2) — 실선 세로
    /// 변과 다르고, 자기 폭이 아니라 이웃 폭이다
    func testVerticalWaveEdgeStartsAtTheExtendedCorner() {
        let corner = 0.5 / 2.0.squareRoot()
        let edges = Self.set(top: 4, left: 4, leftShape: .wave).edges(around: Self.rect)
        let left = HwpLineShapeGeometryTests.pieces(edges[1].path).filter { $0.height > 2 }
        // 첫 대각선은 y = 198(모서리 − 2)에서 시작한다 (45° 평행사변형 상자는 획 반폭/√2
        // 만큼 위로 나간다)
        expect(left.first?.minY).to(beCloseTo(198 - corner, within: 0.01))
        expect(edges[1].band.minY).to(beCloseTo(198 - corner, within: 0.001))
        // 위 변 폭 2 / 왼 변 폭 4: 왼 변 폭 절반(2)이 아니라 위 변 폭 절반(1)만큼 = 199
        let unequal = Self.set(top: 2, left: 4, leftShape: .wave).edges(around: Self.rect)
        let unequalLeft = HwpLineShapeGeometryTests.pieces(unequal[1].path).filter { $0.height > 2 }
        expect(unequalLeft.first?.minY).to(beCloseTo(199 - corner, within: 0.01))
        // 위 변이 없으면 모서리에서
        let alone = Self.set(left: 4, leftShape: .wave).edges(around: Self.rect)
        expect(alone[0].path.boundingBoxOfPath.minY).to(beCloseTo(200 - corner, within: 0.01))
        let solid = Self.set(top: 4, left: 4).edges(around: Self.rect)
        expect(solid[1].path.boundingBoxOfPath.minY).to(beCloseTo(200, within: 0.001))
    }

    /// `HwpTableLayout.borders(from:)`는 표 23의 네 방향 선 종류를 그대로 싣는다
    /// (왼·오른·위·아래 순서, 종류 0은 폭 0)
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
        expect(borders.bottom) == 0
        expect(borders.top).to(beCloseTo(0.12 * 72 / 25.4, within: 0.001))
    }
}
