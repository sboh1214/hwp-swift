import CoreGraphics
import Foundation

public struct HwpPageMargins: Sendable, Hashable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// 메모 (댓글) 풍선 패널 — 한글.app 편집 뷰처럼 페이지 오른쪽 바깥 영역에
/// 그린다 (종이 밖이므로 인쇄 뷰·PrvImage에는 없다).
/// 좌표는 패널 로컬 (원점 = 페이지 오른쪽 위 모서리).
public struct HwpMemoPanel: Sendable {
    public let width: CGFloat
    public let paintList: HwpPaintList
    /// 풍선 스택 전체 높이 (패널 로컬) — 뷰가 레이어를 이 높이로 키워 페이지보다
    /// 긴 메모 패널이 클립되지 않게 한다 (#8). 페이지 높이보다 작으면 페이지 높이.
    public let contentHeight: CGFloat

    public init(width: CGFloat, paintList: HwpPaintList, contentHeight: CGFloat = 0) {
        self.width = width
        self.paintList = paintList
        self.contentHeight = contentHeight
    }
}

public struct HwpPage: Sendable, Hashable {
    public let size: CGSize
    public let margins: HwpPageMargins
    public let blocks: [AnyHwpBlock]
    public let pageNumber: Int
    public let paintList: HwpPaintList
    public let memoPanel: HwpMemoPanel?

    public init(
        size: CGSize,
        margins: HwpPageMargins,
        blocks: [AnyHwpBlock],
        pageNumber: Int,
        paintList: HwpPaintList = HwpPaintList(commands: []),
        memoPanel: HwpMemoPanel? = nil
    ) {
        self.size = size
        self.margins = margins
        self.blocks = blocks
        self.pageNumber = pageNumber
        self.paintList = paintList
        self.memoPanel = memoPanel
    }

    /// paintList contributes only commands.count (structural fingerprint); its CF
    /// payloads (NSAttributedString/CGImage/CGPath/CGColor) are not Equatable, so
    /// pages with same count but different rendered content compare equal.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(margins)
        hasher.combine(blocks)
        hasher.combine(pageNumber)
        hasher.combine(paintList.commands.count)
        hasher.combine(memoPanel?.width ?? 0)
        hasher.combine(memoPanel?.paintList.commands.count ?? 0)
        hasher.combine(memoPanel?.contentHeight ?? 0)
    }

    public static func == (lhs: HwpPage, rhs: HwpPage) -> Bool {
        lhs.size == rhs.size
            && lhs.margins == rhs.margins
            && lhs.blocks == rhs.blocks
            && lhs.pageNumber == rhs.pageNumber
            && lhs.paintList.commands.count == rhs.paintList.commands.count
            && lhs.memoPanel?.width == rhs.memoPanel?.width
            && lhs.memoPanel?.paintList.commands.count
            == rhs.memoPanel?.paintList.commands.count
            && lhs.memoPanel?.contentHeight == rhs.memoPanel?.contentHeight
    }
}
