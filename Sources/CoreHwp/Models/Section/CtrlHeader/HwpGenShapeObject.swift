import Foundation

public struct HwpGenShapeObject {
    /** ctrl id */
    public var commonCtrlProperty: HwpCommonCtrlProperty
    /** 원본 payload */
    public var rawPayload: Data
    /** 개체 공통 속성 뒤에 남은 원본 payload */
    public var rawTrailing: Data
    /** 개체 요소 공통 레코드 */
    public var shapeComponentArray: [HwpShapeComponent]
    /** 컨트롤 데이터 child record */
    public var ctrlDataRecords: [HwpCtrlData]
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpGenShapeObject: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader, children, nil)
    }

    init(
        _ reader: inout DataReader,
        _ children: [HwpRecord],
        _ version: HwpVersion?
    ) throws {
        let startOffset = reader.byteOffset
        commonCtrlProperty = try HwpCommonCtrlProperty(&reader)
        guard commonCtrlProperty.commonCtrlId == .genShapeObject else {
            throw HwpError.invalidCtrlId(ctrlId: commonCtrlProperty.commonCtrlId.rawValue)
        }
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        shapeComponentArray = try children
            .filter { $0.tagId == HwpSectionTag.shapeComponent.rawValue }
            .map {
                if let version {
                    return try HwpShapeComponent.load($0, version)
                }
                return try HwpShapeComponent.load($0)
            }
        ctrlDataRecords = try children
            .filter { $0.tagId == HwpSectionTag.ctrlData.rawValue }
            .map { try HwpCtrlData.load($0) }
        unknownChildren = children
            .filter {
                $0.tagId != HwpSectionTag.shapeComponent.rawValue
                    && $0.tagId != HwpSectionTag.ctrlData.rawValue
            }
            .map(HwpUnknownRecord.init)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var object = try self.init(&reader, record.children)
        object.rawPayload = record.payload
        return object
    }

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var object = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        object.rawPayload = record.payload
        return object
    }
}
