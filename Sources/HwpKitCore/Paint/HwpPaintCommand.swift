@preconcurrency import CoreGraphics
@preconcurrency import Foundation

/// Hashable is intentionally omitted: CGColor, CGImage, CGPath, and NSAttributedString
/// are reference/CF types that require non-trivial manual conformance and identity-based
/// hashing would be semantically wrong for most callers. Sendable is sufficient for T21.
///
/// 직접 생성 시 참조 페이로드(NSAttributedString·CGPath)는 immutable 인스턴스여야
/// 한다 — enum case는 복사를 강제할 수 없어, mutable 서브클래스를 넣고 actor 경계
/// 이후 변형하면 `@unchecked Sendable` 계약이 깨진다. 라이브러리 생산 경로는 소유권
/// 경계(AnyHwpBlock·HwpLaidOutParagraph·HwpShapeGeometry init)에서 동결된다 (R61 #3).
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
