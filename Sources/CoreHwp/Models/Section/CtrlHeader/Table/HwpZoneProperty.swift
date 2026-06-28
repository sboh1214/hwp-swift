public struct HwpZoneProperty {
    /** 시작 열 주소 */
    public var startColumnIndex: UInt16
    /** 시작 행 주소 */
    public var startRowIndex: UInt16
    /** 끝 열 주소 */
    public var endColumnIndex: UInt16
    /** 끝 행 주소 */
    public var endRowIndex: UInt16
    /** 테두리 채우기 ID */
    public var borderFillId: UInt16
}

extension HwpZoneProperty: HwpFromData {
    init(_ reader: inout DataReader) throws {
        startColumnIndex = try reader.read(UInt16.self)
        startRowIndex = try reader.read(UInt16.self)
        endColumnIndex = try reader.read(UInt16.self)
        endRowIndex = try reader.read(UInt16.self)
        borderFillId = try reader.read(UInt16.self)
    }
}
