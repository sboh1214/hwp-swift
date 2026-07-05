import CoreGraphics
import Foundation

/// 레이아웃이 끝난 문단 하나: 텍스트 + 지오메트리 + 원본 문단 참조.
///
/// `paragraphId`는 CoreHwp `HwpParaHeader.paraId`로, 추후 편집 기능이
/// 렌더 결과에서 모델 문단으로 되돌아갈 수 있게 한다.
public struct HwpLaidOutParagraph: @unchecked Sendable {
    public let attributedString: NSAttributedString
    public let frame: HwpParagraphFrame
    /// 블록 로컬 좌표계에서 이 문단이 차지하는 영역
    public let rect: CGRect
    /// 원본 CoreHwp 문단의 paraId (편집용 모델 참조)
    public let paragraphId: UInt32

    public init(
        attributedString: NSAttributedString,
        frame: HwpParagraphFrame,
        rect: CGRect,
        paragraphId: UInt32
    ) {
        self.attributedString = NSAttributedString(attributedString: attributedString)
        self.frame = frame
        self.rect = rect
        self.paragraphId = paragraphId
    }
}

extension HwpLaidOutParagraph: Hashable {
    public static func == (lhs: HwpLaidOutParagraph, rhs: HwpLaidOutParagraph) -> Bool {
        lhs.paragraphId == rhs.paragraphId
            && lhs.rect == rhs.rect
            && lhs.frame == rhs.frame
            && lhs.attributedString.string == rhs.attributedString.string
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paragraphId)
        hasher.combine(rect.origin.x)
        hasher.combine(rect.origin.y)
        hasher.combine(rect.size.width)
        hasher.combine(rect.size.height)
        hasher.combine(attributedString.string)
    }
}

/// 이미지 블록의 렌더 정보. 디코딩된 비트맵 대신 BinItem 참조를 운반해
/// 네이티브 레이어가 캐시를 통해 지연 디코딩할 수 있게 한다.
public struct HwpImageBlockInfo: Sendable, Hashable {
    /// DocInfo HWPTAG_BIN_DATA 참조값 (1-based)
    public let binItemId: UInt32
    /// 테두리 색 (없으면 테두리 없음)
    public let borderColor: HwpRGBColor?
    /// 테두리 두께 (pt)
    public let borderWidth: CGFloat

    public init(binItemId: UInt32, borderColor: HwpRGBColor? = nil, borderWidth: CGFloat = 0) {
        self.binItemId = binItemId
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

/// CGColor 대신 Hashable하게 운반하는 RGB 색상 값.
public struct HwpRGBColor: Sendable, Hashable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 블록이 어떤 CoreHwp 모델에서 왔는지 가리키는 안정적인 참조 (편집 대비).
public struct HwpBlockSource: Sendable, Hashable {
    /// 개체 공통 속성의 instance id (표 69)
    public let controlInstanceId: UInt32?
    /// 원본 문단의 paraId
    public let paragraphId: UInt32?
    /// 문서 내 구역 index
    public let sectionIndex: Int?
    /// 구역 내 문단 index
    public let paragraphIndex: Int?

    public init(
        controlInstanceId: UInt32? = nil,
        paragraphId: UInt32? = nil,
        sectionIndex: Int? = nil,
        paragraphIndex: Int? = nil
    ) {
        self.controlInstanceId = controlInstanceId
        self.paragraphId = paragraphId
        self.sectionIndex = sectionIndex
        self.paragraphIndex = paragraphIndex
    }
}

/// 블록 종류별 상세 레이아웃 결과.
public enum HwpBlockPayload: @unchecked Sendable, Hashable {
    case table(HwpTableFrame)
    case textbox(HwpTextboxFrame)
    case footnote(HwpFootnoteBlock)
    case shape(HwpShapeGeometry)
    case image(HwpImageBlockInfo)
}
