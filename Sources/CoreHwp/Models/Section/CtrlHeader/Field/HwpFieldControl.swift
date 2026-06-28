import Foundation

/** 아직 세부 payload를 해석하지 않은 필드 컨트롤 */
public struct HwpFieldControl {
    /** ctrl id */
    public var ctrlId: HwpFieldCtrlId
    /** ctrl id 이후의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
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
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        let rawCtrlId = try reader.read(UInt32.self)
        guard let ctrlId = HwpFieldCtrlId(rawValue: rawCtrlId) else {
            throw HwpError.invalidCtrlId(ctrlId: rawCtrlId)
        }
        self.ctrlId = ctrlId
        rawTrailing = try reader.readToEnd()
        fieldParameterHeaderValue = Self.fieldParameterHeaderValue(from: rawTrailing)
        fieldParameterHeaderRawPayload = Self.fieldParameterHeaderRawPayload(from: rawTrailing)
        let lengthInfo = Self.fieldParameterLengthInfo(from: rawTrailing)
        fieldParameterCharacterCount = lengthInfo?.characterCount
        fieldParameterLengthRawPayload = lengthInfo?.rawPayload
        let parsedParameter = Self.fieldParameter(from: rawTrailing)
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
        guard data.count >= textOffset else {
            return nil
        }

        let length: WORD
        do {
            length = try data.readLittleEndianUInt16(at: lengthOffset)
        } catch {
            return nil
        }
        guard let parsedLength = parsedLength(
            length,
            remainingBytes: data.count - textOffset
        )
        else {
            return nil
        }
        let chars: [WCHAR]
        do {
            chars = try (0 ..< parsedLength.characterCount).map { index in
                try data.readLittleEndianUInt16(
                    at: textOffset + index * MemoryLayout<WCHAR>.size
                )
            }
        } catch {
            return nil
        }
        let parameterChars = parsedLength.isByteSwapped
            ? chars.map(\.byteSwapped)
            : chars
        guard let value = parameterChars.stringIfValid else {
            return nil
        }
        let consumedBytes = textOffset + parsedLength.characterCount * MemoryLayout<WCHAR>.size
        let byteCount = parsedLength.characterCount * MemoryLayout<WCHAR>.size
        return HwpFieldParameterParseResult(
            value: value,
            rawPayload: Data(data.dropFirst(textOffset).prefix(byteCount)),
            rawTrailing: Data(data.dropFirst(consumedBytes))
        )
    }

    private static func parsedLength(
        _ length: WORD,
        remainingBytes: Int
    ) -> (characterCount: Int, isByteSwapped: Bool)? {
        let maxCharacterCount = remainingBytes / MemoryLayout<WCHAR>.size
        if let count = Int(exactly: length), count <= maxCharacterCount {
            return (count, false)
        }
        let swappedLength = length.byteSwapped
        if let count = Int(exactly: swappedLength), count <= maxCharacterCount {
            return (count, true)
        }
        return nil
    }

    private static func fieldParameterLengthInfo(from data: Data)
        -> HwpFieldParameterLengthInfo?
    {
        let lengthOffset = MemoryLayout<UInt32>.size
        let textOffset = lengthOffset + MemoryLayout<WORD>.size
        guard data.count >= textOffset else {
            return nil
        }

        do {
            let length = try data.readLittleEndianUInt16(at: lengthOffset)
            let rawPayload = Data(
                data.dropFirst(lengthOffset).prefix(MemoryLayout<WORD>.size)
            )
            guard let parsed = parsedLength(
                length,
                remainingBytes: data.count - textOffset
            ) else {
                return HwpFieldParameterLengthInfo(
                    characterCount: nil,
                    rawPayload: rawPayload
                )
            }
            return HwpFieldParameterLengthInfo(
                characterCount: parsed.characterCount,
                rawPayload: rawPayload
            )
        } catch {
            return nil
        }
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

private struct HwpFieldParameterParseResult {
    let value: String
    let rawPayload: Data
    let rawTrailing: Data
}

private struct HwpFieldParameterLengthInfo {
    let characterCount: Int?
    let rawPayload: Data
}

private extension HwpMemoFieldParameter {
    init?(_ rawValue: String, rawPayload: Data, rawTrailing: Data) {
        let components = rawValue
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let marker = components.first, marker == "MEMO" else {
            return nil
        }
        self.rawValue = rawValue
        self.rawPayload = rawPayload
        self.components = components
        self.marker = marker
        fields = Array(components.dropFirst())
        author = components.indices.contains(5) ? components[5] : nil
        self.rawTrailing = rawTrailing
    }
}
