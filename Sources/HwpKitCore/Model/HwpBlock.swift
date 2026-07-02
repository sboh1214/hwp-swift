import CoreGraphics
import Foundation

public protocol HwpBlock: Sendable {
    var frame: CGRect { get }
    var kind: HwpBlockKind { get }
}

public enum HwpBlockKind: String, Sendable, Hashable {
    case text, image, shape, table, textbox, footnote, placeholder
}

public struct AnyHwpBlock: HwpBlock, @unchecked Sendable, Hashable {
    public let frame: CGRect
    public let kind: HwpBlockKind
    public let identifier: UUID
    public let attributedString: NSAttributedString?

    public init(
        frame: CGRect,
        kind: HwpBlockKind,
        identifier: UUID = UUID(),
        attributedString: NSAttributedString? = nil
    ) {
        self.frame = frame
        self.kind = kind
        self.identifier = identifier
        self.attributedString = attributedString
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(kind)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }

    public static func == (lhs: AnyHwpBlock, rhs: AnyHwpBlock) -> Bool {
        lhs.identifier == rhs.identifier
            && lhs.kind == rhs.kind
            && lhs.frame == rhs.frame
    }
}
