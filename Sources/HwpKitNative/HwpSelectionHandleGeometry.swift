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

    /// 핸들 프레임의 **그립 중심** (프레임과 같은 좌표계).
    ///
    /// 겹친 그랩 영역의 승자를 가르는 기준점이다 — 사용자가 겨냥하는 것은
    /// 보이는 그립이지 캐럿 중심이 아니다. 두 그립은 캐럿 위·아래로 갈라져
    /// 있어 (`handleFrame`) 끝점이 완전히 겹쳐도 `줄 높이 + 지름`만큼 떨어진다.
    static func knobCenter(handleFrame: CGRect, edge: HwpSelectionEdge) -> CGPoint {
        let caretHeight = max(0, handleFrame.height - handleFrame.width)
        let radius = handleFrame.width / 2
        return CGPoint(
            x: handleFrame.midX,
            y: edge == .start
                ? handleFrame.minY + radius
                : handleFrame.minY + caretHeight + radius
        )
    }

    /// 핸들 로컬 점이 그랩 영역(프레임 + `grabMargin`) 안인가.
    static func isWithinGrabArea(_ point: CGPoint, bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -grabMargin, dy: -grabMargin).contains(point)
    }

    /// 두 핸들의 그랩 영역이 **겹쳤을 때** `own`이 그 터치를 가져가는가.
    /// 좌표계는 두 프레임과 같아야 한다 (= 공통 superview).
    ///
    /// **반드시 반대칭이어야 한다** — 인자를 맞바꾼 호출이 반대 값을 내야 한다.
    /// 둘 다 true면 subview 순서로 되돌아가 나중에 붙은 끝 핸들이 늘 이기고
    /// (그것이 이 함수가 생긴 이유다), 둘 다 false면 터치가 스크롤 뷰로 새어
    /// 탭 핸들러의 `hasSelection → clear()`가 선택을 통째로 지운다.
    /// 그래서 두 끝점(`ownEdge != otherEdge`)에만 쓴다 — 같은 끝점 둘을 넘기면
    /// 동점 갈림이 양쪽에서 같은 답을 내 그 계약이 깨진다.
    static func winsGrabContest(
        at point: CGPoint,
        ownFrame: CGRect,
        ownEdge: HwpSelectionEdge,
        otherFrame: CGRect,
        otherEdge: HwpSelectionEdge
    ) -> Bool {
        let own = squaredDistance(
            point, knobCenter(handleFrame: ownFrame, edge: ownEdge)
        )
        let other = squaredDistance(
            point, knobCenter(handleFrame: otherFrame, edge: otherEdge)
        )
        if own != other {
            return own < other
        }
        // 완전 동점 — 좌우로 가르면 양쪽이 같은 답을 내므로 **끝점 종류**로
        // 가른다 (그래야 반대칭이다).
        return ownEdge == .start
    }

    private static func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return deltaX * deltaX + deltaY * deltaY
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
