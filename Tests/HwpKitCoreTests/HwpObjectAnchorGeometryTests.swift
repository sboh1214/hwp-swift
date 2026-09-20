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

    /// 세로는 줄 상자 모델이다 (#180·#195): 개체 **바깥 상자**를 그 높이의 글자로 보고 상자
    /// 상단에서 높이 × `objectBaselineRatio` 내려간 자리를 줄 베이스라인(상자 상단 +
    /// `baseline`)에 맞춘다. 한글 문서(0.85)의 40pt 줄(앵커 34)에 든 20pt 개체는 상자
    /// 상단 + 34 − 17 = +17 — 한글 12.30 실측(그림 상단 = 베이스라인 − 0.85 × 20)과 같고, 종전의
    /// "바닥을 베이스라인에"(+14)보다 3pt 아래다.
    func testInlineAnchorOriginPutsASmallObjectAtItsOwnBaselineRatio() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: CGPoint(x: 10, y: 20),
            line: line(origin: CGPoint(x: 3, y: 30), baseline: 34, ratio: 0.85),
            anchor: anchor(xOffset: 5, ascent: 20)
        )
        expect(origin.x) == 18 // 10 + 3 + 5
        expect(origin.y).to(beCloseTo(67, within: 0.001)) // 20 + 30 + (34 − 0.85 × 20)
    }

    /// 바깥 여백은 바깥 상자에 든다 — 20pt 그림 + 위 7·아래 3의 바깥 30pt 상자가 상자 상단 +
    /// 34 − 25.5 = +8.5에 놓이고, 그림은 `inlineObjectOrigin`이 7만큼 들인 +15.5다 (한글 실측:
    /// 그림 상단 = 베이스라인 − 18.5).
    func testInlineAnchorOriginTreatsTheOuterBoxAsTheGlyphBox() {
        let outer = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: .zero,
            line: line(origin: .zero, baseline: 34, ratio: 0.85),
            anchor: anchor(xOffset: 0, ascent: 30)
        )
        expect(outer.y).to(beCloseTo(8.5, within: 0.001))
        let object = HwpObjectAnchorGeometry.inlineObjectOrigin(
            outerBoxOrigin: outer, margins: .init(top: 7, bottom: 3)
        )
        expect(object.y).to(beCloseTo(15.5, within: 0.001))
    }

    /// MS 워드 호환 문서는 비율 1 — 바깥 상자 바닥이 베이스라인이다 (한글 실측: 함초롬돋움
    /// 40pt 줄의 20pt 그림 상단 = 베이스라인 − 20).
    func testInlineAnchorOriginPutsTheOuterBoxBottomOnTheBaselineForMsWord() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: .zero,
            line: line(origin: CGPoint(x: 0, y: 100), baseline: 50.64, ratio: 1),
            anchor: anchor(xOffset: 0, ascent: 20)
        )
        expect(origin.y).to(beCloseTo(130.64, within: 0.001))
    }

    /// 개체가 상자를 정한 줄(코퍼스의 전부)은 앵커 = 비율 × 개체 높이라 개체 상단이 곧 상자
    /// 상단이다 — 한글 문서(0.85 × 60 = 51)와 MS 워드 호환 문서(max(글꼴, 60) = 60) 모두.
    func testInlineAnchorOriginPinsATallObjectToTheLineBoxTop() {
        for (baseline, ratio) in [(CGFloat(0.85 * 60), CGFloat(0.85)), (60, 1)] {
            let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
                paragraphOrigin: CGPoint(x: 0, y: 100),
                line: line(origin: CGPoint(x: 0, y: 16), baseline: baseline, ratio: ratio),
                anchor: anchor(xOffset: 0, ascent: 60)
            )
            expect(origin.y).to(beCloseTo(116, within: 0.001), description: "비율 \(ratio)")
        }
    }

    /// 손으로 만든 줄 프레임이 앵커보다 큰 개체를 실어도 상자 상단 위로는 올리지 않는다 —
    /// 측정 줄 프레임은 `baseline` ≥ 비율 × 개체 높이라 이 가드에 걸리지 않는다.
    func testInlineAnchorOriginDoesNotRiseAboveTheLineBoxTop() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: .zero,
            line: line(origin: CGPoint(x: 0, y: 40), baseline: 12, ratio: 1),
            anchor: anchor(xOffset: 0, ascent: 20)
        )
        expect(origin.y) == 40
    }

    func testInlineAnchorOriginAtParagraphOriginWithZeroMetrics() {
        let origin = HwpObjectAnchorGeometry.inlineAnchorOrigin(
            paragraphOrigin: .zero,
            line: line(origin: .zero, baseline: 0, ratio: 0.85),
            anchor: anchor(xOffset: 0, ascent: 0)
        )
        expect(origin) == .zero
    }

    // MARK: 헬퍼

    /// 줄 프레임 — 원점·앵커·개체 비율만 뜻이 있다.
    private func line(origin: CGPoint, baseline: CGFloat, ratio: CGFloat) -> HwpLineFrame {
        HwpLineFrame(
            origin: origin, width: 100, baseline: baseline,
            attributedRange: NSRange(location: 0, length: 1), objectBaselineRatio: ratio
        )
    }

    /// 줄 앵커 — 바깥 상자 높이 `ascent`(pt)의 개체 마커.
    private func anchor(xOffset: CGFloat, ascent: CGFloat) -> HwpInlineAnchor {
        HwpInlineAnchor(controlIndex: 0, xOffset: xOffset, ascent: ascent, width: 20)
    }

    /// base 100 · extent 80 · size 20 고정 — 분기별 기대값이 100/130/160.
    private func aligned(
        alignment: CoreHwp.HwpCommonCtrlRelativeAlignment?
    ) -> CGFloat {
        HwpObjectAnchorGeometry.aligned(
            base: 100, extent: 80, size: 20, alignment: alignment
        )
    }
}
