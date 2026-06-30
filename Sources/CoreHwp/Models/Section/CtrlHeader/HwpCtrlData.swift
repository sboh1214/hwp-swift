import Foundation

/** 컨트롤 데이터 */
public struct HwpCtrlData {
    /** 원본 payload */
    public var rawPayload: Data
    /** 알려진 ParameterSet payload를 해석한 값 */
    public var parameterSet: HwpCtrlDataParameterSet?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    /** 기존 raw record assertion과 호환되는 payload alias */
    public var payload: Data {
        rawPayload
    }
}

extension HwpCtrlData: HwpFromRecord {
    // MARK: loader contract exemption - validates CTRL_DATA tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlData)

        var reader = DataReader(record.payload)
        return try self.init(&reader, record.children)
    }

    // MARK: loader contract exemption - CTRL_DATA payload is currently opaque raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        parameterSet = HwpCtrlDataParameterSet(rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
