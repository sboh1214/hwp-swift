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
    init(_ reader: inout DataReader) throws {
        data = try reader.readToEnd()
        rawPayload = data
        unknownChildren = []
    }
}

extension HwpForbiddenChar: HwpFromRecord {
    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .forbiddenChar, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        data = try reader.readToEnd()
        rawPayload = data
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
