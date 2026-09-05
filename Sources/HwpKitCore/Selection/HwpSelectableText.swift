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
    /// 원본 문단의 paraId — 반복 머리행 클론 복사 dedup의 출처 식별과, 위치
    /// 열쇠가 없는 컨테이너 문단의 이어짐 판정에 쓴다 (nil이면 미상). 문단마다
    /// 고유하지 않다 (#145) — 같은 문단인지는 `paragraphKey`가 가른다.
    public let paragraphId: UInt32?
    /// 본문 문단의 위치 열쇠 — 같은 문단이 열/쪽에 걸쳐 여러 단위로 쪼개졌는지
    /// 판정해 복사 텍스트에 헛개행을 넣지 않는 데 쓴다. 컨테이너(표 셀·글상자·
    /// 각주) 문단과 손으로 만든 블록은 nil이다.
    public let paragraphKey: HwpParagraphKey?

    public init(
        blockIndex: Int,
        unitIndex: Int,
        attributedString: NSAttributedString,
        rect: CGRect,
        paragraphId: UInt32? = nil,
        paragraphKey: HwpParagraphKey? = nil
    ) {
        self.blockIndex = blockIndex
        self.unitIndex = unitIndex
        self.attributedString = attributedString
        self.rect = rect
        self.paragraphId = paragraphId
        self.paragraphKey = paragraphKey
    }
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
            // paragraphId는 워커가 문단/블록별로 준다 — 본문 조각은 열/쪽에
            // 걸친 연속 판정에, 표/글상자/각주 셀 문단은 반복 머리행 복사
            // dedup의 출처 식별에 쓴다 (#8). 서로 다른 셀은 서로 다른 paraId.
            // 본문 `.text` 블록은 블록 자체가 단위 하나라 위치 열쇠를 블록 source에서
            // 바로 싣는다 (#145). 컨테이너 문단은 열쇠가 없어 이어짐 표식으로만
            // 접합을 판정한다 (`HwpSelectionGeometry.joinsWithPrevious`).
            let paragraphKey = block.payload == nil ? block.source?.paragraphKey : nil
            var unitIndex = 0
            HwpBlockContentWalker.walkText(block: block) { attributed, rect, paragraphId in
                units.append(HwpTextUnit(
                    blockIndex: blockIndex,
                    unitIndex: unitIndex,
                    attributedString: attributed,
                    rect: rect,
                    paragraphId: paragraphId,
                    paragraphKey: paragraphKey
                ))
                unitIndex += 1
            }
        }
        return units
    }
}
