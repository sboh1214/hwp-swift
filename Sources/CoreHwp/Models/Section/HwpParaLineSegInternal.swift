public struct HwpParaLineSegInternal: HwpPrimitive {
    /** 텍스트 시작 위치 */
    public let textStartingIndex: UInt32
    /** 줄의 세로 위치 */
    public let lineLocation: Int32
    /** 줄의 높이 */
    public let lineHeight: Int32
    /** 텍스트 부분의 높이 */
    public let textHeight: Int32
    /** 줄의 세로 위치에서 베이스라인까지 거리 */
    public let baselineDistance: Int32
    /** 줄간격 */
    public let lineSpacing: Int32
    /** 컬럼에서의 시작 위치 */
    public let startingLocation: Int32
    /** 세그먼트의 폭 */
    public let width: Int32
    /**
     태그
     - bit 0 : 페이지의 첫 줄인지 여부
     - bit 1 : 컬럼의 첫 줄인지 여부
     - bit 16 : 텍스트가 배열되지 않은 빈 세그먼 트인지 여부
     - bit 17 : 줄의 첫 세그먼트인지 여부
     - bit 18 : 줄의 마지막 세그먼트인지 여부
     - bit 19 : 줄의 마지막에 auto-hyphenation이 수행되었는지 여부.
     - bit 20 : indentation 적용
     - bit 21 : 문단 머리 모양 적용
     - bit 31 : 구현상의 편의를 위한 property
     */
    public let property: UInt32

    init() {
        textStartingIndex = 0
        lineLocation = 0
        lineHeight = 1000
        textHeight = 1000
        baselineDistance = 850
        lineSpacing = 600
        startingLocation = 0
        width = 42520
        property = 393_216
    }

    init(_ reader: inout DataReader) throws {
        textStartingIndex = try reader.read(UInt32.self)
        lineLocation = try reader.read(Int32.self)
        lineHeight = try reader.read(Int32.self)
        textHeight = try reader.read(Int32.self)
        baselineDistance = try reader.read(Int32.self)
        lineSpacing = try reader.read(Int32.self)
        startingLocation = try reader.read(Int32.self)
        width = try reader.read(Int32.self)
        property = try reader.read(UInt32.self)
    }
}
