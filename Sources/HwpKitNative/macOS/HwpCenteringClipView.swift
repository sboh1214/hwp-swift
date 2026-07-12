#if os(macOS)
    import AppKit

    /// 문서가 뷰포트보다 작을 때 (좁은 페이지·축소 줌) 가운데 정렬하는
    /// 클립 뷰. 클립 bounds는 문서 좌표계라 magnification 상태에서도
    /// documentView frame과 그대로 비교할 수 있다.
    final class HwpCenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var rect = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return rect }
            if rect.width > documentView.frame.width {
                rect.origin.x = (documentView.frame.width - rect.width) / 2
            }
            if rect.height > documentView.frame.height {
                rect.origin.y = (documentView.frame.height - rect.height) / 2
            }
            return rect
        }
    }
#endif
