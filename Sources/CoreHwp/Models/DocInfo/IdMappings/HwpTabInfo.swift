import Foundation

/**
 탭 정보 (count 개수)
 */
public struct HwpTabInfo {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 탭의 위치 */
    public let location: HWPUNIT
    /**
     탭의 종류

     값 설명
     0 왼쪽
     1 오른쪽
     2 가운데
     3 소수점
     */
    public let type: UInt8
    /** 채움 종류 */
    public let fillType: UInt8
    /** 8 바이트를 맞추기 위한 예약 */
    public let reserved: UInt16
}

extension HwpTabInfo: HwpFromData {
    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        location = try reader.read(HWPUNIT.self)
        type = try reader.read(UInt8.self)
        fillType = try reader.read(UInt8.self)
        reserved = try reader.read(UInt16.self)
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var tabInfo = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        tabInfo.rawPayload = data
        return tabInfo
    }
}
