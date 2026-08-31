public struct HwpColumnProperty {
    public var rawValue: UInt16
    public var type: HwpColumnType
    public var count: Int
    public var direction: HwpColumnDirection
    public var isSameWidth: Bool
}

extension HwpColumnProperty: HwpFromUInt {
    typealias UIntType = UInt16

    init(_ reader: inout BitsReader<UInt16>) throws {
        rawValue = 0
        let typeRawValue = try reader.readInt(2)
        guard let type = HwpColumnType(rawValue: typeRawValue) else {
            throw HwpError.invalidRawValueForEnum(model: HwpColumnType.self, rawValue: typeRawValue)
        }
        self.type = type

        count = try reader.readInt(8)

        let directionRawValue = try reader.readInt(2)
        guard let direction = HwpColumnDirection(rawValue: directionRawValue) else {
            throw HwpError.invalidRawValueForEnum(
                model: HwpColumnDirection.self,
                rawValue: directionRawValue
            )
        }
        self.direction = direction

        isSameWidth = try reader.readBit()

        try reader.readBits(3)
    }

    static func load(_ uint: UInt16) throws -> Self {
        var reader = BitsReader(from: uint)
        var property = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        property.rawValue = uint
        return property
    }
}

extension HwpColumnProperty {
    /// typed 필드에서 bit field를 되만든다 — 위 `init(_ reader:)`의 읽기
    /// 순서를 그대로 뒤집는다. 후미 예약 3비트는 0으로 둔다.
    var synthesizedRawValue: UInt16 {
        var raw: UInt16 = 0
        var offset = 0
        func put(_ value: Int, width: Int) {
            raw |= UInt16(value & ((1 << width) - 1)) << offset
            offset += width
        }
        put(type.rawValue, width: 2)
        put(count, width: 8)
        put(direction.rawValue, width: 2)
        put(isSameWidth ? 1 : 0, width: 1)
        return raw
    }

    init() {
        rawValue = 0
        type = .general
        count = 1
        direction = .left
        isSameWidth = true
    }
}

public enum HwpColumnType: Int, HwpPrimitive {
    /** 일반 다단 */
    case general = 0
    /** 배분 다단 */
    case div = 1
    /** 평행 다단 */
    case along = 2
}

public enum HwpColumnDirection: Int, HwpPrimitive {
    /** 왼쪽부터 */
    case left = 0
    /** 오른쪽부터 */
    case right = 1
    /** 맞쪽 */
    case yang = 2
}
