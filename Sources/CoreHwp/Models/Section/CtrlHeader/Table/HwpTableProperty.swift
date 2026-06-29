import Foundation

private let hwpZonePropertyByteCount = MemoryLayout<UInt16>.size * 5

public struct HwpTableProperty {
    /** 속성 */
    public var property: UInt32
    /** RowCount */
    public var rowCount: UInt16
    /** nCols */
    public var columnCount: UInt16
    /** CellSpacing */
    public var cellSpacing: HWPUNIT16
    /** 왼쪽 여백 */
    public var leftInnerMargin: HWPUNIT16
    /** 오른쪽 여백 */
    public var rightInnerMargin: HWPUNIT16
    /** 위쪽 여백 */
    public var topInnerMargin: HWPUNIT16
    /** 아래쪽 여백 */
    public var bottomInnerMargin: HWPUNIT16
    /** Row Size */
    public var rowSize: [BYTE]
    /** Border Fill ID */
    public var borderFillId: UInt16
    /**
     Valid Zone Info Size

     (5.0.1.0 이상)
     */
    public var validZoneInfoSize: UInt16?
    /**
     영역 속성

     (5.0.1.0 이상)
     */
    public var zonePropertyArray: [HwpZoneProperty]?
    /** raw payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
}

extension HwpTableProperty: HwpFromDataWithVersion {
    // MARK: loader contract exemption - preserves table-property trailing payload

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt32.self)
        rowCount = try reader.read(UInt16.self)
        columnCount = try reader.read(UInt16.self)
        cellSpacing = try reader.read(HWPUNIT16.self)
        leftInnerMargin = try reader.read(HWPUNIT16.self)
        rightInnerMargin = try reader.read(HWPUNIT16.self)
        topInnerMargin = try reader.read(HWPUNIT16.self)
        bottomInnerMargin = try reader.read(HWPUNIT16.self)
        let rowSizeByteCount = Int(rowCount) * MemoryLayout<UInt16>.size
        rowSize = try reader.readBytes(rowSizeByteCount).bytes
        borderFillId = try reader.read(UInt16.self)
        if version >= HwpVersion(5, 0, 1, 0) {
            let zonePropertySize = try reader.read(UInt16.self)
            let requiredZoneByteCount = Int(zonePropertySize) * hwpZonePropertyByteCount
            guard requiredZoneByteCount <= reader.remainBytes else {
                throw HwpError.truncatedData(
                    expected: requiredZoneByteCount,
                    actual: reader.remainBytes
                )
            }
            validZoneInfoSize = zonePropertySize
            zonePropertyArray = try (0 ..< zonePropertySize).map { _ in
                try HwpZoneProperty(&reader)
            }
        }
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - restores complete table-property rawPayload

    static func load(_ data: Data, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(data)
        var tableProperty = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        tableProperty.rawPayload = data
        return tableProperty
    }
}
