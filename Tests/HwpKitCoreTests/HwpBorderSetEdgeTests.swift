import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 셀 테두리 변 기하(`HwpBorderSet.edges`) — 한글 12.30.0 실측(#191)의 배치 규칙을 고정한다:
/// 선은 셀 모서리에 중심, 가로 변은 세로 변이 있는 끝만 그 폭의 절반 연장, 세로 변은
/// 연장 없음, 여러 줄은 모서리에서 겹상자, `none`·폭 0은 그리지 않음.
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
        // 히트 띠는 경로 상자와 같다
        expect(edges.map(\.band)).to(equal(boxes))
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
        // 왼 변 물결 띠: x 100 − 4 ~ 100 + 1 (−7/8·+1/8 두께 + 획 반폭 1/8)
        expect(wave[0].band).to(equal(CGRect(x: 96, y: 200, width: 5, height: 50)))
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
