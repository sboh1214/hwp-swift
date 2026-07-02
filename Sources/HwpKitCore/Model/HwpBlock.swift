import CoreGraphics
import Foundation

public protocol HwpBlock: Sendable {
    var frame: CGRect { get }
    var kind: HwpBlockKind { get }
}

public enum HwpBlockKind: String, Sendable, Hashable {
    case text, image, shape, table, textbox, footnote, placeholder
}

public struct AnyHwpBlock: HwpBlock, Sendable, Hashable {
    public let frame: CGRect
    public let kind: HwpBlockKind
    public let identifier: UUID

    public init(frame: CGRect, kind: HwpBlockKind, identifier: UUID = UUID()) {
        self.frame = frame
        self.kind = kind
        self.identifier = identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(kind)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }
}
