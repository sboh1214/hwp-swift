import Foundation

/**
 레이아웃 호환성

 Tag ID : HWPTAG_LAYOUT_COMPATIBILITY
 */
public struct HwpLayoutCompatibility: HwpFromData {
    /** 글자 단위 서식 */
    public let char: UInt32
    /** 문단 단위 서식 */
    public let paragraph: UInt32
    /** 구역 단위 서식 */
    public let section: UInt32
    /** 개체 단위 서식 */
    public let object: UInt32
    /** 필드 단위 서식 */
    public let field: UInt32
    /** 알려진 고정 폭 필드의 원문 payload */
    @ExcludeEquatable
    public var fixedFieldsRawPayload: Data
    @ExcludeEquatable
    public var rawPayload: Data
    @ExcludeEquatable
    public var unknownChildren: [HwpUnknownRecord]

    init() {
        char = 0
        paragraph = 0
        section = 0
        object = 0
        field = 0
        fixedFieldsRawPayload = Data()
        rawPayload = Data()
        unknownChildren = []
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        char = try reader.read(UInt32.self)
        paragraph = try reader.read(UInt32.self)
        section = try reader.read(UInt32.self)
        object = try reader.read(UInt32.self)
        field = try reader.read(UInt32.self)
        let consumedPayload = try reader.consumedData(from: startOffset)
        fixedFieldsRawPayload = consumedPayload
        rawPayload = consumedPayload
        unknownChildren = []
    }
}

extension HwpLayoutCompatibility: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        try validateDocInfoRecordTag(record, expectedTag: .layoutCompatibility)

        var reader = DataReader(record.payload)
        var layoutCompatibility = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        layoutCompatibility.rawPayload = record.payload
        return layoutCompatibility
    }
}
