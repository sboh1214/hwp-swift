import Foundation

/**
 문서 내 캐럿의 위치 정보
 */
public struct HwpCaratLocation: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 리스트 아이디 */
    public var listId: UInt32
    /** 문단 아이디 */
    public var paragraphId: UInt32
    /** 문단 내에서의 글자 단위 위치 */
    public var charIndex: UInt32

    init() {
        rawPayload = Data()
        listId = 0
        paragraphId = 0
        charIndex = 16
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        listId = try reader.read(UInt32.self)
        paragraphId = try reader.read(UInt32.self)
        charIndex = try reader.read(UInt32.self)
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var caratLocation = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        caratLocation.rawPayload = data
        return caratLocation
    }
}
