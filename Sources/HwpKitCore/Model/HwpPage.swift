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

    /// 등가는 렌더 산출이 아니라 **구조**로 판정한다 — size·margins·blocks·
    /// pageNumber와 메모 패널 기하 (width·contentHeight). `paintList`는 어느 항에도
    /// 들어가지 않는다 (#72).
    ///
    /// 본문 paint 커맨드는 blocks의 파생값이라 판별력을 더하지 못하고
    /// (`AnyHwpBlock.==`가 frame·kind·payload·문자열을 이미 비교한다), CF 페이로드
    /// (NSAttributedString/CGImage/CGPath/CGColor)는 Equatable이 아니라 애초에
    /// 커맨드 **개수** 말고는 비교할 수단도 없었다.
    ///
    /// 메모 풍선 텍스트는 blocks에 표현이 없어 파생값이 아니지만, 풍선마다 누적한
    /// `contentHeight`가 풍선 수와 본문 줄 수를 함께 움직인다. 풍선 수가 달라지는데
    /// `contentHeight`가 우연히 같은 잔여 케이스는 수용한다.
    ///
    /// 렌더 결과 확인에 이 `==`를 쓰지 말 것 — 여기서 같다는 것은 조판 구조가 같다는
    /// 뜻이지 같은 픽셀이 나온다는 뜻이 아니다.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(margins)
        hasher.combine(blocks)
        hasher.combine(pageNumber)
        hasher.combine(memoPanel?.width ?? 0)
        hasher.combine(memoPanel?.contentHeight ?? 0)
    }

    public static func == (lhs: HwpPage, rhs: HwpPage) -> Bool {
        lhs.size == rhs.size
            && lhs.margins == rhs.margins
            && lhs.blocks == rhs.blocks
            && lhs.pageNumber == rhs.pageNumber
            && lhs.memoPanel?.width == rhs.memoPanel?.width
            && lhs.memoPanel?.contentHeight == rhs.memoPanel?.contentHeight
    }
}
