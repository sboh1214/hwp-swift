/**
 4.3.11.1. 필드 속성

 필드 컨트롤의 속성을 나타내는 bit field이다.
 */
public struct HwpFieldControlProperty {
    /** 원본 bit field */
    public var rawValue: UInt32
    /** 필드 내용이 한컴 초기 상태인지 여부 */
    public var isInitialState: Bool
}

extension HwpFieldControlProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UInt32>) throws {
        rawValue = 0
        try reader.readBits(15)
        isInitialState = try !reader.readBit()
        try reader.readBits(16)
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

extension HwpFieldControlProperty {
    init() {
        rawValue = 0
        isInitialState = true
    }
}
