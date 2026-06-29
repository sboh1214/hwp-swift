import Foundation

/**
 문단 번호

 Tag ID : HWPTAG_NUMBERING

 * 잘못된 문서화
 */
public struct HwpNumbering {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /**
     7회 반복 수준(1~7)

     각 레벨에 해당하는 숫자 또는 문자 또는 기호를 표시
     */
    public var formatArray: [HwpNumberingFormat]
    /** 시작 번호 */
    public let startingIndex: UInt16
    /** 수준별 시작번호 (5.0.2.5 이상) */
    public var startingIndexArray: [UInt32]?
    /**
     3회 반복 수준(8~10)

     각 레벨에 해당하는 숫자 또는 문자 또는 기호를 표시
     */
    public var extendedFormatArray: [HwpNumberingFormat]?
    /** 확장 수준별 시작번호 (5.1.0.0 이상) */
    public var extendedStartingIndexArray: [UInt32]?
}

extension HwpNumbering: HwpFromDataWithVersion {
    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        formatArray = [HwpNumberingFormat]()
        for _ in 1 ... 7 {
            formatArray.append(try Self.numberingFormat(from: &reader))
        }
        startingIndex = try reader.read(UInt16.self)
        if version >= HwpVersion(5, 0, 2, 5) {
            let startingIndexCount = try Self.startingIndexCount(from: reader, version)
            startingIndexArray = try reader.read(UInt32.self, startingIndexCount)
        }
        if version >= HwpVersion(5, 1, 0, 0) {
            extendedFormatArray = [HwpNumberingFormat]()
            for _ in 8 ... 10 {
                extendedFormatArray?.append(try Self.numberingFormat(from: &reader))
            }
            extendedStartingIndexArray = try reader.read(UInt32.self, 3)
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(_ data: Data, _ version: HwpVersion) throws -> Self {
        var reader = DataReader(data)
        var numbering = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        numbering.rawPayload = data
        return numbering
    }
}

private extension HwpNumbering {
    static func numberingFormat(from reader: inout DataReader) throws -> HwpNumberingFormat {
        let bytes = try reader.readBytes(12).bytes
        let length = try reader.read(WORD.self)
        let formatStartOffset = reader.byteOffset
        let formatCharacters = try reader.read(WCHAR.self, length)
        let formatRawPayload = try reader.consumedData(from: formatStartOffset)
        return try HwpNumberingFormat(
            bytes,
            length,
            formatCharacters.string,
            formatRawPayload: formatRawPayload
        )
    }

    static func startingIndexCount(
        from reader: DataReader,
        _ version: HwpVersion
    ) throws -> Int {
        let documentedCount = 7
        let byteWidth = MemoryLayout<UInt32>.size

        if version >= HwpVersion(5, 1, 0, 0) {
            return documentedCount
        }

        let availableCount = min(documentedCount, reader.remainBytes / byteWidth)
        let unreadTrailingBytes = reader.remainBytes - (availableCount * byteWidth)
        guard unreadTrailingBytes == 0 || availableCount == documentedCount else {
            throw HwpError.truncatedData(expected: byteWidth, actual: unreadTrailingBytes)
        }
        return availableCount
    }
}

extension HwpNumbering {
    init(
        formatArray: [HwpNumberingFormat],
        startingIndex: UInt16,
        startingIndexArray: [UInt32]? = nil,
        extendedFormatArray: [HwpNumberingFormat]? = nil,
        extendedStartingIndexArray: [UInt32]? = nil,
        rawPayload: Data = Data()
    ) {
        self.rawPayload = rawPayload
        self.formatArray = formatArray
        self.startingIndex = startingIndex
        self.startingIndexArray = startingIndexArray
        self.extendedFormatArray = extendedFormatArray
        self.extendedStartingIndexArray = extendedStartingIndexArray
    }
}
