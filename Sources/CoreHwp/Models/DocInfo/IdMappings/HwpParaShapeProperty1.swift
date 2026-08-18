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

    /**
     문단 수준 (표 44 bit 25-27)

     **저장값은 0-기반이다** — 사람이 읽는 수준은 `headingLevelRawValue + 1`이다.
     스펙이 적은 "1수준~7수준"은 의미 범위 표기일 뿐 저장 기점이 아니고, 스펙은
     기점을 명시하지 않는다. 기점은 실측으로 확정했다 (#77):
     `legacy-common-control-property`(헌법주석)에서 `headingTypeRawValue == 1`인
     문단 1,944개의 이 값 분포가 `0: 280, 1: 512, 2: 486, 3: 301, 4: 244, 5: 100,
     6: 21`이고, **같은 문단들의 스타일 이름 분포가 개수까지 정확히 일치한다**
     (`개요 1`: 280 … `개요 7`: 21). 즉 `개요 N` ↔ 이 값 `N - 1`이다.

     3비트이므로 담을 수 있는 범위는 0...7, 즉 1수준~**8**수준이다 ("3비트라
     7수준까지"가 아니다). 표현 불가한 것은 9·10수준뿐이며, 애초에 `개요 8` 이상
     스타일은 문단 머리 모양이 개요로 설정돼 있지 않아
     (`headingTypeRawValue == 0`) 이 비트 경로로는 잡히지 않는다 — 그런 문단의
     수준은 스타일 이름(`개요 N` / `Outline N`)에서 읽는다.

     `headingTypeRawValue != 1`인 문단에서도 비트 자체는 읽히지만 의미가 없다 —
     개요 수준으로 해석하기 전에 머리 모양 종류를 먼저 확인할 것.
     */
    var headingLevelRawValue: UInt32 {
        (rawValue >> 25) & 0b111
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
