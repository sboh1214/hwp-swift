import Foundation

/** 아직 세부 payload를 해석하지 않은 기타 컨트롤 */
public struct HwpOtherControl {
    /** ctrl id */
    public var ctrlId: HwpOtherCtrlId
    /** 자동 번호/새 번호 컨트롤의 번호 정보 */
    public var numberingInfo: HwpOtherControlNumberingInfo?
    /** 쪽 감추기 컨트롤의 알려진 bit field */
    public var pageHideInfo: HwpOtherControlPageHideInfo?
    /** 찾아보기 표식 컨트롤의 알려진 문자열 정보 */
    public var indexmarkInfo: HwpOtherControlIndexmarkInfo?
    /** 책갈피 컨트롤의 알려진 정보 */
    public var bookmarkInfo: HwpOtherControlBookmarkInfo?
    /** ctrl id 이후의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
    /** 원본 payload */
    public var rawPayload: Data
    /** 컨트롤 데이터 child record */
    public var ctrlDataRecords: [HwpCtrlData]
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    public init(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data,
        rawPayload: Data,
        ctrlDataRecords: [HwpCtrlData],
        unknownChildren: [HwpUnknownRecord],
        numberingInfo: HwpOtherControlNumberingInfo? = nil,
        pageHideInfo: HwpOtherControlPageHideInfo? = nil,
        indexmarkInfo: HwpOtherControlIndexmarkInfo? = nil,
        bookmarkInfo: HwpOtherControlBookmarkInfo? = nil
    ) {
        self.ctrlId = ctrlId
        self.numberingInfo = numberingInfo
        self.pageHideInfo = pageHideInfo
        self.indexmarkInfo = indexmarkInfo
        self.bookmarkInfo = bookmarkInfo
        self.rawTrailing = rawTrailing
        self.rawPayload = rawPayload
        self.ctrlDataRecords = ctrlDataRecords
        self.unknownChildren = unknownChildren
    }
}

/** 자동 번호/새 번호 컨트롤의 알려진 번호 payload */
public struct HwpOtherControlNumberingInfo: HwpPrimitive {
    /** 번호 종류 */
    public var kind: UInt32
    /** 번호 값 */
    public var number: UInt32
    /** 표시 형식 */
    public var format: UInt32
    /** 알려진 번호 필드 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
}

/** 쪽 감추기 컨트롤의 알려진 payload */
public struct HwpOtherControlPageHideInfo: HwpPrimitive {
    /** 쪽 감추기 bit field 원본 값 */
    public var rawValue: UInt32
    /** bit field 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
}

/** 찾아보기 표식 컨트롤의 알려진 payload */
public struct HwpOtherControlIndexmarkInfo: HwpPrimitive {
    /** 찾아보기 표식 문자열 길이 */
    public var textCharacterCount: Int
    /** 찾아보기 표식 문자열 길이 WORD payload */
    public var textLengthRawPayload: Data
    /** 찾아보기 표식 문자열 */
    public var text: String
    /** 문자열 WCHAR payload */
    public var textRawPayload: Data
    /** 문자열 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
}

/** 책갈피 컨트롤의 알려진 ctrlData payload */
public struct HwpOtherControlBookmarkInfo: HwpPrimitive {
    /** 책갈피 이름 길이 */
    public var nameCharacterCount: Int
    /** 책갈피 이름 길이 WORD payload */
    public var nameLengthRawPayload: Data
    /** 책갈피 이름 */
    public var name: String
    /** 책갈피 이름 WCHAR payload */
    public var nameRawPayload: Data
    /** 책갈피 이름 뒤의 아직 해석하지 않은 ctrlData payload */
    public var rawTrailing: Data
}

extension HwpOtherControl: HwpFromRecord {
    // MARK: loader contract exemption - preserves other-control trailing payload for typed views

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        let rawCtrlId = try reader.read(UInt32.self)
        guard let ctrlId = HwpOtherCtrlId(rawValue: rawCtrlId) else {
            throw HwpError.invalidCtrlId(ctrlId: rawCtrlId)
        }
        self.ctrlId = ctrlId
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        numberingInfo = Self.numberingInfo(ctrlId: ctrlId, rawTrailing: rawTrailing)
        pageHideInfo = Self.pageHideInfo(ctrlId: ctrlId, rawTrailing: rawTrailing)
        indexmarkInfo = Self.indexmarkInfo(ctrlId: ctrlId, rawTrailing: rawTrailing)
        ctrlDataRecords = try children
            .filter { $0.tagId == HwpSectionTag.ctrlData.rawValue }
            .map { try HwpCtrlData.load($0) }
        bookmarkInfo = Self.bookmarkInfo(ctrlId: ctrlId, ctrlDataRecords: ctrlDataRecords)
        unknownChildren = children
            .filter { $0.tagId != HwpSectionTag.ctrlData.rawValue }
            .map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates other control tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var control = try self.init(&reader, record.children)
        control.rawPayload = record.payload
        return control
    }
}

private extension HwpOtherControl {
    static func numberingInfo(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data
    ) -> HwpOtherControlNumberingInfo? {
        guard ctrlId == .autoNumber || ctrlId == .newNumber,
              rawTrailing.count >= MemoryLayout<UInt32>.size * 3
        else {
            return nil
        }

        do {
            let knownByteCount = MemoryLayout<UInt32>.size * 3
            return HwpOtherControlNumberingInfo(
                kind: try rawTrailing.readLittleEndianUInt32(at: 0),
                number: try rawTrailing.readLittleEndianUInt32(at: 4),
                format: try rawTrailing.readLittleEndianUInt32(at: 8),
                rawTrailing: Data(rawTrailing.dropFirst(knownByteCount))
            )
        } catch {
            return nil
        }
    }

    static func bookmarkInfo(
        ctrlId: HwpOtherCtrlId,
        ctrlDataRecords: [HwpCtrlData]
    ) -> HwpOtherControlBookmarkInfo? {
        guard ctrlId == .bookmark else {
            return nil
        }

        return ctrlDataRecords.compactMap { bookmarkInfo(from: $0) }.first
    }

    static func bookmarkInfo(from ctrlData: HwpCtrlData) -> HwpOtherControlBookmarkInfo? {
        if let item = ctrlData.parameterSet?.stringItem {
            return HwpOtherControlBookmarkInfo(
                nameCharacterCount: item.valueCharacterCount,
                nameLengthRawPayload: item.valueLengthRawPayload,
                name: item.value,
                nameRawPayload: item.valueRawPayload,
                rawTrailing: item.rawTrailing
            )
        }

        return bookmarkInfo(from: ctrlData.rawPayload)
    }

    static func indexmarkInfo(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data
    ) -> HwpOtherControlIndexmarkInfo? {
        guard ctrlId == .indexmark,
              rawTrailing.count >= MemoryLayout<UInt16>.size
        else {
            return nil
        }

        do {
            let stringLengthOffset = 0
            let stringOffset = MemoryLayout<UInt16>.size
            let characterCount = Int(
                try rawTrailing.readLittleEndianUInt16(at: stringLengthOffset)
            )
            let byteCount = characterCount * MemoryLayout<WCHAR>.size
            let endOffset = stringOffset + byteCount
            guard rawTrailing.count >= endOffset else {
                return nil
            }

            let characters = try (0 ..< characterCount).map { index in
                try rawTrailing.readLittleEndianUInt16(
                    at: stringOffset + index * MemoryLayout<WCHAR>.size
                )
            }

            return HwpOtherControlIndexmarkInfo(
                textCharacterCount: characterCount,
                textLengthRawPayload: Data(
                    rawTrailing.prefix(MemoryLayout<UInt16>.size)
                ),
                text: try characters.string,
                textRawPayload: Data(rawTrailing.dropFirst(stringOffset).prefix(byteCount)),
                rawTrailing: Data(rawTrailing.dropFirst(endOffset))
            )
        } catch {
            return nil
        }
    }

    static func bookmarkInfo(from payload: Data) -> HwpOtherControlBookmarkInfo? {
        let stringLengthOffset = 10
        let stringOffset = 12
        guard payload.count >= stringOffset else {
            return nil
        }

        do {
            let characterCount = Int(try payload.readLittleEndianUInt16(at: stringLengthOffset))
            let byteCount = characterCount * MemoryLayout<UInt16>.size
            let endOffset = stringOffset + byteCount
            guard payload.count >= endOffset else {
                return nil
            }

            let name = try (0 ..< characterCount).map { index in
                try payload.readLittleEndianUInt16(
                    at: stringOffset + index * MemoryLayout<WCHAR>.size
                )
            }.string
            return HwpOtherControlBookmarkInfo(
                nameCharacterCount: characterCount,
                nameLengthRawPayload: Data(
                    payload
                        .dropFirst(stringLengthOffset)
                        .prefix(MemoryLayout<UInt16>.size)
                ),
                name: name,
                nameRawPayload: Data(payload.dropFirst(stringOffset).prefix(byteCount)),
                rawTrailing: Data(payload.dropFirst(endOffset))
            )
        } catch {
            return nil
        }
    }

    static func pageHideInfo(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data
    ) -> HwpOtherControlPageHideInfo? {
        guard ctrlId == .pageHide,
              rawTrailing.count >= MemoryLayout<UInt32>.size
        else {
            return nil
        }

        do {
            return HwpOtherControlPageHideInfo(
                rawValue: try rawTrailing.readLittleEndianUInt32(at: 0),
                rawTrailing: Data(rawTrailing.dropFirst(MemoryLayout<UInt32>.size))
            )
        } catch {
            return nil
        }
    }
}
