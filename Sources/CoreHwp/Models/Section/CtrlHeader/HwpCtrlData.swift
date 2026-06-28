import Foundation

/** 컨트롤 데이터 */
public struct HwpCtrlData {
    /** 원본 payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    /** 기존 raw record assertion과 호환되는 payload alias */
    public var payload: Data {
        rawPayload
    }
}

extension HwpCtrlData: HwpFromRecord {
    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlData)

        var reader = DataReader(record.payload)
        return try self.init(&reader, record.children)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
