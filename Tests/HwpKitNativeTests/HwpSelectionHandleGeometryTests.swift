import CoreGraphics
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// 선택 핸들(#84)의 순수 기하 — 플랫폼 중립이라 양쪽 테스트 번들에서
/// 컴파일된다. iOS 잡은 커버리지를 수집하지 않으므로 이 산식들이
/// `#if os(iOS)` 밖에 사는 것이 codecov patch가 잡히는 유일한 길이다.
final class HwpSelectionHandleGeometryTests: XCTestCase {
    private let caret = CGRect(x: 120, y: 200, width: 0, height: 16)

    // MARK: - handleFrame

    /// 그립은 선택 **밖**을 향한다 — 시작은 위, 끝은 아래. 반대로 두면 두
    /// 핸들이 선택 안쪽에서 서로 겹쳐 짧은 선택을 잡을 수 없다.
    func testHandleFrameGrowsAwayFromTheSelection() {
        let diameter = HwpSelectionHandleGeometry.knobDiameter

        let start = HwpSelectionHandleGeometry.handleFrame(caretRect: caret, edge: .start)
        let end = HwpSelectionHandleGeometry.handleFrame(caretRect: caret, edge: .end)

        expect(start.maxY).to(beCloseTo(caret.maxY, within: 0.001))
        expect(start.minY).to(beCloseTo(caret.minY - diameter, within: 0.001))
        expect(end.minY).to(beCloseTo(caret.minY, within: 0.001))
        expect(end.maxY).to(beCloseTo(caret.maxY + diameter, within: 0.001))
    }

    func testHandleFrameCentersOnTheCaret() {
        let start = HwpSelectionHandleGeometry.handleFrame(caretRect: caret, edge: .start)

        expect(start.midX).to(beCloseTo(caret.midX, within: 0.001))
        expect(start.width) == HwpSelectionHandleGeometry.knobDiameter
        expect(start.height).to(
            beCloseTo(caret.height + HwpSelectionHandleGeometry.knobDiameter, within: 0.001)
        )
    }

    /// 캐럿 높이는 줌 배율을 타고 들어온다 (뷰가 `contentView.convert`로 옮긴
    /// rect를 준다) — 0.25x·5x 어느 쪽에서도 그립 지름은 그대로여야 한다.
    func testKnobSizeIsIndependentOfCaretHeight() {
        let tiny = HwpSelectionHandleGeometry.handleFrame(
            caretRect: CGRect(x: 10, y: 10, width: 0, height: 4), edge: .end
        )
        let huge = HwpSelectionHandleGeometry.handleFrame(
            caretRect: CGRect(x: 10, y: 10, width: 0, height: 80), edge: .end
        )

        expect(tiny.width) == huge.width
        expect(tiny.width) == HwpSelectionHandleGeometry.knobDiameter
    }

    // MARK: - handleParts

    func testHandlePartsPlaceTheKnobOutsideTheBar() {
        let bounds = CGRect(
            origin: .zero,
            size: HwpSelectionHandleGeometry
                .handleFrame(caretRect: caret, edge: .start).size
        )

        let start = HwpSelectionHandleGeometry.handleParts(in: bounds, edge: .start)
        let end = HwpSelectionHandleGeometry.handleParts(in: bounds, edge: .end)

        expect(start.knob.minY) == 0
        expect(start.bar.minY) == HwpSelectionHandleGeometry.knobDiameter
        expect(start.bar.maxY).to(beCloseTo(bounds.maxY, within: 0.001))
        expect(end.bar.minY) == 0
        expect(end.knob.maxY).to(beCloseTo(bounds.maxY, within: 0.001))
        expect(start.bar.midX).to(beCloseTo(bounds.midX, within: 0.001))
        expect(start.bar.width) == HwpSelectionHandleGeometry.barWidth
    }

    /// 캐럿보다 그립이 큰(짧은 줄) 경우에도 바 높이가 음수로 내려가지 않는다.
    func testHandlePartsClampDegenerateBounds() {
        let parts = HwpSelectionHandleGeometry.handleParts(
            in: CGRect(x: 0, y: 0, width: 11, height: 4), edge: .start
        )

        expect(parts.bar.height) == 0
        expect(parts.knob.height) == 11
    }

    // MARK: - caretCenter / grabOffset

    /// `handleFrame`의 역이 정확해야 그랩 순간 캐럿이 손가락으로 튀지 않는다.
    func testCaretCenterRoundTripsHandleFrame() {
        for edge in [HwpSelectionEdge.start, .end] {
            let frame = HwpSelectionHandleGeometry.handleFrame(
                caretRect: caret, edge: edge
            )

            let center = HwpSelectionHandleGeometry.caretCenter(
                handleFrame: frame, edge: edge
            )

            expect(center.x).to(beCloseTo(caret.midX, within: 0.001))
            expect(center.y).to(beCloseTo(caret.midY, within: 0.001))
        }
    }

    func testGrabOffsetKeepsTheCaretWhereItWas() {
        let touch = CGPoint(x: 118, y: 214)

        let offset = HwpSelectionHandleGeometry.grabOffset(
            caretCenter: CGPoint(x: caret.midX, y: caret.midY), touchPoint: touch
        )
        let restored = HwpSelectionHandleGeometry.caretPoint(
            touchPoint: touch, grabOffset: offset
        )

        expect(restored.x).to(beCloseTo(caret.midX, within: 0.001))
        expect(restored.y).to(beCloseTo(caret.midY, within: 0.001))
    }

    func testGrabOffsetTranslatesWithTheFinger() {
        let offset = HwpSelectionHandleGeometry.grabOffset(
            caretCenter: CGPoint(x: 100, y: 100), touchPoint: CGPoint(x: 100, y: 110)
        )

        let moved = HwpSelectionHandleGeometry.caretPoint(
            touchPoint: CGPoint(x: 140, y: 160), grabOffset: offset
        )

        expect(moved.x) == 140
        expect(moved.y) == 150
    }

    // MARK: - isWithinGrabArea

    func testGrabAreaIsWiderThanTheDrawnHandle() {
        let bounds = CGRect(x: 0, y: 0, width: 11, height: 27)
        let margin = HwpSelectionHandleGeometry.grabMargin

        expect(HwpSelectionHandleGeometry.isWithinGrabArea(
            CGPoint(x: 5, y: 13), bounds: bounds
        )) == true
        // 그리는 영역 밖이지만 여유 안 — 손가락 굵기를 감안해 잡힌다
        expect(HwpSelectionHandleGeometry.isWithinGrabArea(
            CGPoint(x: -margin + 1, y: 13), bounds: bounds
        )) == true
        // 여유 밖 — 잡히지 않는다 (여기까지 삼키면 본문 탭·롱프레스가 죽는다)
        expect(HwpSelectionHandleGeometry.isWithinGrabArea(
            CGPoint(x: -margin - 1, y: 13), bounds: bounds
        )) == false
        expect(HwpSelectionHandleGeometry.isWithinGrabArea(
            CGPoint(x: 5, y: bounds.maxY + margin + 1), bounds: bounds
        )) == false
    }

    // MARK: - isCaretVisible

    /// 캐럿은 정의상 폭 0이고, 빈 rect에 대한 `CGRect.intersects`의 계약은
    /// 문서화돼 있지 않다 (`isEmpty`가 true인 rect다) — 그래서 판정을 명시
    /// 산식으로 들고 있는다. 경계 정책도 여기서 고정한다: 뷰포트 가장자리에
    /// 정확히 걸친 캐럿은 **보이는 것**으로 본다.
    func testCaretVisibilityDoesNotRideOnEmptyRectSemantics() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 800)
        let onRightEdge = CGRect(x: 390, y: 200, width: 0, height: 16)

        expect(self.caret.isEmpty) == true
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: self.caret, in: viewport
        )) == true
        // 오른쪽 끝에 정확히 걸친 캐럿에서 두 판정이 갈린다
        expect(viewport.intersects(onRightEdge)) == false
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: onRightEdge, in: viewport
        )) == true
    }

    func testCaretOutsideTheViewportIsHidden() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 800)

        // 위로 완전히 벗어남 / 아래로 완전히 벗어남
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: CGRect(x: 100, y: -40, width: 0, height: 16), in: viewport
        )) == false
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: CGRect(x: 100, y: 800, width: 0, height: 16), in: viewport
        )) == false
        // 가로로 벗어남 (확대해서 좌우로 민 상태)
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: CGRect(x: -1, y: 100, width: 0, height: 16), in: viewport
        )) == false
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: CGRect(x: 391, y: 100, width: 0, height: 16), in: viewport
        )) == false
        // 위쪽 절반만 걸친 캐럿은 보인다
        expect(HwpSelectionHandleGeometry.isCaretVisible(
            caretRect: CGRect(x: 100, y: -8, width: 0, height: 16), in: viewport
        )) == true
    }
}
