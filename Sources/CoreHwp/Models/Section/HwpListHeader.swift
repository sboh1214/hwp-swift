import Foundation

/**
 문단 리스트 헤더

 Tag ID : HWPTAG_LIST_HEADER
 */
public struct HwpListHeader: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /**
     문단 수

     한글문서에선 Int16으로 되어있으나 대부분의 경우 Int32 으로 읽어야 문제가 없다
     */
    public let paragraphCount: Int32
    public let property: UInt32
    /** 아직 해석하지 않은 trailing bytes */
    public let rawTrailing: Data
    /** trailing bytes를 little-endian WORD 단위로 해석한 값 */
    public let rawTrailingWords: [UInt16]?

    init() {
        rawPayload = Data()
        paragraphCount = 0
        property = 0
        rawTrailing = Data()
        rawTrailingWords = []
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        paragraphCount = try reader.read(Int32.self)
        property = try reader.read(UInt32.self)
        rawTrailing = try reader.readToEnd()
        rawTrailingWords = rawTrailing.littleEndianUInt16ArrayIfAligned()
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var listHeader = try self.init(&reader)
        listHeader.rawPayload = data
        return listHeader
    }
}
