import Foundation

public struct HwpCharShapeProperty {
    /** 원본 bit field */
    @ExcludeEquatable
    public var rawValue: UInt32
    /** 기울임 여부 */
    public var isItalic: Bool
    /** 진하게 여부 */
    public var isBold: Bool
    /** 밑줄 종류 */
    public var underlineType: HwpUnderlineType
    /** 밑줄 모양 */
    public var underlineShape: Int
    /** 외곽선 종류 */
    public var borderlineType: HwpBorderLineType
    /** 그림자 종류 */
    public var shadowType: HwpShadowType
    /** 양각 여부 */
    public var isRelief: Bool
    /** 음각 여부 */
    public var isCounterRelief: Bool
    /** 위 첨자 여부 */
    public var isSuperscript: Bool
    /** 아래 첨자 여부 */
    public var isSubscript: Bool
    /** Reserved */
    public var reserved: Bool
    /** 취소선 여부 */
    public var strikethrough: Int
    /** 강조점 종류 */
    public var emphasisType: HwpEmphasisType
    /** 글꼴에 어울리는 빈칸 사용 여부 */
    public var doesAdjustBlank: Bool
    /** 취소선 모양 */
    public var strikethroughShape: Int
    /** Kerning 여부 */
    public var isKerning: Bool
}

extension HwpCharShapeProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UIntType>) throws {
        rawValue = 0
        isItalic = try reader.readBit()
        isBold = try reader.readBit()

        let underlineTypeLawValue = try reader.readInt(2)
        guard let underlineType = HwpUnderlineType(rawValue: underlineTypeLawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpUnderlineType.self,
                rawValue: underlineTypeLawValue
            )
        }
        self.underlineType = underlineType

        underlineShape = try reader.readInt(4)

        let borderlineTypeLawValue = try reader.readInt(3)
        guard let borderlineType = HwpBorderLineType(rawValue: borderlineTypeLawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpBorderLineType.self,
                rawValue: borderlineTypeLawValue
            )
        }
        self.borderlineType = borderlineType

        let shadowTypeLawValue = try reader.readInt(2)
        guard let shadowType = HwpShadowType(rawValue: shadowTypeLawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpShadowType.self,
                rawValue: shadowTypeLawValue
            )
        }
        self.shadowType = shadowType

        isRelief = try reader.readBit()
        isCounterRelief = try reader.readBit()
        isSuperscript = try reader.readBit()
        isSubscript = try reader.readBit()
        reserved = try reader.readBit()
        strikethrough = try reader.readInt(3)

        let emphasisTypeLawValue = try reader.readInt(4)
        guard let emphasisType = HwpEmphasisType(rawValue: emphasisTypeLawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpEmphasisType.self,
                rawValue: emphasisTypeLawValue
            )
        }
        self.emphasisType = emphasisType

        doesAdjustBlank = try reader.readBit()
        strikethroughShape = try reader.readInt(4)
        isKerning = try reader.readBit()

        try reader.readBits(1)
    }

    static func load(_ uint: UIntType) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

extension HwpCharShapeProperty {
    init() {
        rawValue = 0
        isItalic = false
        isBold = false
        underlineType = .none
        underlineShape = 0
        borderlineType = .none
        shadowType = .none
        isRelief = false
        isCounterRelief = false
        isSuperscript = false
        isSubscript = false
        reserved = false
        strikethrough = 0
        emphasisType = .none
        doesAdjustBlank = false
        strikethroughShape = 0
        isKerning = false
    }
}

public enum HwpUnderlineType: Int, HwpPrimitive {
    /** 0: 없음 */
    case none = 0
    /** 1: 글자 아래 */
    case under = 1
    /** 3: 글자 위 */
    case above = 2
}

public enum HwpBorderLineType: Int, HwpPrimitive {
    /** 0: 없음 */
    case none = 0
    /** 1: 실선 */
    case line = 1
    /** 2: 점선 */
    case dot = 2
    /** 3: 굵은 실선(두꺼운 선) */
    case thickLine = 3
    /** 4: 파선(긴 점선) */
    case loneDot = 4
    /** 5: 일점쇄선 (-.-.-.-.) */
    case oneDotOneLine = 5
    /** 6: 이점쇄선 (-..-..-..) */
    case twoDotsOneLine = 6
}

public enum HwpShadowType: Int, HwpPrimitive {
    /** 0: 없음 */
    case none = 0
    /** 1: 비연속 */
    case discontinuous = 1
    /** 2: 연속 */
    case continuous = 2
}

public enum HwpEmphasisType: Int, HwpPrimitive {
    /** 0: 없음 */
    case none = 0
    /** 1: 검정 동그라미 강조점 */
    case filledCircle = 1
    /** 2: 속 빈 동그라미 강조점 */
    case outlinedCircle = 2
    /** 3: ˇ(반대 곡절 부호) */
    case caron = 3
    /** 4:  ̃ (틸드) */
    case tilde = 4
    /** 5: ・ (가운뎃점) */
    case interpunct = 5
    /** 6: : (쌍점) */
    case colon = 6
}
