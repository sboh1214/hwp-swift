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

    public init(size: CGSize, margins: HwpPageMargins, blocks: [AnyHwpBlock], pageNumber: Int) {
        self.size = size
        self.margins = margins
        self.blocks = blocks
        self.pageNumber = pageNumber
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(margins)
        hasher.combine(blocks)
        hasher.combine(pageNumber)
    }
}
