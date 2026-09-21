import CoreText
import Foundation
import HwpKitCore

extension HwpPageLayer {
    /// 줄 배치와 동일한 규칙 — `HwpDrawnTextLayout` 위임 (렌더·선택 공유). `endsParagraph`는
    /// 문단의 마지막 줄 판정(`HwpDrawnLine.endsParagraph`) — 그 줄의 상자에는 접힌 문단 끝
    /// 글자의 글자 모양도 든다 (#206).
    static func underlineReturnDrop(of line: CTLine, endsParagraph: Bool) -> CGFloat {
        HwpDrawnTextLayout.underlineReturnDrop(of: line, endsParagraph: endsParagraph)
    }
}
