import CoreText
import Foundation
import HwpKitCore

extension HwpPageLayer {
    /// 줄 배치와 동일한 규칙 — `HwpDrawnTextLayout` 위임 (렌더·선택 공유)
    static func baselineLift(of line: CTLine) -> CGFloat {
        HwpDrawnTextLayout.baselineLift(of: line)
    }

    static func underlineReturnDrop(of line: CTLine) -> CGFloat {
        HwpDrawnTextLayout.underlineReturnDrop(of: line)
    }
}
