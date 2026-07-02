@preconcurrency import CoreGraphics
@preconcurrency import Foundation

/// Hashable is intentionally omitted: CGColor, CGImage, CGPath, and NSAttributedString
/// are reference/CF types that require non-trivial manual conformance and identity-based
/// hashing would be semantically wrong for most callers. Sendable is sufficient for T21.
public enum HwpPaintCommand: @unchecked Sendable {
    case fillRect(rect: CGRect, color: CGColor)
    case strokeRect(rect: CGRect, color: CGColor, width: CGFloat)
    case drawText(attributedString: NSAttributedString, origin: CGPoint, lineWidth: CGFloat)
    case drawPath(path: CGPath, fill: CGColor?, stroke: CGColor?, strokeWidth: CGFloat)
    case drawImage(image: CGImage, rect: CGRect)
    case drawPlaceholder(rect: CGRect, text: String)
    case hyperlink(rect: CGRect, url: String)
}
