import Foundation

/** 일반 개체 컨트롤 */
public struct HwpShapeControl {
    /** ctrl id */
    public var ctrlId: HwpCommonCtrlId
    /** 개체 공통 속성. 아직 전체 payload layout을 해석하지 못하면 nil이다. */
    public var commonCtrlProperty: HwpCommonCtrlProperty?
    /** 원본 payload */
    public var rawPayload: Data
    /** 개체 공통 속성 뒤에 남은 원본 payload */
    public var rawTrailing: Data
    /** 개체 요소 공통 레코드 */
    public var shapeComponentArray: [HwpShapeComponent]
    /** 수식 편집 정보 */
    public var eqEditArray: [HwpEquationEdit]
    /** 수식 편집 정보 raw record */
    public var eqEditRecords: [HwpUnknownRecord]
    /** 컨트롤 데이터 child record */
    public var ctrlDataRecords: [HwpCtrlData]
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeControl: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader, children, nil)
    }

    init(
        _ reader: inout DataReader,
        _ children: [HwpRecord],
        _ version: HwpVersion?
    ) throws {
        rawPayload = try reader.readToEnd()

        var ctrlIdReader = DataReader(rawPayload)
        let rawCtrlId = try ctrlIdReader.read(UInt32.self)
        guard let ctrlId = HwpCommonCtrlId(rawValue: rawCtrlId) else {
            throw HwpError.invalidCtrlId(ctrlId: rawCtrlId)
        }
        self.ctrlId = ctrlId

        let parsedProperty = Self.commonCtrlProperty(from: rawPayload)
        commonCtrlProperty = parsedProperty?.property
        if let parsedProperty {
            rawTrailing = parsedProperty.trailing
        } else {
            rawTrailing = try ctrlIdReader.readToEnd()
        }

        shapeComponentArray = try children
            .filter { $0.tagId == HwpSectionTag.shapeComponent.rawValue }
            .map {
                if let version {
                    return try HwpShapeComponent.load($0, version)
                }
                return try HwpShapeComponent.load($0)
            }
        eqEditArray = try children
            .filter { $0.tagId == HwpSectionTag.eqEdit.rawValue }
            .map { try HwpEquationEdit.load($0) }
        eqEditRecords = children
            .filter { $0.tagId == HwpSectionTag.eqEdit.rawValue }
            .map(HwpUnknownRecord.init)
        ctrlDataRecords = try children
            .filter { $0.tagId == HwpSectionTag.ctrlData.rawValue }
            .map { try HwpCtrlData.load($0) }
        unknownChildren = children
            .filter {
                $0.tagId != HwpSectionTag.shapeComponent.rawValue
                    && $0.tagId != HwpSectionTag.eqEdit.rawValue
                    && $0.tagId != HwpSectionTag.ctrlData.rawValue
            }
            .map(HwpUnknownRecord.init)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        let shapeControl = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return shapeControl
    }

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        let shapeControl = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return shapeControl
    }

    private static func commonCtrlProperty(
        from payload: Data
    ) -> (property: HwpCommonCtrlProperty, trailing: Data)? {
        var propertyReader = DataReader(payload)
        do {
            let property = try HwpCommonCtrlProperty(&propertyReader)
            let trailing = try propertyReader.readToEnd()
            return (property, trailing)
        } catch {
            return nil
        }
    }
}

/** 수식 편집 정보 */
public struct HwpEquationEdit {
    /** 원본 payload */
    public var rawPayload: Data
    /** 수식 문자열 길이. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var equationTextLength: UInt16?
    /** 수식 문자열 길이 원문 WORD payload */
    public var equationTextLengthRawPayload: Data?
    /** 수식 문자열. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var equationText: String?
    /** 수식 문자열 원문 WCHAR payload */
    public var equationTextRawPayload: Data?
    /** 수식 문자열 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpEquationEdit: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        equationTextLength = Self.equationTextLength(from: rawPayload)
        equationTextLengthRawPayload = Self.equationTextLengthRawPayload(from: rawPayload)
        equationText = Self.equationText(from: rawPayload)
        equationTextRawPayload = Self.equationTextRawPayload(from: rawPayload)
        rawTrailing = Self.rawTrailing(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .eqEdit)

        var reader = DataReader(record.payload)
        let edit = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return edit
    }

    private static func equationTextLength(from payload: Data) -> UInt16? {
        let offset = 4
        guard payload.count >= offset + MemoryLayout<UInt16>.size else {
            return nil
        }
        do {
            return try payload.readLittleEndianUInt16(at: offset)
        } catch {
            return nil
        }
    }

    private static func equationTextLengthRawPayload(from payload: Data) -> Data? {
        let offset = 4
        let byteCount = MemoryLayout<UInt16>.size
        guard payload.count >= offset + byteCount else {
            return nil
        }
        return Data(payload.dropFirst(offset).prefix(byteCount))
    }

    private static func equationText(from payload: Data) -> String? {
        guard let length = equationTextLength(from: payload),
              let textPayload = equationTextRawPayload(from: payload)
        else {
            return nil
        }

        let characters: [WCHAR]
        do {
            characters = try (0 ..< Int(length)).map { index in
                try textPayload.readLittleEndianUInt16(
                    at: index * MemoryLayout<WCHAR>.size
                )
            }
        } catch {
            return nil
        }
        return characters.stringIfValid
    }

    private static func equationTextRawPayload(from payload: Data) -> Data? {
        guard let textByteCount = equationTextByteCount(from: payload) else {
            return nil
        }
        return Data(payload.dropFirst(equationTextOffset).prefix(textByteCount))
    }

    private static func rawTrailing(from payload: Data) -> Data? {
        guard let textByteCount = equationTextByteCount(from: payload) else {
            return nil
        }
        return Data(payload.dropFirst(equationTextOffset + textByteCount))
    }

    private static var equationTextOffset: Int {
        6
    }

    private static func equationTextByteCount(from payload: Data) -> Int? {
        guard let length = equationTextLength(from: payload) else {
            return nil
        }
        let byteCount = Int(length) * MemoryLayout<WCHAR>.size
        let endOffset = equationTextOffset + byteCount
        guard payload.count >= endOffset else {
            return nil
        }
        return byteCount
    }
}
