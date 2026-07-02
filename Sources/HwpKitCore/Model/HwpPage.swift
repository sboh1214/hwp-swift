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

public struct HwpPage: Sendable, Hashable {
    public let size: CGSize
    public let margins: HwpPageMargins
    public let blocks: [AnyHwpBlock]
    public let pageNumber: Int
    public let paintList: HwpPaintList

    public init(
        size: CGSize,
        margins: HwpPageMargins,
        blocks: [AnyHwpBlock],
        pageNumber: Int,
        paintList: HwpPaintList = HwpPaintList(commands: [])
    ) {
        self.size = size
        self.margins = margins
        self.blocks = blocks
        self.pageNumber = pageNumber
        self.paintList = paintList
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(margins)
        hasher.combine(blocks)
        hasher.combine(pageNumber)
        hasher.combine(paintList.commands.count)
    }

    public static func == (lhs: HwpPage, rhs: HwpPage) -> Bool {
        lhs.size == rhs.size
            && lhs.margins == rhs.margins
            && lhs.blocks == rhs.blocks
            && lhs.pageNumber == rhs.pageNumber
            && lhs.paintList.commands.count == rhs.paintList.commands.count
    }
}
