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
    /// `HwpImageStore` + 이미지 캐시를 통해 지연 디코딩하고, style이 있으면
    /// crop/밝기/명암/효과를 적용한다.
    /// clipRect: 그리기를 이 영역으로 자른다 (페이지 절단면에 걸친 분할 셀
    /// 그림 — rect 축소는 비트맵 스케일 왜곡이라 클립으로 가시 영역만 남긴다)
    case drawImageReference(
        binItemId: UInt32, rect: CGRect,
        style: HwpImageRenderStyle? = nil, clipRect: CGRect? = nil
    )
    case drawPlaceholder(rect: CGRect, text: String)
    case hyperlink(rect: CGRect, url: String)
}
