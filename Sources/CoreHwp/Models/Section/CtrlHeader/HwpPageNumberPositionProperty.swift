/**
 4.3.10.9. 쪽 번호 위치 속성

 쪽 번호의 번호 모양과 표시 위치를 나타내는 속성이다.
 */
public struct HwpPageNumberPositionProperty {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 번호 모양 */
    public var numberFormat: Int
    /** 번호의 표시 위치 */
    public var displayPosition: Int
}

extension HwpPageNumberPositionProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        numberFormat = try reader.readInt(8)
        displayPosition = try reader.readInt(4)
        try reader.readBits(20)
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

extension HwpPageNumberPositionProperty {
    init() {
        rawValue = 0
        numberFormat = 0
        displayPosition = 0
    }
}
