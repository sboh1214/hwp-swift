/**
 4.3.9. 개체 공통 속성의 속성

 개체 공통 속성의 배치, 크기 기준, 본문 흐름 방식을 나타내는 bit field이다.
 */
public struct HwpCommonCtrlPropertyInfo {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 글자처럼 취급 여부 */
    public var treatAsChar: Bool
    /** 줄 간격에 영향을 줄지 여부 */
    public var affectsLineSpacing: Bool
    /** 세로 위치 기준 raw 값 */
    public var verticalRelativeToRawValue: Int
    /** 세로 위치 기준 */
    public var verticalRelativeTo: HwpCommonCtrlVerticalRelativeTo?
    /** 세로 위치 기준에 대한 상대적인 배열 방식 raw 값 */
    public var verticalAlignmentRawValue: Int
    /** 세로 위치 기준에 대한 상대적인 배열 방식 */
    public var verticalAlignment: HwpCommonCtrlRelativeAlignment?
    /** 가로 위치 기준 raw 값 */
    public var horizontalRelativeToRawValue: Int
    /** 가로 위치 기준 (스펙 표 70의 '0 page'는 종이의 오기) */
    public var horizontalRelativeTo: HwpCommonCtrlHorizontalRelativeTo?
    /** 가로 위치 기준에 대한 상대적인 배열 방식 raw 값 */
    public var horizontalAlignmentRawValue: Int
    /** 가로 위치 기준에 대한 상대적인 배열 방식 */
    public var horizontalAlignment: HwpCommonCtrlRelativeAlignment?
    /** VertRelTo이 `para`일 때 오브젝트의 세로 위치를 본문 영역으로 제한할지 여부 */
    public var restrictInPage: Bool
    /** 다른 오브젝트와 겹치는 것을 허용할지 여부 */
    public var allowOverlap: Bool
    /** 오브젝트 폭 기준 raw 값 */
    public var widthRelativeToRawValue: Int
    /** 오브젝트 폭 기준 */
    public var widthRelativeTo: HwpCommonCtrlObjectWidthRelativeTo?
    /** 오브젝트 높이 기준 raw 값 */
    public var heightRelativeToRawValue: Int
    /** 오브젝트 높이 기준 */
    public var heightRelativeTo: HwpCommonCtrlObjectHeightRelativeTo?
    /** VertRelTo이 `para`일 때 크기 보호 여부 */
    public var protectSizeInParagraphVertRelTo: Bool
    /** 오브젝트 주위를 텍스트가 어떻게 흘러갈지 지정하는 옵션 raw 값 */
    public var textWrapRawValue: Int
    /** 오브젝트 주위를 텍스트가 어떻게 흘러갈지 지정하는 옵션 */
    public var textWrap: HwpCommonCtrlTextWrap?
    /** 오브젝트의 좌/우 어느 쪽에 글을 배치할지 지정하는 옵션 raw 값 */
    public var textFlowSideRawValue: Int
    /** 오브젝트의 좌/우 어느 쪽에 글을 배치할지 지정하는 옵션 */
    public var textFlowSide: HwpCommonCtrlTextFlowSide?
    /** 이 개체가 속하는 번호 범주 raw 값 */
    public var numberingCategoryRawValue: Int
    /** 이 개체가 속하는 번호 범주 */
    public var numberingCategory: HwpCommonCtrlNumberingCategory?

    /** 본문 영역 제한 규칙을 적용한 실제 겹침 허용 여부 */
    public var effectiveAllowOverlap: Bool {
        allowOverlap && !restrictInPage
    }
}

extension HwpCommonCtrlPropertyInfo: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        treatAsChar = try reader.readBit()
        _ = try reader.readBit()
        affectsLineSpacing = try reader.readBit()
        verticalRelativeToRawValue = try reader.readInt(2)
        verticalRelativeTo = HwpCommonCtrlVerticalRelativeTo(rawValue: verticalRelativeToRawValue)
        verticalAlignmentRawValue = try reader.readInt(3)
        verticalAlignment = HwpCommonCtrlRelativeAlignment(rawValue: verticalAlignmentRawValue)
        horizontalRelativeToRawValue = try reader.readInt(2)
        horizontalRelativeTo = HwpCommonCtrlHorizontalRelativeTo(
            rawValue: horizontalRelativeToRawValue
        )
        horizontalAlignmentRawValue = try reader.readInt(3)
        horizontalAlignment = HwpCommonCtrlRelativeAlignment(rawValue: horizontalAlignmentRawValue)
        restrictInPage = try reader.readBit()
        allowOverlap = try reader.readBit()

        widthRelativeToRawValue = try reader.readInt(3)
        widthRelativeTo = HwpCommonCtrlObjectWidthRelativeTo(rawValue: widthRelativeToRawValue)

        heightRelativeToRawValue = try reader.readInt(2)
        heightRelativeTo = HwpCommonCtrlObjectHeightRelativeTo(rawValue: heightRelativeToRawValue)

        protectSizeInParagraphVertRelTo = try reader.readBit()

        textWrapRawValue = try reader.readInt(3)
        textWrap = HwpCommonCtrlTextWrap(rawValue: textWrapRawValue)

        textFlowSideRawValue = try reader.readInt(2)
        textFlowSide = HwpCommonCtrlTextFlowSide(rawValue: textFlowSideRawValue)

        numberingCategoryRawValue = try reader.readInt(3)
        numberingCategory = HwpCommonCtrlNumberingCategory(rawValue: numberingCategoryRawValue)

        try reader.readBits(3)
    }

    static func load(_ uint: UInt32) throws -> Self {
        var reader = BitsReader(from: uint)
        var propertyInfo = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        propertyInfo.rawValue = uint
        return propertyInfo
    }
}

extension HwpCommonCtrlPropertyInfo {
    /// typed 필드에서 bit field를 되만든다 — 위 `init(_ reader:)`의 읽기
    /// 순서를 그대로 뒤집은 것이라 두 방향이 한 파일에서 대조된다
    /// (LSB-first, `BitsReader` 규약).
    ///
    /// raw가 없는 합성 경로(HWPX)를 위한 것이다 — typed 필드만 채우면
    /// `rawValue`/`property`가 0으로 남아 같은 모델 안에서 두 표현이
    /// 어긋난다. 예약 비트(1, 29-31)는 되살릴 근거가 없어 0으로 둔다.
    var synthesizedRawValue: UInt32 {
        var raw: UInt32 = 0
        var offset = 0
        func put(_ value: Int, width: Int) {
            raw |= UInt32(value & ((1 << width) - 1)) << offset
            offset += width
        }
        put(treatAsChar ? 1 : 0, width: 1)
        put(0, width: 1)
        put(affectsLineSpacing ? 1 : 0, width: 1)
        put(verticalRelativeToRawValue, width: 2)
        put(verticalAlignmentRawValue, width: 3)
        put(horizontalRelativeToRawValue, width: 2)
        put(horizontalAlignmentRawValue, width: 3)
        put(restrictInPage ? 1 : 0, width: 1)
        put(allowOverlap ? 1 : 0, width: 1)
        put(widthRelativeToRawValue, width: 3)
        put(heightRelativeToRawValue, width: 2)
        put(protectSizeInParagraphVertRelTo ? 1 : 0, width: 1)
        put(textWrapRawValue, width: 3)
        put(textFlowSideRawValue, width: 2)
        put(numberingCategoryRawValue, width: 3)
        return raw
    }

    /// 합성 raw가 표현하지 않는 자리 — 예약 비트 1과 29-31.
    static let reservedRawValueMask: UInt32 = 0b1110_0000_0000_0000_0000_0000_0000_0010

    init() {
        rawValue = 0
        treatAsChar = false
        affectsLineSpacing = false
        verticalRelativeToRawValue = 0
        verticalRelativeTo = .paper
        verticalAlignmentRawValue = 0
        verticalAlignment = .topOrLeft
        horizontalRelativeToRawValue = 0
        horizontalRelativeTo = .paper
        horizontalAlignmentRawValue = 0
        horizontalAlignment = .topOrLeft
        restrictInPage = false
        allowOverlap = false
        widthRelativeToRawValue = 0
        widthRelativeTo = .paper
        heightRelativeToRawValue = 0
        heightRelativeTo = .paper
        protectSizeInParagraphVertRelTo = false
        textWrapRawValue = 0
        textWrap = .square
        textFlowSideRawValue = 0
        textFlowSide = .bothSides
        numberingCategoryRawValue = 0
        numberingCategory = HwpCommonCtrlNumberingCategory.none
    }
}

public enum HwpCommonCtrlObjectWidthRelativeTo: Int, HwpPrimitive {
    /** 종이 */
    case paper = 0
    /** 쪽 */
    case page = 1
    /** 단 */
    case column = 2
    /** 문단 */
    case paragraph = 3
    /** 절대값 */
    case absolute = 4
}

public enum HwpCommonCtrlObjectHeightRelativeTo: Int, HwpPrimitive {
    /** 종이 */
    case paper = 0
    /** 쪽 */
    case page = 1
    /** 절대값 */
    case absolute = 2
}

/** 세로 위치 기준 (표 70 bits 3-4) */
public enum HwpCommonCtrlVerticalRelativeTo: Int, HwpPrimitive {
    /** 종이 */
    case paper = 0
    /** 쪽 */
    case page = 1
    /** 문단 */
    case paragraph = 2
}

/** 가로 위치 기준 (표 70 bits 8-9) */
public enum HwpCommonCtrlHorizontalRelativeTo: Int, HwpPrimitive {
    /** 종이 (스펙 표에는 page로 인쇄된 오기) */
    case paper = 0
    /** 쪽 */
    case page = 1
    /** 단 */
    case column = 2
    /** 문단 */
    case paragraph = 3
}

/** 위치 기준에 대한 상대적인 배열 방식 (표 70 bits 5-7 / 10-12) */
public enum HwpCommonCtrlRelativeAlignment: Int, HwpPrimitive {
    /** 위 (기준이 종이/쪽) 또는 왼쪽 */
    case topOrLeft = 0
    /** 가운데 */
    case center = 1
    /** 아래 (기준이 종이/쪽) 또는 오른쪽 */
    case bottomOrRight = 2
    /** 안쪽 (기준이 종이/쪽일 때만) */
    case inside = 3
    /** 바깥쪽 (기준이 종이/쪽일 때만) */
    case outside = 4
}

/** 본문 흐름 방식 (표 70 bits 21-23).
 바이너리 HWP5 실측 매핑 — 공개 스펙의 6값 순서와 다르다 (ErrataAudit 26b,
 equation/noori/text-box 실제 한컴 fixture raw 1/3 검증). 6값 순서를 쓰면
 raw 2/3(BehindText/InFrontOfText)이 through/topAndBottom으로 오독돼 레이어링
 개체가 본문 흐름에 흡수된다. HWPX 등 6값 포맷은 별도 매핑을 쓸 것 (#1). */
public enum HwpCommonCtrlTextWrap: Int, HwpPrimitive {
    /** 어울림 (bound rect/outline) */
    case square = 0
    /** 자리 차지 (좌우에 텍스트 없음) */
    case topAndBottom = 1
    /** 글 뒤로 */
    case behindText = 2
    /** 글 앞으로 */
    case inFrontOfText = 3
}

public enum HwpCommonCtrlTextFlowSide: Int, HwpPrimitive {
    /** 양쪽 */
    case bothSides = 0
    /** 왼쪽 */
    case leftOnly = 1
    /** 오른쪽 */
    case rightOnly = 2
    /** 큰 쪽 */
    case largestOnly = 3
}

public enum HwpCommonCtrlNumberingCategory: Int, HwpPrimitive {
    /** 없음 */
    case none = 0
    /** 그림 */
    case figure = 1
    /** 표 */
    case table = 2
    /** 수식 */
    case equation = 3
}
