import Foundation

/**
 본문
 */
public struct HwpSection: HwpFromDataWithVersion {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public var paragraph: [HwpParagraph]
    public var unknownRecords: [HwpUnknownRecord]

    init() {
        rawPayload = Data()
        paragraph = [HwpParagraph()]
        unknownRecords = []
    }

    // MARK: loader contract exemption - BodyText section stream must be parsed as one record tree

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let records = try parseTreeRecord(data: try reader.readToEnd())
        var paragraphs = [HwpParagraph]()
        var unknownRecords = [HwpUnknownRecord]()

        for record in records.children {
            if record.tagId == HwpSectionTag.paraHeader.rawValue {
                paragraphs.append(try HwpParagraph.load(record, version))
            } else {
                unknownRecords.append(HwpUnknownRecord(record))
            }
        }

        guard !paragraphs.isEmpty else {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.paraHeader.rawValue)
        }

        paragraph = paragraphs
        self.unknownRecords = unknownRecords
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - raw section payload is restored after record-tree parse

    public static func load(_ data: Data, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(data)
        var section = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        section.rawPayload = data
        return section
    }
}
