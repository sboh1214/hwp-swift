import Foundation

public struct HwpCtrlHeader {
    public var ctrlId: UInt32
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpCtrlHeader: HwpPrimitive {
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

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        return try self.init(&reader, record.children)
    }
}
