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
    /// BinItem 참조로 이미지를 그린다. 실제 비트맵은 네이티브 레이어가
    /// `HwpImageStore` + 이미지 캐시를 통해 지연 디코딩한다.
    case drawImageReference(binItemId: UInt32, rect: CGRect)
    case drawPlaceholder(rect: CGRect, text: String)
    case hyperlink(rect: CGRect, url: String)
}
