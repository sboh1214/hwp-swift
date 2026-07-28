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
        paragraph = [HwpParagraph.blankDocumentParagraph()]
        unknownRecords = []
    }

    // MARK: loader contract exemption - BodyText section stream must be parsed as one record tree

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let records = try parseTreeRecord(data: try reader.readToEnd(), options: reader.options)
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

    public static func load(
        _ data: Data,
        _ version: HwpVersion,
        options: HwpLoadOptions = .default
    ) throws -> Self {
        // 유일한 public 파싱 진입점이다. `HwpFile` 이니셜라이저와 달리 여기로는
        // 검증되지 않은 한도가 그대로 들어오므로, 비-양수 한도를 "모든 레코드가
        // 거부됨"이 아니라 typed 진단으로 돌려준다.
        try options.readLimits.validate()
        var reader = DataReader(data, options: options)
        var section = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        section.rawPayload = options.preservedPayload(data)
        return section
    }
}
