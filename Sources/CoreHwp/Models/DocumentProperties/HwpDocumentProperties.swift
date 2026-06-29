import Foundation

/**
 문서 속성

 Tag ID : HWPTAG_DOCUMENT_PROPERTIES
 */
public struct HwpDocumentProperties: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** 구역 개수 */
    public var sectionSize: UInt16
    public let startingIndex: HwpStartingIndex
    public let caratLocation: HwpCaratLocation

    init() {
        rawPayload = Data()
        sectionSize = 1
        startingIndex = HwpStartingIndex()
        caratLocation = HwpCaratLocation()
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        sectionSize = try reader.read(UInt16.self)
        startingIndex = try HwpStartingIndex.load(try reader.readBytes(12))
        caratLocation = try HwpCaratLocation.load(try reader.readBytes(12))
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data) throws -> Self {
        var reader = DataReader(data)
        var documentProperties = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        documentProperties.rawPayload = data
        return documentProperties
    }
}
