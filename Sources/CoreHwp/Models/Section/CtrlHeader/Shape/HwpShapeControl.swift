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

    // MARK: loader contract exemption - shape control preserves raw payload for fallback parsing

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

    // MARK: loader contract exemption - validates shape control tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        let shapeControl = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return shapeControl
    }

    // MARK: loader contract exemption - validates shape control tag before versioned decode

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
    /** 속성(스크립트 범위) */
    public var property: UInt32?
    /** 속성 원문 DWORD payload */
    public var propertyRawPayload: Data?
    /** 수식 문자열 길이. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var equationTextLength: UInt16?
    /** 수식 문자열 길이 원문 WORD payload */
    public var equationTextLengthRawPayload: Data?
    /** 수식 문자열. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var equationText: String?
    /** 수식 문자열 원문 WCHAR payload */
    public var equationTextRawPayload: Data?
    /** 수식 글자 크기 */
    public var letterSize: HWPUNIT?
    /** 수식 글자 크기 원문 HWPUNIT payload */
    public var letterSizeRawPayload: Data?
    /** 글자 색상 */
    public var textColor: HwpColor?
    /** 글자 색상 원문 COLORREF 값 */
    public var textColorRawValue: COLORREF?
    /** 글자 색상 원문 COLORREF payload */
    public var textColorRawPayload: Data?
    /** base line */
    public var baseline: Int16?
    /** base line 원문 INT16 payload */
    public var baselineRawPayload: Data?
    /** baseline과 version info 사이의 미문서화 UINT16 값 */
    public var unknownAfterBaseline: UInt16?
    /** baseline과 version info 사이의 미문서화 UINT16 원문 payload */
    public var unknownAfterBaselineRawPayload: Data?
    /** 수식 버전 정보 문자열 길이 */
    public var versionInfoLength: UInt16?
    /** 수식 버전 정보 문자열 길이 원문 WORD payload */
    public var versionInfoLengthRawPayload: Data?
    /** 수식 버전 정보 */
    public var versionInfo: String?
    /** 수식 버전 정보 원문 WCHAR payload */
    public var versionInfoRawPayload: Data?
    /** 수식 폰트 이름 문자열 길이 */
    public var fontNameLength: UInt16?
    /** 수식 폰트 이름 문자열 길이 원문 WORD payload */
    public var fontNameLengthRawPayload: Data?
    /** 수식 폰트 이름 */
    public var fontName: String?
    /** 수식 폰트 이름 원문 WCHAR payload */
    public var fontNameRawPayload: Data?
    /** 수식 편집 정보 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpEquationEdit: HwpFromRecord {
    // MARK: loader contract exemption - equation edit payload is best-effort raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        let payloadInfo = Self.payloadInfo(from: rawPayload)
        property = payloadInfo.property
        propertyRawPayload = payloadInfo.propertyRawPayload
        equationTextLength = payloadInfo.equationTextLength
        equationTextLengthRawPayload = payloadInfo.equationTextLengthRawPayload
        equationText = payloadInfo.equationText
        equationTextRawPayload = payloadInfo.equationTextRawPayload
        letterSize = payloadInfo.letterSize
        letterSizeRawPayload = payloadInfo.letterSizeRawPayload
        textColor = payloadInfo.textColor
        textColorRawValue = payloadInfo.textColorRawValue
        textColorRawPayload = payloadInfo.textColorRawPayload
        baseline = payloadInfo.baseline
        baselineRawPayload = payloadInfo.baselineRawPayload
        unknownAfterBaseline = payloadInfo.unknownAfterBaseline
        unknownAfterBaselineRawPayload = payloadInfo.unknownAfterBaselineRawPayload
        versionInfoLength = payloadInfo.versionInfoLength
        versionInfoLengthRawPayload = payloadInfo.versionInfoLengthRawPayload
        versionInfo = payloadInfo.versionInfo
        versionInfoRawPayload = payloadInfo.versionInfoRawPayload
        fontNameLength = payloadInfo.fontNameLength
        fontNameLengthRawPayload = payloadInfo.fontNameLengthRawPayload
        fontName = payloadInfo.fontName
        fontNameRawPayload = payloadInfo.fontNameRawPayload
        rawTrailing = payloadInfo.rawTrailing
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates equation edit tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .eqEdit)

        var reader = DataReader(record.payload)
        let edit = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return edit
    }

    private static func payloadInfo(from payload: Data) -> HwpEquationEditPayloadInfo {
        var info = HwpEquationEditPayloadInfo()
        guard parseProperty(from: payload, into: &info),
              let layoutOffset = parseEquationText(from: payload, into: &info)
        else {
            return info
        }
        info.rawTrailing = Data(payload.dropFirst(layoutOffset))

        guard let stringOffset = parseLayoutFields(
            from: payload,
            offset: layoutOffset,
            into: &info
        ) else {
            return info
        }
        parseVersionAndFont(from: payload, offset: stringOffset, into: &info)
        return info
    }

    private static func parseProperty(
        from payload: Data,
        into info: inout HwpEquationEditPayloadInfo
    ) -> Bool {
        guard let property = uint32(from: payload, at: propertyOffset) else {
            return false
        }
        info.property = property
        info.propertyRawPayload = rawPayload(from: payload, at: propertyOffset, byteCount: 4)
        return true
    }

    private static func parseEquationText(
        from payload: Data,
        into info: inout HwpEquationEditPayloadInfo
    ) -> Int? {
        guard let equationTextLength = uint16(from: payload, at: equationTextLengthOffset) else {
            return nil
        }
        info.equationTextLength = equationTextLength
        info.equationTextLengthRawPayload = rawPayload(
            from: payload,
            at: equationTextLengthOffset,
            byteCount: 2
        )

        let equationTextByteCount = Int(equationTextLength) * MemoryLayout<WCHAR>.size
        guard let equationTextRawPayload = rawPayload(
            from: payload,
            at: equationTextOffset,
            byteCount: equationTextByteCount
        ) else {
            return nil
        }
        info.equationTextRawPayload = equationTextRawPayload
        info.equationText = wcharString(from: equationTextRawPayload)
        return equationTextOffset + equationTextByteCount
    }

    private static func parseLayoutFields(
        from payload: Data,
        offset: Int,
        into info: inout HwpEquationEditPayloadInfo
    ) -> Int? {
        var offset = offset
        guard let letterSize = uint32(from: payload, at: offset) else {
            return nil
        }
        info.letterSize = letterSize
        info.letterSizeRawPayload = rawPayload(from: payload, at: offset, byteCount: 4)
        offset += 4

        guard let textColorRawValue = uint32(from: payload, at: offset) else {
            return nil
        }
        info.textColorRawValue = textColorRawValue
        info.textColor = HwpColor(textColorRawValue)
        info.textColorRawPayload = rawPayload(from: payload, at: offset, byteCount: 4)
        offset += 4

        guard let baselineRawValue = uint16(from: payload, at: offset) else {
            return nil
        }
        info.baseline = Int16(bitPattern: baselineRawValue)
        info.baselineRawPayload = rawPayload(from: payload, at: offset, byteCount: 2)
        offset += 2

        guard let unknownAfterBaseline = uint16(from: payload, at: offset) else {
            return nil
        }
        info.unknownAfterBaseline = unknownAfterBaseline
        info.unknownAfterBaselineRawPayload = rawPayload(from: payload, at: offset, byteCount: 2)
        return offset + 2
    }

    private static func parseVersionAndFont(
        from payload: Data,
        offset: Int,
        into info: inout HwpEquationEditPayloadInfo
    ) {
        guard let versionInfo = hwpString(from: payload, at: offset) else {
            return
        }
        info.versionInfoLength = versionInfo.length
        info.versionInfoLengthRawPayload = versionInfo.lengthRawPayload
        info.versionInfo = versionInfo.value
        info.versionInfoRawPayload = versionInfo.rawPayload

        guard let fontName = hwpString(from: payload, at: versionInfo.endOffset) else {
            return
        }
        info.fontNameLength = fontName.length
        info.fontNameLengthRawPayload = fontName.lengthRawPayload
        info.fontName = fontName.value
        info.fontNameRawPayload = fontName.rawPayload

        info.rawTrailing = Data(payload.dropFirst(fontName.endOffset))
    }

    private static var propertyOffset: Int {
        0
    }

    private static var equationTextLengthOffset: Int {
        4
    }

    private static var equationTextOffset: Int {
        6
    }

    private static func hwpString(from payload: Data, at offset: Int) -> HwpStringInfo? {
        guard let length = uint16(from: payload, at: offset),
              let lengthRawPayload = rawPayload(from: payload, at: offset, byteCount: 2)
        else {
            return nil
        }
        let textOffset = offset + 2
        let byteCount = Int(length) * MemoryLayout<WCHAR>.size
        guard let rawPayload = rawPayload(
            from: payload,
            at: textOffset,
            byteCount: byteCount
        ) else {
            return nil
        }
        return HwpStringInfo(
            length: length,
            lengthRawPayload: lengthRawPayload,
            value: wcharString(from: rawPayload),
            rawPayload: rawPayload,
            endOffset: textOffset + byteCount
        )
    }

    private static func wcharString(from payload: Data) -> String? {
        guard payload.count.isMultiple(of: MemoryLayout<WCHAR>.size) else {
            return nil
        }
        let characters: [WCHAR]
        do {
            characters = try stride(from: 0, to: payload.count, by: MemoryLayout<WCHAR>.size)
                .map { try payload.readLittleEndianUInt16(at: $0) }
        } catch {
            return nil
        }
        return characters.stringIfValid
    }

    private static func uint16(from payload: Data, at offset: Int) -> UInt16? {
        do {
            return try payload.readLittleEndianUInt16(at: offset)
        } catch {
            return nil
        }
    }

    private static func uint32(from payload: Data, at offset: Int) -> UInt32? {
        do {
            return try payload.readLittleEndianUInt32(at: offset)
        } catch {
            return nil
        }
    }

    private static func rawPayload(from payload: Data, at offset: Int, byteCount: Int) -> Data? {
        guard offset >= 0, byteCount >= 0 else {
            return nil
        }
        let endOffset = offset.addingReportingOverflow(byteCount)
        guard !endOffset.overflow,
              offset <= payload.count,
              endOffset.partialValue <= payload.count
        else {
            return nil
        }
        return Data(payload.dropFirst(offset).prefix(byteCount))
    }
}

private struct HwpEquationEditPayloadInfo {
    var property: UInt32?
    var propertyRawPayload: Data?
    var equationTextLength: UInt16?
    var equationTextLengthRawPayload: Data?
    var equationText: String?
    var equationTextRawPayload: Data?
    var letterSize: HWPUNIT?
    var letterSizeRawPayload: Data?
    var textColor: HwpColor?
    var textColorRawValue: COLORREF?
    var textColorRawPayload: Data?
    var baseline: Int16?
    var baselineRawPayload: Data?
    var unknownAfterBaseline: UInt16?
    var unknownAfterBaselineRawPayload: Data?
    var versionInfoLength: UInt16?
    var versionInfoLengthRawPayload: Data?
    var versionInfo: String?
    var versionInfoRawPayload: Data?
    var fontNameLength: UInt16?
    var fontNameLengthRawPayload: Data?
    var fontName: String?
    var fontNameRawPayload: Data?
    var rawTrailing: Data?
}

private struct HwpStringInfo {
    let length: UInt16
    let lengthRawPayload: Data
    let value: String?
    let rawPayload: Data
    let endOffset: Int
}
