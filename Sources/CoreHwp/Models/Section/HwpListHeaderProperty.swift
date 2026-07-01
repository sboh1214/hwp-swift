/**
 4.3.7. 문단 리스트 헤더

 문단 리스트의 텍스트 방향, 줄바꿈 방식, 세로 정렬을 나타내는 bit field이다.
 */
public struct HwpListHeaderProperty {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 텍스트 방향 raw 값 */
    public var textDirectionRawValue: Int
    /** 줄바꿈 방식 raw 값 */
    public var textWrapRawValue: Int
    /** 세로 정렬 raw 값 */
    public var verticalAlignmentRawValue: Int
    /** 세로 정렬 */
    public var verticalAlignment: HwpListHeaderVerticalAlignment?
}

extension HwpListHeaderProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        try reader.readBits(16)
        textDirectionRawValue = try reader.readInt(3)
        textWrapRawValue = try reader.readInt(2)
        verticalAlignmentRawValue = try reader.readInt(2)
        verticalAlignment = HwpListHeaderVerticalAlignment(rawValue: verticalAlignmentRawValue)
        try reader.readBits(9)
    }

    static func load(_ uint: UInt32) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

extension HwpListHeaderProperty {
    init() {
        rawValue = 0
        textDirectionRawValue = 0
        textWrapRawValue = 0
        verticalAlignmentRawValue = 0
        verticalAlignment = .top
    }
}

public enum HwpListHeaderVerticalAlignment: Int, HwpPrimitive {
    /** 위 */
    case top = 0
    /** 가운데 */
    case center = 1
    /** 아래 */
    case bottom = 2
}
