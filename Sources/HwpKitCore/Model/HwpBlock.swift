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
    public let attributedString: NSAttributedString?
    public let hyperlinkURL: String?

    public init(
        frame: CGRect,
        kind: HwpBlockKind,
        attributedString: NSAttributedString? = nil,
        hyperlinkURL: String? = nil
    ) {
        self.frame = frame
        self.kind = kind
        self.attributedString = attributedString
        self.hyperlinkURL = hyperlinkURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
        hasher.combine(attributedString?.string)
        hasher.combine(hyperlinkURL)
    }

    public static func == (lhs: AnyHwpBlock, rhs: AnyHwpBlock) -> Bool {
        lhs.kind == rhs.kind
            && lhs.frame == rhs.frame
            && lhs.attributedString?.string == rhs.attributedString?.string
            && lhs.hyperlinkURL == rhs.hyperlinkURL
    }
}
