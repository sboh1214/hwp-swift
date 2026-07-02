import Foundation

public struct HwpCtrlHeader {
    public var ctrlId: UInt32
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    public init(ctrlId: UInt32, rawPayload: Data) {
        self.ctrlId = ctrlId
        self.rawPayload = rawPayload
        unknownChildren = []
    }

    public init(ctrlId: UInt32, rawPayload: Data, unknownChildren: [HwpUnknownRecord]) {
        self.ctrlId = ctrlId
        self.rawPayload = rawPayload
        self.unknownChildren = unknownChildren
    }
}

extension HwpCtrlHeader: HwpPrimitive {
    // MARK: loader contract exemption - malformed ctrl header still preserves raw payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        do {
            ctrlId = try reader.read(UInt32.self)
        } catch HwpError.truncatedData {
            ctrlId = 0
        }
        _ = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates control-header tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        return try self.init(&reader, record.children)
    }
}
