import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// 개체 앵커 산식의 분기 핀 (#73).
///
/// 이 산식은 페이지 흐름 경로와 컨테이너 수집 경로가 **공유**한다. 종전에는
/// 두 곳에 같은 구현이 따로 있었고, 픽스처가 닿는 것은 `topOrLeft`/nil 분기뿐이라
/// 나머지 정렬 분기는 어느 게이트도 잡지 못했다 — 실제로 `.center` 분기를 1pt
/// 틀어도 블록 스냅샷과 렌더 해시가 모두 초록이었다. 공유 소유자로 합치면서
/// 그 구멍을 여기서 닫는다.
final class HwpObjectAnchorGeometryTests: XCTestCase {
    // MARK: aligned — 정렬 분기 전수

    func testTopOrLeftKeepsBase() {
        let value = aligned(alignment: .topOrLeft)
        expect(value) == 100
    }

    func testInsideKeepsBase() {
        let value = aligned(alignment: .inside)
        expect(value) == 100
    }

    func testNilAlignmentKeepsBase() {
        let value = aligned(alignment: nil)
        expect(value) == 100
    }

    /// base + (extent − size) / 2 — 픽스처가 닿지 않는 분기.
    func testCenterCentersWithinExtent() {
        let value = aligned(alignment: .center)
        expect(value) == 130
    }

    /// base + extent − size — 픽스처가 닿지 않는 분기.
    func testBottomOrRightPinsToFarEdge() {
        let value = aligned(alignment: .bottomOrRight)
        expect(value) == 160
    }

    func testOutsidePinsToFarEdge() {
        let value = aligned(alignment: .outside)
        expect(value) == 160
    }

    // MARK: extent 규칙

    /// extent가 0이면 정렬이 무효다 — 페이지 경로가 세로 기준 '문단'일 때
    /// extent 0을 넘겨 정렬을 끄는 것이 이 규칙에 기댄다.
    func testZeroExtentDisablesAlignment() {
        for alignment: CoreHwp.HwpCommonCtrlRelativeAlignment in
            [.center, .bottomOrRight, .outside, .topOrLeft, .inside]
        {
            let value = HwpObjectAnchorGeometry.aligned(
                base: 100, extent: 0, size: 20, alignment: alignment
            )
            expect(value) == 100
        }
    }

    func testNegativeExtentDisablesAlignment() {
        let value = HwpObjectAnchorGeometry.aligned(
            base: 100, extent: -50, size: 20, alignment: .center
        )
        expect(value) == 100
    }

    /// 개체가 여유 폭보다 크면 center는 base보다 앞으로 나간다 — 클램프하지
    /// 않는 것이 현재 동작이고, 흐름 경로가 따로 페이지 안으로 되돌린다.
    func testOversizedObjectIsNotClamped() {
        let value = HwpObjectAnchorGeometry.aligned(
            base: 100, extent: 40, size: 100, alignment: .center
        )
        expect(value) == 70
    }

    // MARK: inlineAnchorOrigin

    /// 세로는 줄 상자 모델이다 (#180): 개체 바닥을 그 줄의 베이스라인 앵커(상자 상단 +
    /// `lineBaseline`)에 두되, 개체가 앵커 위 공간보다 크면 상자 상단에 붙는다.
    func testInlineAnchorOriginPutsASmallObjectOnTheLineBaseline() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: CGPoint(x: 10, y: 20),
            lineBaseline: 12,
            lineOrigin: CGPoint(x: 3, y: 30),
            xOffset: 5,
            ascent: 9
        )
        expect(origin.x) == 18 // 10 + 3 + 5
        expect(origin.y) == 53 // 20 + 30 + (12 − 9)
    }

    /// 개체가 상자를 정한 줄(코퍼스의 전부)은 앵커 = 0.85 × 개체 높이 < 개체 높이라 개체
    /// 상단이 곧 상자 상단이다 — 렌더가 그 줄 글자를 그리는 자리와 같은 기준.
    func testInlineAnchorOriginPinsATallObjectToTheLineBoxTop() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: CGPoint(x: 0, y: 100),
            lineBaseline: 0.85 * 60,
            lineOrigin: CGPoint(x: 0, y: 16),
            xOffset: 0,
            ascent: 60
        )
        expect(origin.y) == 116
    }

    func testInlineAnchorOriginAtParagraphOriginWithZeroMetrics() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: .zero,
            lineBaseline: 0,
            lineOrigin: .zero,
            xOffset: 0,
            ascent: 0
        )
        expect(origin) == .zero
    }

    // MARK: 헬퍼

    /// base 100 · extent 80 · size 20 고정 — 분기별 기대값이 100/130/160.
    private func aligned(
        alignment: CoreHwp.HwpCommonCtrlRelativeAlignment?
    ) -> CGFloat {
        HwpObjectAnchorGeometry.aligned(
            base: 100, extent: 80, size: 20, alignment: alignment
        )
    }
}
