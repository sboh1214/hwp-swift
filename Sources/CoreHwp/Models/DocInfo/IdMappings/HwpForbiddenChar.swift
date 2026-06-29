import Foundation

public struct HwpForbiddenChar {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public let data: Data
    public let unknownChildren: [HwpUnknownRecord]

    public init(
        data: Data,
        rawPayload: Data? = nil,
        unknownChildren: [HwpUnknownRecord] = []
    ) {
        self.rawPayload = rawPayload ?? data
        self.data = data
        self.unknownChildren = unknownChildren
    }
}

extension HwpForbiddenChar: HwpFromData {
    // MARK: loader contract exemption - forbidden-char payload is stored as opaque raw data

    init(_ reader: inout DataReader) throws {
        data = try reader.readToEnd()
        rawPayload = data
        unknownChildren = []
    }
}

extension HwpForbiddenChar: HwpFromRecord {
    // MARK: loader contract exemption - validates DocInfo tag before preserving raw payload

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .forbiddenChar, as: Self.self)
    }

    // MARK: loader contract exemption - forbidden-char record payload is opaque raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        data = try reader.readToEnd()
        rawPayload = data
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
