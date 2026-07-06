import CoreGraphics
@preconcurrency import CoreHwp
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

/// 그림 효과 (표 107): REAL_PIC 외에는 네이티브 필터로 적용된다.
public enum HwpImageEffect: UInt8, Sendable, Hashable {
    case none = 0
    case grayscale = 1
    case blackWhite = 2

    public init(rawEffect: UInt8) {
        self = HwpImageEffect(rawValue: rawEffect) ?? .none
    }
}

/// 그림 crop/밝기/명암/효과 (표 107) 렌더 스타일.
///
/// crop 좌표는 이미지 "원본 크기" HWPUNIT 공간의 LTRB 사각형이다.
/// 픽스처 검증: 원본 크기 = 픽셀 × 75 (96 DPI 고정; BinData 1920×1080 →
/// 144000×81000 정확 일치, noori/CCL은 반올림 오차 이내).
public struct HwpImageRenderStyle: Sendable, Hashable {
    /// 자르기 후 사각형 (HWPUNIT, 원본 크기 공간)
    public let cropLeft: Int32
    public let cropTop: Int32
    public let cropRight: Int32
    public let cropBottom: Int32
    /// 밝기 (-100...100)
    public let brightness: Int
    /// 명암 (-100...100)
    public let contrast: Int
    /// 그림 효과
    public let effect: HwpImageEffect

    /// 96 DPI 고정 변환: 1px = 75 HWPUNIT
    public static let hwpUnitsPerPixel: CGFloat = 75

    public init(
        cropLeft: Int32 = 0,
        cropTop: Int32 = 0,
        cropRight: Int32 = 0,
        cropBottom: Int32 = 0,
        brightness: Int = 0,
        contrast: Int = 0,
        effect: HwpImageEffect = .none
    ) {
        self.cropLeft = cropLeft
        self.cropTop = cropTop
        self.cropRight = cropRight
        self.cropBottom = cropBottom
        self.brightness = brightness
        self.contrast = contrast
        self.effect = effect
    }

    /// 표 107 그림 속성에서 crop/밝기/명암/효과 렌더 스타일을 만든다.
    public init(pictureProperty: CoreHwp.HwpPictureProperty) {
        self.init(
            cropLeft: pictureProperty.cropLeft,
            cropTop: pictureProperty.cropTop,
            cropRight: pictureProperty.cropRight,
            cropBottom: pictureProperty.cropBottom,
            brightness: Int(pictureProperty.brightness),
            contrast: Int(pictureProperty.contrast),
            effect: HwpImageEffect(rawEffect: pictureProperty.effect)
        )
    }

    /// 색 보정/효과가 없는지
    public var hasColorAdjustments: Bool {
        brightness != 0 || contrast != 0 || effect != .none
    }

    /// 픽셀 단위 crop 사각형. 반올림 후 이미지 전체와 같으면 (crop 없음) nil.
    ///
    /// crop 값이 모두 0이거나 사각형이 비정상이면 nil을 반환한다.
    public func pixelCropRect(imageWidth: Int, imageHeight: Int) -> CGRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        guard cropRight > cropLeft, cropBottom > cropTop else { return nil }

        func pixels(_ value: Int32) -> CGFloat {
            (CGFloat(value) / Self.hwpUnitsPerPixel).rounded()
        }
        let minX = max(0, min(CGFloat(imageWidth), pixels(cropLeft)))
        let minY = max(0, min(CGFloat(imageHeight), pixels(cropTop)))
        let maxX = max(0, min(CGFloat(imageWidth), pixels(cropRight)))
        let maxY = max(0, min(CGFloat(imageHeight), pixels(cropBottom)))
        guard maxX > minX, maxY > minY else { return nil }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let full = CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight))
        guard rect != full else { return nil }
        return rect
    }

    /// 아무 변형도 없는 스타일인지 (이미지 크기를 몰라도 확실한 경우만 true)
    public var isIdentity: Bool {
        !hasColorAdjustments && cropLeft == 0 && cropTop == 0
            && cropRight <= 0 && cropBottom <= 0
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
    /// crop/밝기/명암/효과 (표 107). nil이면 원본 그대로.
    public let style: HwpImageRenderStyle?

    public init(
        binItemId: UInt32,
        borderColor: HwpRGBColor? = nil,
        borderWidth: CGFloat = 0,
        style: HwpImageRenderStyle? = nil
    ) {
        self.binItemId = binItemId
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.style = style
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
