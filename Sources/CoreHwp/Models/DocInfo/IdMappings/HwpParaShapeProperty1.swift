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

    /**
     줄 간격 종류 (표 44 bit 0-1). 한글 2007 이하 버전(5.0.2.5 미만)에서 사용.

     5.0.2.5 이상은 속성3 (표 46)의 줄 간격 종류가 우선한다 —
     `HwpParaShape.resolvedLineSpacingKind` 참조.
     */
    var lineSpacingKind: HwpLineSpacingKind {
        HwpLineSpacingKind(rawValue: rawValue & 0b11) ?? .percent
    }

    /** 정렬 방식 (표 44 bit 2-4): 0 양쪽, 1 왼쪽, 2 오른쪽, 3 가운데, 4 배분, 5 나눔 */
    var alignmentRawValue: UInt32 {
        (rawValue >> 2) & 0b111
    }

    /** 문단 머리 모양 종류 (표 44 bit 23-24): 0 없음, 1 개요, 2 번호, 3 글머리표 */
    var headingTypeRawValue: UInt32 {
        (rawValue >> 23) & 0b11
    }

    /** 글머리표 문단 여부 */
    var hasBulletHeading: Bool {
        headingTypeRawValue == 3
    }
}

/**
 줄 간격 종류 (표 44 bit 0-1, 표 46 bit 0-4)

 `percent`의 값은 %, 나머지 종류의 값은 HWPUNIT이다.
 */
public enum HwpLineSpacingKind: UInt32, HwpPrimitive {
    /** 글자에 따라(%) — 줄 높이 = 글자 크기 × 값 / 100 */
    case percent = 0
    /** 고정값 (HWPUNIT) */
    case fixed = 1
    /** 여백만 지정 (HWPUNIT) */
    case marginOnly = 2
    /** 최소 (HWPUNIT, 표 46 전용 — 5.0.2.5 이상) */
    case atLeast = 3
}
