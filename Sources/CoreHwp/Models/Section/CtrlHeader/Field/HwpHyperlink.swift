import Foundation

/** 하이퍼링크 필드 */
public struct HwpHyperlink {
    /** ctrl id */
    public var ctrlId: UInt32
    /** 속성 */
    public var property: UInt32
    /** 아직 해석하지 않은 prefix byte */
    public var unknownPrefix: BYTE
    /** URL 길이 */
    public var urlLength: WORD
    /** URL 길이 원문 WORD payload */
    public var urlLengthRawPayload: Data
    /** URL */
    public var url: String
    /** URL 원문 WCHAR payload */
    public var urlRawPayload: Data
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
    /** 원본 payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    public init() {
        ctrlId = HwpFieldCtrlId.hyperLink.rawValue
        property = 0
        unknownPrefix = 0
        urlLength = 0
        urlLengthRawPayload = Data()
        url = ""
        urlRawPayload = Data()
        rawTrailing = Data()
        rawPayload = Data()
        unknownChildren = []
    }

    public init(
        ctrlId: UInt32,
        property: UInt32,
        unknownPrefix: BYTE,
        urlLength: WORD,
        urlLengthRawPayload: Data,
        url: String,
        urlRawPayload: Data,
        rawTrailing: Data,
        rawPayload: Data,
        unknownChildren: [HwpUnknownRecord]
    ) {
        self.ctrlId = ctrlId
        self.property = property
        self.unknownPrefix = unknownPrefix
        self.urlLength = urlLength
        self.urlLengthRawPayload = urlLengthRawPayload
        self.url = url
        self.urlRawPayload = urlRawPayload
        self.rawTrailing = rawTrailing
        self.rawPayload = rawPayload
        self.unknownChildren = unknownChildren
    }
}

extension HwpHyperlink: HwpPrimitive {
    // MARK: loader contract exemption - preserves hyperlink trailing payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        ctrlId = try reader.read(UInt32.self)
        guard ctrlId == HwpFieldCtrlId.hyperLink.rawValue else {
            throw HwpError.invalidCtrlId(ctrlId: ctrlId)
        }
        property = try reader.read(UInt32.self)
        unknownPrefix = try reader.read(BYTE.self)
        let urlLengthStartOffset = reader.byteOffset
        urlLength = try reader.read(WORD.self)
        urlLengthRawPayload = try reader.consumedData(from: urlLengthStartOffset)
        let urlStartOffset = reader.byteOffset
        let urlCharacters = try reader.read(WCHAR.self, urlLength)
        urlRawPayload = try reader.consumedData(from: urlStartOffset)
        url = try urlCharacters.string
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates hyperlink control tag before decoding

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var hyperlink = try self.init(&reader, record.children)
        hyperlink.rawPayload = record.payload
        return hyperlink
    }
}
