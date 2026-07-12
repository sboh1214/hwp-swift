import CoreGraphics
import Foundation

public protocol HwpBlock: Sendable {
    var frame: CGRect { get }
    var kind: HwpBlockKind { get }
}

public enum HwpBlockKind: String, Sendable, Hashable {
    case text, image, shape, table, textbox, footnote, placeholder
}

/// 블록이 본문 흐름인지 페이지 크롬 (머리말/꼬리말/쪽 번호)인지 —
/// 텍스트 선택·복사는 크롬을 건너뛴다.
public enum HwpBlockRole: String, Sendable, Hashable {
    case body, pageChrome
}

public struct AnyHwpBlock: HwpBlock, @unchecked Sendable, Hashable {
    public let frame: CGRect
    public let kind: HwpBlockKind
    public let attributedString: NSAttributedString?
    public let hyperlinkURL: String?
    /// 블록 종류별 상세 레이아웃 결과 (표 셀 grid, 도형 path, 이미지 참조 등)
    public let payload: HwpBlockPayload?
    /// 이 블록이 유래한 CoreHwp 모델 참조 (편집 대비)
    public let source: HwpBlockSource?
    public let role: HwpBlockRole

    public init(
        frame: CGRect,
        kind: HwpBlockKind,
        attributedString: NSAttributedString? = nil,
        hyperlinkURL: String? = nil,
        payload: HwpBlockPayload? = nil,
        source: HwpBlockSource? = nil,
        role: HwpBlockRole = .body
    ) {
        self.frame = frame
        self.kind = kind
        self.attributedString = attributedString
        self.hyperlinkURL = hyperlinkURL
        self.payload = payload
        self.source = source
        self.role = role
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
        hasher.combine(attributedString?.string)
        hasher.combine(hyperlinkURL)
        hasher.combine(payload)
        hasher.combine(source)
        hasher.combine(role)
    }

    public static func == (lhs: AnyHwpBlock, rhs: AnyHwpBlock) -> Bool {
        lhs.kind == rhs.kind
            && lhs.frame == rhs.frame
            && lhs.attributedString?.string == rhs.attributedString?.string
            && lhs.hyperlinkURL == rhs.hyperlinkURL
            && lhs.payload == rhs.payload
            && lhs.source == rhs.source
            && lhs.role == rhs.role
    }
}
