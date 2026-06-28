import Foundation

/**
 4.3.10.1.3. 쪽 테두리/배경

 Tag ID : HWPTAG_PAGE_BORDER_FILL
 */
public struct HwpPageBorderFill {
    /** 속성 */
    public var property: UInt32
    /** 테두리/배경 위치 왼쪽 간격 */
    public var spacingLeft: HWPUNIT16
    /** 테두리/배경 위치 오른쪽 간격 */
    public var spacingRight: HWPUNIT16
    /** 테두리/배경 위치 위쪽 간격 */
    public var spacingTop: HWPUNIT16
    /** 테두리/배경 위치 아래쪽 간격 */
    public var spacingBottom: HWPUNIT16
    /** 테두리/배경 ID */
    public var borderFillId: UInt16
    /** raw payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
}

extension HwpPageBorderFill: HwpFromData {
    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        property = try reader.read(UInt32.self)
        spacingLeft = try reader.read(HWPUNIT16.self)
        spacingRight = try reader.read(HWPUNIT16.self)
        spacingTop = try reader.read(HWPUNIT16.self)
        spacingBottom = try reader.read(HWPUNIT16.self)
        borderFillId = try reader.read(UInt16.self)
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var pageBorderFill = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        pageBorderFill.rawPayload = data
        return pageBorderFill
    }
}

extension HwpPageBorderFill {
    init(property: UInt32) {
        self.property = property
        spacingLeft = 1417
        spacingRight = 1417
        spacingTop = 1417
        spacingBottom = 1417
        borderFillId = 1
        rawPayload = Data()
        rawTrailing = Data()
    }
}
