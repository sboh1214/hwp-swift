import Foundation

/** 아직 세부 payload를 해석하지 않은 기타 컨트롤 */
public struct HwpOtherControl {
    /** ctrl id */
    public var ctrlId: HwpOtherCtrlId
    /** 자동 번호/새 번호 컨트롤의 번호 정보 */
    public var numberingInfo: HwpOtherControlNumberingInfo?
    /** 자동 번호 컨트롤 (표 142)의 typed payload */
    public var autoNumberInfo: HwpOtherControlAutoNumberInfo?
    /** 새 번호 지정 컨트롤 (표 144)의 typed payload */
    public var newNumberInfo: HwpOtherControlNewNumberInfo?
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

    /// header의 ctrl id가 알려진 기타 컨트롤이 아니면 nil을 반환한다.
    /// (파싱 경로는 미지의 ctrl id를 `.unknown`으로 보존하므로 임의 강제 변환하지 않는다.)
    public init?(
        header: HwpCtrlHeader,
        rawPayload: Data
    ) {
        guard let ctrlId = HwpOtherCtrlId(rawValue: header.ctrlId) else { return nil }
        self.ctrlId = ctrlId
        numberingInfo = nil
        autoNumberInfo = nil
        newNumberInfo = nil
        pageHideInfo = nil
        indexmarkInfo = nil
        bookmarkInfo = nil
        rawTrailing = Data()
        self.rawPayload = rawPayload
        ctrlDataRecords = []
        unknownChildren = header.unknownChildren
    }

    public init(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data,
        rawPayload: Data,
        ctrlDataRecords: [HwpCtrlData],
        unknownChildren: [HwpUnknownRecord],
        numberingInfo: HwpOtherControlNumberingInfo? = nil,
        pageHideInfo: HwpOtherControlPageHideInfo? = nil,
        indexmarkInfo: HwpOtherControlIndexmarkInfo? = nil,
        bookmarkInfo: HwpOtherControlBookmarkInfo? = nil,
        autoNumberInfo: HwpOtherControlAutoNumberInfo? = nil,
        newNumberInfo: HwpOtherControlNewNumberInfo? = nil
    ) {
        self.ctrlId = ctrlId
        self.numberingInfo = numberingInfo
        self.autoNumberInfo = autoNumberInfo
        self.newNumberInfo = newNumberInfo
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

/**
 자동 번호 컨트롤의 typed payload

 표 142 자동 번호: 속성(표 143), 번호, 사용자 기호, 앞/뒤 장식 문자
 */
public struct HwpOtherControlAutoNumberInfo: HwpPrimitive {
    /** 속성 (표 143) */
    public var property: UInt32
    /** 번호 (저장 시점에 계산된 값) */
    public var number: UInt16
    /** 사용자 기호 */
    public var userSymbol: WCHAR
    /** 앞 장식 문자 (0이면 없음) */
    public var decorationHead: WCHAR
    /** 뒤 장식 문자 (0이면 없음) */
    public var decorationTail: WCHAR
    /** 알려진 필드 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
}

public extension HwpOtherControlAutoNumberInfo {
    /** 번호 종류 (표 143 bit 0-3) */
    var kind: HwpAutoNumberKind {
        HwpAutoNumberKind(rawValue: property & 0xF) ?? .page
    }

    /** 번호 모양 (표 143 bit 4-11, 표 134 참조) */
    var numberShapeRawValue: Int {
        Int((property >> 4) & 0xFF)
    }

    /** 각주 내용 중 번호 코드를 위 첨자 형식으로 할지 (표 143 bit 12) */
    var isSuperscript: Bool {
        property & (1 << 12) != 0
    }
}

/** 자동 번호/새 번호의 번호 종류 (표 143 bit 0-3) */
public enum HwpAutoNumberKind: UInt32, HwpPrimitive {
    /** 쪽 번호 */
    case page = 0
    /** 각주 번호 */
    case footnote = 1
    /** 미주 번호 */
    case endnote = 2
    /** 그림 번호 */
    case picture = 3
    /** 표 번호 */
    case table = 4
    /** 수식 번호 */
    case equation = 5
}

/**
 새 번호 지정 컨트롤의 typed payload

 표 144 새 번호 지정: 속성(bit 0-3 번호 종류, 표 143 참조), 번호
 */
public struct HwpOtherControlNewNumberInfo: HwpPrimitive {
    /** 속성 (bit 0-3 번호 종류) */
    public var property: UInt32
    /** 새로 시작할 번호 */
    public var number: UInt16
    /** 알려진 필드 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data
}

public extension HwpOtherControlNewNumberInfo {
    /** 번호 종류 (표 143 bit 0-3) */
    var kind: HwpAutoNumberKind {
        HwpAutoNumberKind(rawValue: property & 0xF) ?? .page
    }
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
        let trailing = try reader.readToEnd()
        rawTrailing = reader.options.preservedPayload(trailing)
        rawPayload = try reader.consumedData(from: startOffset)
        numberingInfo = Self.numberingInfo(ctrlId: ctrlId, rawTrailing: trailing)
        autoNumberInfo = Self.autoNumberInfo(ctrlId: ctrlId, rawTrailing: trailing)
        newNumberInfo = Self.newNumberInfo(ctrlId: ctrlId, rawTrailing: trailing)
        pageHideInfo = Self.pageHideInfo(ctrlId: ctrlId, rawTrailing: trailing)
        indexmarkInfo = Self.indexmarkInfo(ctrlId: ctrlId, rawTrailing: trailing)
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

        var reader = DataReader(record.payload, options: record.options)
        var control = try self.init(&reader, record.children)
        control.rawPayload = record.options.preservedPayload(record.payload)
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

    static func autoNumberInfo(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data
    ) -> HwpOtherControlAutoNumberInfo? {
        // 표 142: 속성 u32 + 번호 u16 + 사용자 기호/앞/뒤 장식 WCHAR = 12 byte
        // (헌법주석 실측: 01 00 00 00 | nn 00 | 00 00 | 00 00 | 29 00)
        let knownByteCount = 12
        guard ctrlId == .autoNumber, rawTrailing.count >= knownByteCount else {
            return nil
        }

        do {
            return HwpOtherControlAutoNumberInfo(
                property: try rawTrailing.readLittleEndianUInt32(at: 0),
                number: try rawTrailing.readLittleEndianUInt16(at: 4),
                userSymbol: try rawTrailing.readLittleEndianUInt16(at: 6),
                decorationHead: try rawTrailing.readLittleEndianUInt16(at: 8),
                decorationTail: try rawTrailing.readLittleEndianUInt16(at: 10),
                rawTrailing: Data(rawTrailing.dropFirst(knownByteCount))
            )
        } catch {
            return nil
        }
    }

    static func newNumberInfo(
        ctrlId: HwpOtherCtrlId,
        rawTrailing: Data
    ) -> HwpOtherControlNewNumberInfo? {
        // 표 144: 속성 u32 + 번호 u16 = 6 byte (헌법주석 실측: 01 00 00 00 01 00)
        let knownByteCount = 6
        guard ctrlId == .newNumber, rawTrailing.count >= knownByteCount else {
            return nil
        }

        do {
            return HwpOtherControlNewNumberInfo(
                property: try rawTrailing.readLittleEndianUInt32(at: 0),
                number: try rawTrailing.readLittleEndianUInt16(at: 4),
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
