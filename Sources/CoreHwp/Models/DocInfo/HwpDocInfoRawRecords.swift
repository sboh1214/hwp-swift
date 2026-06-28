import Foundation

/**
 문서 데이터

 Tag ID : HWPTAG_DOC_DATA
 */
public struct HwpDocData: HwpFromRecord {
    public let rawPayload: Data
    public let docDataInfo: HwpDocDataInfo?
    public let forbiddenCharArray: [HwpForbiddenChar]
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .docData, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        docDataInfo = Self.docDataInfo(from: rawPayload)
        forbiddenCharArray = try children
            .filter { $0.tagId == HwpDocInfoTag.forbiddenChar.rawValue }
            .map(HwpForbiddenChar.load)
        unknownChildren = children
            .filter { $0.tagId != HwpDocInfoTag.forbiddenChar.rawValue }
            .map(HwpUnknownRecord.init)
    }
}

/** 문서 데이터의 알려진 32-bit word payload */
public struct HwpDocDataInfo: HwpPrimitive {
    /** 해석 전 단계로 노출하는 little-endian 32-bit word 값 */
    public let values: [UInt32]
    /** 32-bit word 값들의 원문 payload */
    public let valuesRawPayload: Data
    /** 32-bit word로 나누어 떨어지지 않는 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

/**
 배포용 문서 데이터

 Tag ID : HWPTAG_DISTRIBUTE_DOC_DATA
 */
public struct HwpDistributeDocData: HwpFromRecord {
    public let rawPayload: Data
    public let distributeDocDataInfo: HwpDistributeDocDataInfo?
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .distributeDocData, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        distributeDocDataInfo = Self.distributeDocDataInfo(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** 배포용 문서 데이터의 알려진 32-bit word payload */
public struct HwpDistributeDocDataInfo: HwpPrimitive {
    /** 해석 전 단계로 노출하는 little-endian 32-bit word 값 */
    public let values: [UInt32]
    /** 32-bit word 값들의 원문 payload */
    public let valuesRawPayload: Data
    /** 32-bit word로 나누어 떨어지지 않는 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

/**
 변경 추적 정보

 Tag ID : HWPTAG_TRACK_CHANGE
 */
public struct HwpTrackChange: HwpFromRecord {
    public let rawPayload: Data
    public let trackChangeInfo: HwpTrackChangeInfo?
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .trackChange, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        trackChangeInfo = Self.trackChangeInfo(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** 변경 추적 정보의 알려진 선행 payload */
public struct HwpTrackChangeInfo: HwpPrimitive {
    /** 선행 32-bit 값 */
    public let headerValue: UInt32
    /** 선행 32-bit 값의 원문 payload */
    public let headerRawPayload: Data
    /** 선행 값 이후의 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

/**
 메모 모양

 Tag ID : HWPTAG_MEMO_SHAPE
 */
public struct HwpMemoShape: HwpFromRecord {
    public let rawPayload: Data
    public let shapeInfo: HwpMemoShapeInfo?
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .memoShape, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        shapeInfo = Self.shapeInfo(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** 메모 모양의 알려진 고정 폭 payload */
public struct HwpMemoShapeInfo: HwpPrimitive {
    /** 폭 */
    public let width: UInt32
    /** 선 종류 */
    public let lineType: UInt8
    /** 선 굵기 */
    public let lineWidth: UInt8
    /** 선 색상 */
    public let lineColor: HwpColor
    /** 채우기 색상 */
    public let fillColor: HwpColor
    /** 활성 상태 색상 */
    public let activeColor: HwpColor
    /** 알려진 고정 폭 필드의 원문 payload */
    public let fixedFieldsRawPayload: Data
    /** 알려진 고정 폭 필드 이후의 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

/**
 변경 추적 내용

 Tag ID : HWPTAG_TRACK_CHANGE_CONTENT
 */
public struct HwpTrackChangeContent: HwpFromRecord {
    public let rawPayload: Data
    public let contentInfo: HwpTrackChangeContentInfo?
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .trackChangeContent, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        contentInfo = Self.contentInfo(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** 변경 추적 내용의 알려진 payload */
public struct HwpTrackChangeContentInfo: HwpPrimitive {
    /** 변경 내용 종류 */
    public let kind: UInt32
    /** 변경 내용 종류 원문 payload */
    public let kindRawPayload: Data
    /** 변경 시각 */
    public let timestamp: HwpTrackChangeTimestamp
    /** 변경 시각 원문 payload */
    public let timestampRawPayload: Data
    /** 변경 시각 이후의 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

/** 변경 추적 시각 */
public struct HwpTrackChangeTimestamp: HwpPrimitive {
    public let year: UInt16
    public let month: UInt16
    public let day: UInt16
    public let hour: UInt16
    public let minute: UInt16
}

/**
 변경 추적 작성자

 Tag ID : HWPTAG_TRACK_CHANGE_AUTHOR
 */
public struct HwpTrackChangeAuthor: HwpFromRecord {
    public let rawPayload: Data
    public let authorInfo: HwpTrackChangeAuthorInfo?
    public let unknownChildren: [HwpUnknownRecord]

    static func load(_ record: HwpRecord) throws -> Self {
        try loadDocInfoRecord(record, expectedTag: .trackChangeAuthor, as: Self.self)
    }

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        authorInfo = Self.authorInfo(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** 변경 추적 작성자의 알려진 payload */
public struct HwpTrackChangeAuthorInfo: HwpPrimitive {
    /** 작성자 이름 */
    public let name: String
    /** 작성자 이름 길이 원문 payload */
    public let nameLengthRawPayload: Data
    /** 작성자 이름 원문 WCHAR payload */
    public let nameRawPayload: Data
    /** 작성자 이름 이후의 아직 해석하지 않은 payload */
    public let rawTrailing: Data
}

func loadDocInfoRecord<T: HwpFromRecord>(
    _ record: HwpRecord,
    expectedTag: HwpDocInfoTag,
    as type: T.Type
) throws -> T {
    try validateDocInfoRecordTag(record, expectedTag: expectedTag)

    var reader = DataReader(record.payload)
    let model = try type.init(&reader, record.children)
    if !reader.isEOF {
        throw HwpError.bytesAreNotEOF(model: type, remain: reader.remainBytes)
    }
    return model
}

func validateDocInfoRecordTag(
    _ record: HwpRecord,
    expectedTag: HwpDocInfoTag
) throws {
    guard record.tagId == expectedTag.rawValue else {
        throw HwpError.invalidRecordTree(
            reason: "expected DocInfo tag \(expectedTag.rawValue), got \(record.tagId)"
        )
    }
}

private extension HwpDocData {
    static func docDataInfo(from payload: Data) -> HwpDocDataInfo? {
        guard let parsed = payload.littleEndianUInt32ArrayWithTrailing(
            minimumValueCount: 1
        ) else {
            return nil
        }

        return HwpDocDataInfo(
            values: parsed.values,
            valuesRawPayload: payload.uint32ValuesRawPayload(valueCount: parsed.values.count),
            rawTrailing: parsed.rawTrailing
        )
    }
}

private extension HwpDistributeDocData {
    static func distributeDocDataInfo(from payload: Data) -> HwpDistributeDocDataInfo? {
        guard let parsed = payload.littleEndianUInt32ArrayWithTrailing(
            minimumValueCount: 1
        ) else {
            return nil
        }

        return HwpDistributeDocDataInfo(
            values: parsed.values,
            valuesRawPayload: payload.uint32ValuesRawPayload(valueCount: parsed.values.count),
            rawTrailing: parsed.rawTrailing
        )
    }
}

private extension Data {
    func uint32ValuesRawPayload(valueCount: Int) -> Data {
        prefix(valueCount * MemoryLayout<UInt32>.size)
    }
}

private extension HwpTrackChangeAuthor {
    static func authorInfo(from payload: Data) -> HwpTrackChangeAuthorInfo? {
        let lengthByteCount = MemoryLayout<UInt32>.size
        let characterByteCount = MemoryLayout<UInt16>.size
        guard payload.count >= lengthByteCount else {
            return nil
        }

        do {
            let rawCharacterCount = try payload.readLittleEndianUInt32(at: 0)
            let characterCount = Int(rawCharacterCount)
            let byteCount = characterCount * characterByteCount
            let nameOffset = lengthByteCount

            guard payload.count >= nameOffset + byteCount else {
                return nil
            }

            let nameRawPayload = Data(payload.dropFirst(nameOffset).prefix(byteCount))
            let name = try (0 ..< characterCount).map { index in
                try nameRawPayload.readLittleEndianUInt16(at: index * characterByteCount)
            }.string

            let trailingOffset = lengthByteCount + byteCount
            return HwpTrackChangeAuthorInfo(
                name: name,
                nameLengthRawPayload: Data(payload.prefix(lengthByteCount)),
                nameRawPayload: nameRawPayload,
                rawTrailing: Data(payload.dropFirst(trailingOffset))
            )
        } catch {
            return nil
        }
    }
}

private extension HwpTrackChange {
    static func trackChangeInfo(from payload: Data) -> HwpTrackChangeInfo? {
        let knownByteCount = MemoryLayout<UInt32>.size
        guard payload.count >= knownByteCount else {
            return nil
        }

        do {
            return HwpTrackChangeInfo(
                headerValue: try payload.readLittleEndianUInt32(at: 0),
                headerRawPayload: Data(payload.prefix(knownByteCount)),
                rawTrailing: Data(payload.dropFirst(knownByteCount))
            )
        } catch {
            return nil
        }
    }
}

private extension HwpTrackChangeContent {
    static func contentInfo(from payload: Data) -> HwpTrackChangeContentInfo? {
        let kindByteCount = MemoryLayout<UInt32>.size
        let timestampByteCount = MemoryLayout<UInt16>.size * 5
        let knownByteCount = kindByteCount + timestampByteCount
        guard payload.count >= knownByteCount else {
            return nil
        }

        do {
            return HwpTrackChangeContentInfo(
                kind: try payload.readLittleEndianUInt32(at: 0),
                kindRawPayload: Data(payload.prefix(kindByteCount)),
                timestamp: HwpTrackChangeTimestamp(
                    year: try payload.readLittleEndianUInt16(at: 4),
                    month: try payload.readLittleEndianUInt16(at: 6),
                    day: try payload.readLittleEndianUInt16(at: 8),
                    hour: try payload.readLittleEndianUInt16(at: 10),
                    minute: try payload.readLittleEndianUInt16(at: 12)
                ),
                timestampRawPayload: Data(
                    payload.dropFirst(kindByteCount).prefix(timestampByteCount)
                ),
                rawTrailing: Data(payload.dropFirst(knownByteCount))
            )
        } catch {
            return nil
        }
    }
}

private extension HwpMemoShape {
    static func shapeInfo(from payload: Data) -> HwpMemoShapeInfo? {
        let knownByteCount = MemoryLayout<UInt32>.size
            + MemoryLayout<UInt8>.size * 2
            + MemoryLayout<COLORREF>.size * 3
        guard payload.count >= knownByteCount else {
            return nil
        }

        do {
            return HwpMemoShapeInfo(
                width: try payload.readLittleEndianUInt32(at: 0),
                lineType: try payload.readUInt8(at: 4),
                lineWidth: try payload.readUInt8(at: 5),
                lineColor: HwpColor(try payload.readLittleEndianUInt32(at: 6)),
                fillColor: HwpColor(try payload.readLittleEndianUInt32(at: 10)),
                activeColor: HwpColor(try payload.readLittleEndianUInt32(at: 14)),
                fixedFieldsRawPayload: Data(payload.prefix(knownByteCount)),
                rawTrailing: Data(payload.dropFirst(knownByteCount))
            )
        } catch {
            return nil
        }
    }
}
