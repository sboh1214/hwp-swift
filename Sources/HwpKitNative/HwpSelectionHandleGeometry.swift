import CoreGraphics
import HwpKitCore

/// 선택 핸들(#84)의 순수 기하 — 캐럿 rect ↔ 핸들 프레임, 그랩 판정, 가시 판정.
///
/// `#if os(iOS)` **밖**에 둔다. iOS 잡은 `xcodebuild test`만 돌고 커버리지를
/// 수집하지 않으므로(`--enable-code-coverage`와 codecov 업로드는 macOS 잡
/// 소속), iOS 가드 안에만 사는 산식은 codecov patch에 아예 잡히지 않는다.
/// `HwpDocumentViewSupport.effectiveContentsScale`와 같은 틀이다.
///
/// **줌 역보정 산식이 여기 없는 것은 의도다.** 핸들은 줌 대상(`contentView`)의
/// 서브뷰가 아니라 스크롤 뷰의 **형제**라 배율 transform을 물려받지 않는다 —
/// 페이지 로컬 rect를 `contentView.convert(_:to:)`로 옮기면 UIKit이 배율을
/// 반영해 주고, 남는 것은 아래의 순수 배치뿐이다.
enum HwpSelectionHandleGeometry {
    /// 그립(동그란 손잡이) 지름.
    static let knobDiameter: CGFloat = 11
    /// 캐럿 바 두께.
    static let barWidth: CGFloat = 2
    /// 손가락은 그립보다 크다 — 그리는 크기보다 이만큼 넓게 잡는다.
    static let grabMargin: CGFloat = 11

    /// 뷰 좌표의 캐럿 rect(폭 0) → 핸들 뷰 프레임.
    ///
    /// 프레임은 바와 그립의 합집합이다. 그립이 바 바깥으로 튀어나오므로
    /// 세로로 지름만큼 넓히고, 가로는 캐럿을 가운데 두고 지름만큼 잡는다.
    /// 시작 핸들은 그립이 **위**, 끝 핸들은 **아래**다 (선택 밖으로 향한다).
    static func handleFrame(caretRect: CGRect, edge: HwpSelectionEdge) -> CGRect {
        CGRect(
            x: caretRect.midX - knobDiameter / 2,
            y: edge == .start ? caretRect.minY - knobDiameter : caretRect.minY,
            width: knobDiameter,
            height: caretRect.height + knobDiameter
        )
    }

    /// 핸들 뷰 **로컬** 좌표의 (바, 그립) 프레임.
    static func handleParts(
        in bounds: CGRect,
        edge: HwpSelectionEdge
    ) -> (bar: CGRect, knob: CGRect) {
        let diameter = bounds.width
        let caretHeight = max(0, bounds.height - diameter)
        let bar = CGRect(
            x: (diameter - barWidth) / 2,
            y: edge == .start ? diameter : 0,
            width: barWidth,
            height: caretHeight
        )
        let knob = CGRect(
            x: 0,
            y: edge == .start ? 0 : caretHeight,
            width: diameter,
            height: diameter
        )
        return (bar, knob)
    }

    /// `handleFrame`의 역 — 핸들 프레임에서 캐럿 중심을 되돌린다.
    /// 그랩 오프셋 계산이 이것을 쓴다.
    static func caretCenter(handleFrame: CGRect, edge: HwpSelectionEdge) -> CGPoint {
        let caretHeight = max(0, handleFrame.height - handleFrame.width)
        let minY = edge == .start
            ? handleFrame.minY + handleFrame.width
            : handleFrame.minY
        return CGPoint(x: handleFrame.midX, y: minY + caretHeight / 2)
    }

    /// 그랩 순간의 (캐럿 중심 − 터치점). 드래그 중 터치점에 이 값을 더해야
    /// 캐럿이 잡는 순간 손가락으로 **튀지 않고** 상대 위치를 지킨다.
    static func grabOffset(caretCenter: CGPoint, touchPoint: CGPoint) -> CGPoint {
        CGPoint(x: caretCenter.x - touchPoint.x, y: caretCenter.y - touchPoint.y)
    }

    /// 그랩 오프셋을 반영한 "지금 캐럿이 있어야 할" 뷰 좌표.
    static func caretPoint(touchPoint: CGPoint, grabOffset: CGPoint) -> CGPoint {
        CGPoint(x: touchPoint.x + grabOffset.x, y: touchPoint.y + grabOffset.y)
    }

    /// 핸들 로컬 점이 그랩 영역(프레임 + `grabMargin`) 안인가.
    static func isWithinGrabArea(_ point: CGPoint, bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -grabMargin, dy: -grabMargin).contains(point)
    }

    /// 뷰포트 안에 캐럿이 걸쳐 있는가.
    ///
    /// 밖이면 핸들을 **숨긴다** — 가장자리로 클램프해 보여주면 손가락이 엉뚱한
    /// 자리의 핸들을 잡아 선택이 튄다. 페이지 가상화로 페이지 레이어가 축출돼도
    /// 캐럿 좌표 자체는 지오메트리에서 나오므로 계산은 살아 있다.
    /// (`CGRect.intersects`를 못 쓰는 이유는 캐럿 폭이 0이라 항상 false여서다.)
    static func isCaretVisible(caretRect: CGRect, in viewportBounds: CGRect) -> Bool {
        caretRect.maxY > viewportBounds.minY
            && caretRect.minY < viewportBounds.maxY
            && caretRect.maxX >= viewportBounds.minX
            && caretRect.minX <= viewportBounds.maxX
    }
}
