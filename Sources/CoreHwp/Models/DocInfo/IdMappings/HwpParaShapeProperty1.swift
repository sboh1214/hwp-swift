/**
 4.2.10. 문단 모양 속성1

 문단 모양의 정렬, 줄 간격, 문단 테두리 동작을 나타내는 bit field이다.
 */
public struct HwpParaShapeProperty1 {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 문단 테두리 연결 여부 */
    public var borderConnect: Bool
    /** 문단 여백 무시 여부 */
    public var borderIgnoreMargin: Bool
}

extension HwpParaShapeProperty1: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        try reader.readBits(28)
        borderConnect = try reader.readBit()
        borderIgnoreMargin = try reader.readBit()
        try reader.readBits(2)
    }

    public static func load(_ uint: UInt32) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

public extension HwpParaShapeProperty1 {
    init(rawValue: UInt32) {
        self.rawValue = rawValue
        borderConnect = rawValue & (1 << 28) != 0
        borderIgnoreMargin = rawValue & (1 << 29) != 0
    }

    init() {
        self.init(rawValue: 0)
    }
}
