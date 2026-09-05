import CoreGraphics
import CoreHwp
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
    /// 이 문단을 감싸는 하이퍼링크(%hlk) URL — 표 셀/글상자 안 링크를 히트
    /// 테스트가 찾을 수 있게 컨테이너 문단에 실어 나른다 (없으면 nil).
    public let hyperlinkURL: String?

    public init(
        attributedString: NSAttributedString,
        frame: HwpParagraphFrame,
        rect: CGRect,
        paragraphId: UInt32,
        hyperlinkURL: String? = nil
    ) {
        self.attributedString = NSAttributedString(attributedString: attributedString)
        self.frame = frame
        self.rect = rect
        self.paragraphId = paragraphId
        self.hyperlinkURL = hyperlinkURL
    }
}

extension HwpLaidOutParagraph: Hashable {
    /// 반복 표 머리행 클론 표식. `attributedString` 의 **속성**이라 문자열
    /// 비교로는 안 잡히는데, 검색 목록 dedup 과 복사(`plainText`)가 이 값으로
    /// 판정한다.
    ///
    /// **동등성이 이 층에 있어야 하는 이유**: 실제 반복 머리행 블록은
    /// top-level `attributedString` 이 nil 인 `.table` 이고 표식은 여기,
    /// 셀 문단에 붙는다 (`HwpTableSplitter.markRepeatedHeader`). 그래서
    /// `AnyHwpBlock` 쪽만 보면 프로덕션 문서에서는 늘 false 라, 표식만 뒤집힌
    /// 재전달이 "같은 내용"으로 접혀 목록이 옛 분류에 머문다 (#75 리뷰 8차).
    /// 판정은 선택·검색과 **같은 술어**를 쓴다.
    var isRepeatedTableHeaderClone: Bool {
        HwpSelectionGeometry.isRepeatedHeaderClone(attributedString)
    }

    public static func == (lhs: HwpLaidOutParagraph, rhs: HwpLaidOutParagraph) -> Bool {
        lhs.paragraphId == rhs.paragraphId
            && lhs.rect == rhs.rect
            && lhs.frame == rhs.frame
            && lhs.hyperlinkURL == rhs.hyperlinkURL
            && HwpTextIdentity.isIdentical(
                lhs.attributedString.string, rhs.attributedString.string
            )
            && lhs.isRepeatedTableHeaderClone == rhs.isRepeatedTableHeaderClone
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paragraphId)
        hasher.combine(rect.origin.x)
        hasher.combine(rect.origin.y)
        hasher.combine(rect.size.width)
        hasher.combine(rect.size.height)
        hasher.combine(hyperlinkURL)
        hasher.combine(attributedString.string)
        hasher.combine(isRepeatedTableHeaderClone)
    }
}

extension CoreHwp.HwpParagraph {
    /// 이 문단에 붙은 하이퍼링크 컨트롤(%hlk)의 URL (비어 있으면 nil).
    /// HWP 필드 명령의 트레일링 플래그를 뗀 순수 URL — 원문은 CoreHwp
    /// HwpHyperlink.url/urlRawPayload에 보존된다 (#3).
    var hyperlinkURL: String? {
        for ctrl in ctrlHeaderArray ?? [] {
            if case let .hyperLink(link) = ctrl, !link.url.isEmpty {
                return HwpHyperlinkURL.displayURL(link.url)
            }
        }
        return nil
    }
}

/// 하이퍼링크(%hlk) 필드 명령 문자열 파싱.
enum HwpHyperlinkURL {
    /// HWP 하이퍼링크 필드 명령의 트레일링 플래그(`;1;0;1` — 새 창/방문 여부 등
    /// HWP 내부 숫자 플래그 3개)를 떼어 실제 URL만 돌려준다. 콜백
    /// (onHyperlinkTapped)이 원문을 그대로 넘기면 호스트가 잘못된 경로를 열어
    /// 404가 난다 (CCL·공공누리 실측: `…/deed.ko;1;0;1`). 플래그가 없으면 원문 그대로.
    static func displayURL(_ raw: String) -> String {
        guard let flags = raw.range(
            of: ";[0-9]+;[0-9]+;[0-9]+$", options: .regularExpression
        ) else { return raw }
        return String(raw[raw.startIndex ..< flags.lowerBound])
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
    /// crop은 원본 크기 좌표계(HWPUNIT→px, /75)라 원본 기준으로 계산·"crop 없음"
    /// 판정을 하고, 실제(다운샘플됐을 수 있는) 비트맵 크기에 비례 스케일한다 (#5).
    /// 원본 크기를 안 주면 비트맵 크기와 동일 취급 → 기존 동작과 같다.
    public func pixelCropRect(
        imageWidth: Int,
        imageHeight: Int,
        originalWidth: Int? = nil,
        originalHeight: Int? = nil
    ) -> CGRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        guard cropRight > cropLeft, cropBottom > cropTop else { return nil }
        let origW = CGFloat(originalWidth ?? imageWidth)
        let origH = CGFloat(originalHeight ?? imageHeight)
        guard origW > 0, origH > 0 else { return nil }

        func pixels(_ value: Int32) -> CGFloat {
            (CGFloat(value) / Self.hwpUnitsPerPixel).rounded()
        }
        let minX = max(0, min(origW, pixels(cropLeft)))
        let minY = max(0, min(origH, pixels(cropTop)))
        let maxX = max(0, min(origW, pixels(cropRight)))
        let maxY = max(0, min(origH, pixels(cropBottom)))
        guard maxX > minX, maxY > minY else { return nil }

        let origRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard origRect != CGRect(x: 0, y: 0, width: origW, height: origH) else { return nil }

        let sx = CGFloat(imageWidth) / origW
        let sy = CGFloat(imageHeight) / origH
        return CGRect(
            x: origRect.minX * sx, y: origRect.minY * sy,
            width: origRect.width * sx, height: origRect.height * sy
        )
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
    case chart(HwpChartFrame)
}

/// OLE 내장 차트 (OOXMLChartContents)에서 파싱한 렌더용 차트 데이터.
///
/// 한컴의 실제 차트 엔진 렌더 (3D 원근·음영)는 재현 범위 밖 — 계열/값/제목/
/// 범례를 같은 기하 배치로 근사해 그린다 (빈 상자보다 한글.app에 가깝다).
public struct HwpChartFrame: Sendable, Hashable {
    public struct Series: Sendable, Hashable {
        public let name: String
        public let values: [Double]

        public init(name: String, values: [Double]) {
            self.name = name
            self.values = values
        }
    }

    /// 차트 종류 (플롯 렌더 형태 선택)
    public enum Kind: Sendable, Hashable {
        /// 세로 막대 (barDir=col). cone=true면 원뿔 마커 (3D 원뿔 차트 근사)
        case bar(cone: Bool)
    }

    /// 제목 (c:title). 자동 제목이면 한컴 기본값 "차트 제목".
    public let title: String?
    /// 카테고리 축 라벨 (항목 1…)
    public let categories: [String]
    /// 계열 (이름 + 카테고리별 값)
    public let series: [Series]
    /// 범례 표시 여부 (c:legend)
    public let showLegend: Bool
    public let kind: Kind

    public init(
        title: String?,
        categories: [String],
        series: [Series],
        showLegend: Bool,
        kind: Kind
    ) {
        self.title = title
        self.categories = categories
        self.series = series
        self.showLegend = showLegend
        self.kind = kind
    }
}

public extension HwpLaidOutParagraph {
    /// 이 문단이 하이퍼링크를 품는지 — 문단-레벨 URL 또는 `%hlk` 스팬 속성.
    ///
    /// 블록-레벨 폴백의 게이트다 (R61): 방출은 안쪽 링크를 하나라도 내면 프레임
    /// 전체 블록 링크를 내지 않으므로 히트도 그때는 폴백하면 안 된다. 탭 경로에서
    /// 쓰이므로 **CT 조판 없이 속성만** 훑는다 (R55).
    var hasHyperlink: Bool {
        if hyperlinkURL != nil {
            return true
        }
        var found = false
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.hyperlink,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            guard value != nil else { return }
            found = true
            stop.pointee = true
        }
        return found
    }
}

/// 문단의 **위치 열쇠** — (구역 서수, 구역 안 문단 서수). 조판이 본문 문단 블록에
/// 싣고(`HwpPaginator.appendBlock`) 복사(`HwpSelectionGeometry.joinsWithPrevious`)가
/// 열/쪽에 걸친 같은 문단의 조각을 잇는 identity로 쓴다. `paraId`는 한글.app
/// 저장본에서 0·0x80000000이 되풀이돼(noori 65문단 중 고유 값 2개) 문단을 가르지
/// 못한다 (#145).
public struct HwpParagraphKey: Hashable, Sendable {
    public let sectionIndex: Int
    public let paragraphIndex: Int

    public init(sectionIndex: Int, paragraphIndex: Int) {
        self.sectionIndex = sectionIndex
        self.paragraphIndex = paragraphIndex
    }
}

public extension HwpBlockSource {
    /// 구역·문단 서수가 모두 있을 때의 위치 열쇠 — 본문 문단 블록은 조판이
    /// 채우고, 개체 블록·손으로 만든 블록은 nil이다.
    var paragraphKey: HwpParagraphKey? {
        guard let sectionIndex, let paragraphIndex else { return nil }
        return HwpParagraphKey(sectionIndex: sectionIndex, paragraphIndex: paragraphIndex)
    }
}
