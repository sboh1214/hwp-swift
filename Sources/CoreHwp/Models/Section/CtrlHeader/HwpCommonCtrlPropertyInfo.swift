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
    /** 세로 위치 기준에 대한 상대적인 배열 방식 raw 값 */
    public var verticalAlignmentRawValue: Int
    /** 가로 위치 기준 raw 값 */
    public var horizontalRelativeToRawValue: Int
    /** 가로 위치 기준에 대한 상대적인 배열 방식 raw 값 */
    public var horizontalAlignmentRawValue: Int
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
        verticalAlignmentRawValue = try reader.readInt(3)
        horizontalRelativeToRawValue = try reader.readInt(2)
        horizontalAlignmentRawValue = try reader.readInt(3)
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
    init() {
        rawValue = 0
        treatAsChar = false
        affectsLineSpacing = false
        verticalRelativeToRawValue = 0
        verticalAlignmentRawValue = 0
        horizontalRelativeToRawValue = 0
        horizontalAlignmentRawValue = 0
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

public enum HwpCommonCtrlTextWrap: Int, HwpPrimitive {
    /** 어울림 */
    case square = 0
    /** 자리 차지 */
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
