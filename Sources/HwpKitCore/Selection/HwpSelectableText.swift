import CoreGraphics
import Foundation

/// 선택 가능한 텍스트 단위 하나 — `.drawText` 명령과 동형인
/// (attributedString, 페이지 로컬 rect) 쌍.
public struct HwpTextUnit {
    public let blockIndex: Int
    public let unitIndex: Int
    public let attributedString: NSAttributedString
    /// 페이지 로컬 top-down — `HwpPaintListBuilder`의 drawText origin/width와 동일
    public let rect: CGRect
}

/// 페이지의 블록을 문서 순서의 텍스트 단위로 전개한다. 전개 순서·오프셋은
/// `HwpBlockContentWalker`를 렌더 (`HwpPaintListBuilder`)와 공유해 선택
/// 지오메트리가 렌더와 같은 입력을 쓰게 한다 — 계약은
/// `HwpSelectableTextPaintParityTests`가 고정한다.
public enum HwpSelectableText {
    public static func units(in page: HwpPage) -> [HwpTextUnit] {
        var units: [HwpTextUnit] = []
        for (blockIndex, block) in page.blocks.enumerated() {
            // 머리말/꼬리말/쪽 번호는 본문 선택·복사에서 제외한다
            guard block.role == .body else { continue }
            var unitIndex = 0
            HwpBlockContentWalker.walkText(block: block) { attributed, rect in
                units.append(HwpTextUnit(
                    blockIndex: blockIndex,
                    unitIndex: unitIndex,
                    attributedString: attributed,
                    rect: rect
                ))
                unitIndex += 1
            }
        }
        return units
    }
}
