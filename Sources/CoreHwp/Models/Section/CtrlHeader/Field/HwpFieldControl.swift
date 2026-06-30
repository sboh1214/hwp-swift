import Foundation

/** 아직 세부 payload를 해석하지 않은 필드 컨트롤 */
public struct HwpFieldControl {
    /** ctrl id */
    public var ctrlId: HwpFieldCtrlId
    /** ctrl id 이후의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
    /** 필드 속성 */
    public var properties: UInt32?
    /** 필드 속성 원문 payload */
    @ExcludeEquatable
    public var propertiesRawPayload: Data?
    /** 필드 속성을 bit field로 해석한 값 */
    public var propertyInfo: HwpFieldControlProperty?
    /** 기타 속성 */
    public var extraProperties: UInt8?
    /** 기타 속성 원문 payload */
    @ExcludeEquatable
    public var extraPropertiesRawPayload: Data?
    /** command 문자열의 글자 수 */
    public var commandCharacterCount: Int?
    /** command length WORD 원문 payload */
    @ExcludeEquatable
    public var commandLengthRawPayload: Data?
    /** 필드 command 문자열 */
    public var command: String?
    /** command 문자열 원문 WCHAR payload */
    @ExcludeEquatable
    public var commandRawPayload: Data?
    /** command 문자열 이후의 field id, memo index, 기타 payload */
    public var commandRawTrailing: Data?
    /** 필드 ID */
    public var fieldId: UInt32?
    /** 필드 ID 원문 payload */
    @ExcludeEquatable
    public var fieldIdRawPayload: Data?
    /** 메모 모양 참조 인덱스 */
    public var memoIndex: Int32?
    /** 메모 모양 참조 인덱스 원문 payload */
    @ExcludeEquatable
    public var memoIndexRawPayload: Data?
    /** field parameter 길이 앞의 알려진 32-bit header 값 */
    public var fieldParameterHeaderValue: UInt32?
    /** field parameter 길이 앞의 알려진 32-bit header 원문 payload */
    @ExcludeEquatable
    public var fieldParameterHeaderRawPayload: Data?
    /** field parameter 문자열의 해석된 글자 수 */
    public var fieldParameterCharacterCount: Int?
    /** field parameter length WORD 원문 payload */
    @ExcludeEquatable
    public var fieldParameterLengthRawPayload: Data?
    /** 필드 payload 안의 UTF-16LE parameter 문자열 */
    public var fieldParameter: String?
    /** field parameter 원문 WCHAR payload */
    @ExcludeEquatable
    public var fieldParameterRawPayload: Data?
    /** parameter 문자열 이후의 아직 해석하지 않은 payload */
    public var fieldParameterRawTrailing: Data?
    /** MEMO field parameter를 구조화한 값 */
    public var memoParameter: HwpMemoFieldParameter?
    /** 원본 payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    public var isMemoField: Bool {
        ctrlId == .memo || memoParameter != nil
    }

    public var isRevisionField: Bool {
        ctrlId.isRevision
    }

    /** payload와 parameter를 바탕으로 분류한 필드 컨트롤 종류 */
    public var semanticKind: HwpFieldControlKind {
        if isMemoField {
            return .memo
        }
        if isRevisionField {
            return .revision
        }
        return .field
    }
}

public enum HwpFieldControlKind: String, HwpPrimitive {
    case field
    case memo
    case revision
}

public struct HwpMemoFieldParameter: HwpPrimitive {
    /** 원본 parameter 문자열 */
    public let rawValue: String
    /** 원본 parameter 문자열 WCHAR payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /** "/"로 분리한 전체 component. 첫 값은 marker이다. */
    public let components: [String]
    /** MEMO marker */
    public let marker: String
    /** marker 뒤의 아직 세부 해석하지 않은 field 값 */
    public let fields: [String]
    /** 한컴오피스가 저장한 작성자 문자열로 보이는 component */
    public let author: String?
    /** parameter 문자열 이후의 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

extension HwpFieldControl: HwpPrimitive {
    // MARK: loader contract exemption - preserves field rawTrailing for best-effort parameters

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        let rawCtrlId = try reader.read(UInt32.self)
        guard let ctrlId = HwpFieldCtrlId(rawValue: rawCtrlId) else {
            throw HwpError.invalidCtrlId(ctrlId: rawCtrlId)
        }
        self.ctrlId = ctrlId
        rawTrailing = try reader.readToEnd()
        let parsedControl = Self.fieldControlPayload(from: rawTrailing)
        let fallbackLengthInfo = Self.fieldParameterLengthInfo(from: rawTrailing)
        let fallbackParameter = Self.fieldParameter(from: rawTrailing)
        let parsedProperties = parsedControl?.properties
            ?? Self.fieldParameterHeaderValue(from: rawTrailing)
        let parsedPropertiesRawPayload = parsedControl?.propertiesRawPayload
            ?? Self.fieldParameterHeaderRawPayload(from: rawTrailing)
        let parsedCommandLengthRawPayload = parsedControl?.commandLengthRawPayload

        properties = parsedProperties
        propertiesRawPayload = parsedPropertiesRawPayload
        propertyInfo = try parsedProperties.map(HwpFieldControlProperty.load)
        extraProperties = parsedControl?.extraProperties
        extraPropertiesRawPayload = parsedControl?.extraPropertiesRawPayload
        commandCharacterCount = parsedControl?.command.characterCount
        commandLengthRawPayload = parsedCommandLengthRawPayload
        command = parsedControl?.command.value
        commandRawPayload = parsedControl?.command.rawPayload
        commandRawTrailing = parsedControl?.command.rawTrailing
        fieldId = parsedControl?.fieldId
        fieldIdRawPayload = parsedControl?.fieldIdRawPayload
        memoIndex = parsedControl?.memoIndex
        memoIndexRawPayload = parsedControl?.memoIndexRawPayload

        fieldParameterHeaderValue = parsedProperties
        fieldParameterHeaderRawPayload = parsedPropertiesRawPayload
        fieldParameterCharacterCount = parsedControl?.command.characterCount
            ?? fallbackLengthInfo?.characterCount
        fieldParameterLengthRawPayload = parsedCommandLengthRawPayload
            ?? fallbackLengthInfo?.rawPayload
        let parsedParameter = parsedControl?.command ?? fallbackParameter
        fieldParameter = parsedParameter?.value
        fieldParameterRawPayload = parsedParameter?.rawPayload
        fieldParameterRawTrailing = parsedParameter?.rawTrailing
        memoParameter = parsedParameter.flatMap {
            HwpMemoFieldParameter(
                $0.value,
                rawPayload: $0.rawPayload,
                rawTrailing: $0.rawTrailing
            )
        }
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates field control tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var control = try self.init(&reader, record.children)
        control.rawPayload = record.payload
        return control
    }

    private static func fieldParameter(from data: Data) -> HwpFieldParameterParseResult? {
        let lengthOffset = MemoryLayout<UInt32>.size
        let textOffset = lengthOffset + MemoryLayout<WORD>.size
        return fieldParameter(from: data, lengthOffset: lengthOffset, textOffset: textOffset)
    }

    private static func fieldParameter(
        from data: Data,
        lengthOffset: Int,
        textOffset: Int
    ) -> HwpFieldParameterParseResult? {
        guard data.count >= textOffset else {
            return nil
        }

        let length: WORD
        do {
            length = try data.readLittleEndianUInt16(at: lengthOffset)
        } catch {
            return nil
        }
        let candidates = parsedLengthCandidates(length, remainingBytes: data.count - textOffset)
        let parsedCandidates = candidates.compactMap {
            fieldParameter(from: data, textOffset: textOffset, length: $0)
        }
        guard let parsedParameter = selectedFieldParameter(from: parsedCandidates) else {
            return nil
        }
        return parsedParameter
    }

    private static func fieldParameter(
        from data: Data,
        textOffset: Int,
        length: HwpFieldParameterLengthCandidate
    ) -> HwpFieldParameterParseResult? {
        let chars: [WCHAR]
        do {
            chars = try (0 ..< length.characterCount).map { index in
                try data.readLittleEndianUInt16(
                    at: textOffset + index * MemoryLayout<WCHAR>.size
                )
            }
        } catch {
            return nil
        }
        let parameterChars = length.isByteSwapped ? chars.map(\.byteSwapped) : chars
        guard let value = parameterChars.stringIfValid else {
            return nil
        }
        guard isSupportedFieldParameterText(value) else {
            return nil
        }
        let byteCount = length.characterCount * MemoryLayout<WCHAR>.size
        let consumedBytes = textOffset + byteCount
        return HwpFieldParameterParseResult(
            value: value,
            characterCount: length.characterCount,
            isByteSwapped: length.isByteSwapped,
            rawPayload: Data(data.dropFirst(textOffset).prefix(byteCount)),
            rawTrailing: Data(data.dropFirst(consumedBytes))
        )
    }

    private static func parsedLengthCandidates(
        _ length: WORD,
        remainingBytes: Int
    ) -> [HwpFieldParameterLengthCandidate] {
        let maxCharacterCount = remainingBytes / MemoryLayout<WCHAR>.size
        var candidates = [HwpFieldParameterLengthCandidate]()
        if let count = Int(exactly: length), count <= maxCharacterCount {
            candidates.append(HwpFieldParameterLengthCandidate(
                characterCount: count,
                isByteSwapped: false
            ))
        }
        let swappedLength = length.byteSwapped
        if swappedLength != length,
           let count = Int(exactly: swappedLength),
           count <= maxCharacterCount
        {
            candidates.append(HwpFieldParameterLengthCandidate(
                characterCount: count,
                isByteSwapped: true
            ))
        }
        return candidates
    }

    private static func selectedFieldParameter(
        from candidates: [HwpFieldParameterParseResult]
    ) -> HwpFieldParameterParseResult? {
        guard let natural = candidates.first(where: { !$0.isByteSwapped }) else {
            return candidates.first
        }

        if let swapped = candidates.first(where: \.isByteSwapped),
           isStrongFieldParameterText(swapped.value),
           !isStrongFieldParameterText(natural.value)
        {
            return swapped
        }
        return natural
    }

    private static func isSupportedFieldParameterText(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func isStrongFieldParameterText(_ value: String) -> Bool {
        value.hasPrefix("MEMO/")
    }

    private static func fieldParameterLengthInfo(from data: Data)
        -> HwpFieldParameterLengthInfo?
    {
        let lengthOffset = MemoryLayout<UInt32>.size
        let textOffset = lengthOffset + MemoryLayout<WORD>.size
        return fieldParameterLengthInfo(
            from: data,
            lengthOffset: lengthOffset,
            textOffset: textOffset
        )
    }

    private static func fieldParameterLengthInfo(
        from data: Data,
        lengthOffset: Int,
        textOffset: Int
    ) -> HwpFieldParameterLengthInfo? {
        guard data.count >= textOffset else {
            return nil
        }

        do {
            let length = try data.readLittleEndianUInt16(at: lengthOffset)
            let rawPayload = Data(
                data.dropFirst(lengthOffset).prefix(MemoryLayout<WORD>.size)
            )
            let candidates = parsedLengthCandidates(
                length,
                remainingBytes: data.count - textOffset
            )
            guard let characterCount = fieldParameter(from: data)?.characterCount
                ?? candidates.first?.characterCount
            else {
                return HwpFieldParameterLengthInfo(
                    characterCount: nil,
                    rawPayload: rawPayload
                )
            }
            return HwpFieldParameterLengthInfo(
                characterCount: characterCount,
                rawPayload: rawPayload
            )
        } catch {
            return nil
        }
    }

    private static func fieldControlPayload(
        from data: Data
    ) -> HwpFieldControlPayloadParseResult? {
        guard let parsedCommand = fieldControlCommand(from: data) else {
            return nil
        }

        return fieldControlPayload(
            from: data,
            command: parsedCommand.command,
            offsets: parsedCommand.offsets
        )
    }

    private static func fieldControlCommand(
        from data: Data
    ) -> (command: HwpFieldParameterParseResult, offsets: HwpFieldControlPayloadOffsets)? {
        let propertiesOffset = 0
        let extraPropertiesOffset = propertiesOffset + MemoryLayout<UInt32>.size
        let lengthOffset = extraPropertiesOffset + MemoryLayout<UInt8>.size
        let textOffset = lengthOffset + MemoryLayout<WORD>.size
        guard data.count >= textOffset else {
            return nil
        }
        guard let command = fieldParameter(
            from: data,
            lengthOffset: lengthOffset,
            textOffset: textOffset
        ) else {
            return nil
        }

        let fieldIdOffset = textOffset + command.rawPayload.count
        let memoIndexOffset = fieldIdOffset + MemoryLayout<UInt32>.size
        let endOffset = memoIndexOffset + MemoryLayout<Int32>.size
        guard data.count == endOffset else {
            return nil
        }
        let offsets = HwpFieldControlPayloadOffsets(
            properties: propertiesOffset,
            extraProperties: extraPropertiesOffset,
            commandLength: lengthOffset,
            fieldId: fieldIdOffset,
            memoIndex: memoIndexOffset
        )
        return (command, offsets)
    }

    private static func fieldControlPayload(
        from data: Data,
        command: HwpFieldParameterParseResult,
        offsets: HwpFieldControlPayloadOffsets
    ) -> HwpFieldControlPayloadParseResult? {
        do {
            let properties = try data.readLittleEndianUInt32(at: offsets.properties)
            let extraProperties = try data.readUInt8(at: offsets.extraProperties)
            let fieldId = try data.readLittleEndianUInt32(at: offsets.fieldId)
            let memoIndexRawValue = try data.readLittleEndianUInt32(at: offsets.memoIndex)
            return HwpFieldControlPayloadParseResult(
                properties: properties,
                propertiesRawPayload: rawFieldPayload(
                    from: data,
                    offset: offsets.properties,
                    byteCount: MemoryLayout<UInt32>.size
                ),
                extraProperties: extraProperties,
                extraPropertiesRawPayload: rawFieldPayload(
                    from: data,
                    offset: offsets.extraProperties,
                    byteCount: MemoryLayout<UInt8>.size
                ),
                commandLengthRawPayload: rawFieldPayload(
                    from: data,
                    offset: offsets.commandLength,
                    byteCount: MemoryLayout<WORD>.size
                ),
                command: HwpFieldParameterParseResult(
                    value: command.value,
                    characterCount: command.characterCount,
                    isByteSwapped: command.isByteSwapped,
                    rawPayload: command.rawPayload,
                    rawTrailing: Data(data.dropFirst(offsets.fieldId))
                ),
                fieldId: fieldId,
                fieldIdRawPayload: rawFieldPayload(
                    from: data,
                    offset: offsets.fieldId,
                    byteCount: MemoryLayout<UInt32>.size
                ),
                memoIndex: Int32(bitPattern: memoIndexRawValue),
                memoIndexRawPayload: rawFieldPayload(
                    from: data,
                    offset: offsets.memoIndex,
                    byteCount: MemoryLayout<Int32>.size
                )
            )
        } catch {
            return nil
        }
    }

    private static func rawFieldPayload(
        from data: Data,
        offset: Int,
        byteCount: Int
    ) -> Data {
        Data(data.dropFirst(offset).prefix(byteCount))
    }

    private static func fieldParameterHeaderValue(from data: Data) -> UInt32? {
        guard data.count >= MemoryLayout<UInt32>.size else {
            return nil
        }

        do {
            return try data.readLittleEndianUInt32(at: 0)
        } catch {
            return nil
        }
    }

    private static func fieldParameterHeaderRawPayload(from data: Data) -> Data? {
        let byteCount = MemoryLayout<UInt32>.size
        guard data.count >= byteCount else {
            return nil
        }

        return Data(data.prefix(byteCount))
    }
}
