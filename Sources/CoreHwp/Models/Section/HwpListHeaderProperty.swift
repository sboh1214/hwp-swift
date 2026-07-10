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
        // 실측 이중 레이아웃: 한/글 윈도우 저장본 (noori)은 표 89 필드를
        // bits 16-22에, 한컴오피스 mac 저장본 (text-box)은 스펙 문서 그대로
        // bits 0-6에 둔다. 상위 레이아웃이 하나라도 설정되어 있으면 상위,
        // 전부 0이면 하위 레이아웃으로 폴백한다.
        rawValue = 0
        let lowTextDirection = try reader.readInt(3) // bits 0-2
        let lowTextWrap = try reader.readInt(2) // bits 3-4
        let lowVerticalAlignment = try reader.readInt(2) // bits 5-6
        try reader.readBits(9) // bits 7-15
        let highTextDirection = try reader.readInt(3) // bits 16-18
        let highTextWrap = try reader.readInt(2) // bits 19-20
        let highVerticalAlignment = try reader.readInt(2) // bits 21-22
        try reader.readBits(9) // bits 23-31

        let usesHighLayout = highTextDirection != 0
            || highTextWrap != 0
            || highVerticalAlignment != 0
        textDirectionRawValue = usesHighLayout ? highTextDirection : lowTextDirection
        textWrapRawValue = usesHighLayout ? highTextWrap : lowTextWrap
        verticalAlignmentRawValue = usesHighLayout
            ? highVerticalAlignment
            : lowVerticalAlignment
        verticalAlignment = HwpListHeaderVerticalAlignment(rawValue: verticalAlignmentRawValue)
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
