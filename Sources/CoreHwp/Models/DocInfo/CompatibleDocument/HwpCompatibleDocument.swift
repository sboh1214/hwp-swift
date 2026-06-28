import Foundation

/**
 호환 문서

 Tag ID : HWPTAG_COMPATIBLE_DOCUMENT
 */
public struct HwpCompatibleDocument: HwpFromRecord {
    /** 대상 프로그램 */
    public let targetDocument: UInt32
    /** 대상 프로그램 필드의 원문 payload */
    @ExcludeEquatable
    public var targetDocumentRawPayload: Data
    public let layoutCompatibility: HwpLayoutCompatibility?
    @ExcludeEquatable
    public var trackChangeArray: [HwpTrackChange]
    @ExcludeEquatable
    public var rawPayload: Data
    @ExcludeEquatable
    public var unknownChildren: [HwpUnknownRecord]

    init() {
        targetDocument = 0
        targetDocumentRawPayload = Data()
        layoutCompatibility = HwpLayoutCompatibility()
        trackChangeArray = []
        rawPayload = Data()
        unknownChildren = []
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        targetDocument = try reader.read(UInt32.self)
        let targetPayload = try reader.consumedData(from: startOffset)
        targetDocumentRawPayload = targetPayload

        if let layoutCompatibility = children
            .first(where: { $0.tagId == HwpDocInfoTag.layoutCompatibility.rawValue })
        {
            self.layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibility)
        } else {
            layoutCompatibility = nil
        }
        trackChangeArray = try children
            .filter { $0.tagId == HwpDocInfoTag.trackChange.rawValue }
            .map(HwpTrackChange.load)
        rawPayload = targetPayload
        unknownChildren = Self.unconsumedRecords(from: children).map(HwpUnknownRecord.init)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        try validateDocInfoRecordTag(record, expectedTag: .compatibleDocument)

        var reader = DataReader(record.payload)
        var compatibleDocument = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        compatibleDocument.rawPayload = record.payload
        return compatibleDocument
    }
}

private extension HwpCompatibleDocument {
    static func unconsumedRecords(from children: [HwpRecord]) -> [HwpRecord] {
        var didConsumeLayoutCompatibility = false

        return children.filter { child in
            guard child.tagId == HwpDocInfoTag.layoutCompatibility.rawValue else {
                return child.tagId != HwpDocInfoTag.trackChange.rawValue
            }

            if didConsumeLayoutCompatibility {
                return true
            }
            didConsumeLayoutCompatibility = true
            return false
        }
    }
}
