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

    /// HWPX 합성 전용 — DOCUMENT_PROPERTIES record가 없으므로 구역 수와
    /// 시작 번호만 싣고 캐럿 위치는 기본값이다.
    init(hwpxSectionSize sectionSize: UInt16, startingIndex: HwpStartingIndex) {
        rawPayload = Data()
        self.sectionSize = sectionSize
        self.startingIndex = startingIndex
        caratLocation = HwpCaratLocation()
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        sectionSize = try reader.read(UInt16.self)
        startingIndex = try HwpStartingIndex.load(
            try reader.readBytes(12),
            options: reader.options
        )
        caratLocation = try HwpCaratLocation.load(
            try reader.readBytes(12),
            options: reader.options
        )
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data, options: HwpLoadOptions = .default) throws -> Self {
        var reader = DataReader(data, options: options)
        var documentProperties = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        documentProperties.rawPayload = options.preservedPayload(data)
        return documentProperties
    }
}
