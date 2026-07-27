import Foundation

/// 문서 전역 텍스트 위치 — (페이지, 블록, 블록 내 텍스트 단위, 문자 오프셋)
/// 튜플의 사전순 비교로 크로스 페이지 선택의 anchor/focus를 정규화한다.
public struct HwpTextPosition: Comparable, Hashable, Sendable {
    public let pageIndex: Int
    public let blockIndex: Int
    public let unitIndex: Int
    /// 단위 attributedString의 UTF-16 오프셋
    public let characterOffset: Int

    public init(pageIndex: Int, blockIndex: Int, unitIndex: Int, characterOffset: Int) {
        self.pageIndex = pageIndex
        self.blockIndex = blockIndex
        self.unitIndex = unitIndex
        self.characterOffset = characterOffset
    }

    public static func < (lhs: HwpTextPosition, rhs: HwpTextPosition) -> Bool {
        (lhs.pageIndex, lhs.blockIndex, lhs.unitIndex, lhs.characterOffset)
            < (rhs.pageIndex, rhs.blockIndex, rhs.unitIndex, rhs.characterOffset)
    }
}

/// 드래그 선택 범위. anchor는 드래그 시작점에 고정되고 focus가 따라온다 —
/// 역방향 드래그도 `range`가 문서 순서로 정규화한다.
public struct HwpTextSelection: Hashable, Sendable {
    public var anchor: HwpTextPosition
    public var focus: HwpTextPosition

    public init(anchor: HwpTextPosition, focus: HwpTextPosition) {
        self.anchor = anchor
        self.focus = focus
    }

    public var range: (start: HwpTextPosition, end: HwpTextPosition) {
        anchor <= focus ? (anchor, focus) : (focus, anchor)
    }

    public var isCollapsed: Bool {
        anchor == focus
    }
}
