import Foundation

public struct HwpColumn {
    /** ctrl id */
    public var otherCtrlId: HwpOtherCtrlId
    /** 속성의 bit 0-15 */
    public var property: HwpColumnProperty
    /** 단 사이 간격 */
    public var spacing: HWPUNIT16?
    /** 단 너비가 동일하지 않으면, 단의 개수만큼 단의 비례 폭 */
    public var widthArray: [WORD]?
    /** 속성의 bit 16-32 */
    public var property2: UInt16?
    /** 단 너비가 동일하지 않으면, 단의 개수만큼 단의 비례 간격 */
    public var gapArray: [WORD]?
    /** 단 구분선 종류 */
    public var dividerType: UInt8
    /** 단 구분선 굵기 */
    public var dividerThickness: UInt8
    /** 단 구분선 색상 */
    public var dividerColor: HwpColor
    /** 아직 해석하지 않은 trailing payload */
    public var unknown: Data?
    /** raw payload */
    public var rawPayload: Data
    /** ctrl id와 해석된 column 필드 뒤에 남은 원본 payload */
    public var rawTrailing: Data
    /** trailing payload를 little-endian WORD 단위로 해석한 값 */
    public var rawTrailingWords: [UInt16]?
    /** unknown child records */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpColumn: HwpFromData {
    // MARK: loader contract exemption - preserves column trailing payload

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        let ctrlId = try reader.read(UInt32.self)
        guard let otherCtrlId = HwpOtherCtrlId(rawValue: ctrlId),
              otherCtrlId == .column
        else {
            throw HwpError.invalidCtrlId(ctrlId: ctrlId)
        }
        self.otherCtrlId = otherCtrlId

        let property = try HwpColumnProperty.load(try reader.read(UInt16.self))

        if property.count < 2 || property.isSameWidth {
            spacing = try reader.read(HWPUNIT16.self)
            property2 = try reader.read(UInt16.self)
            widthArray = nil
            gapArray = nil
        } else {
            spacing = nil
            property2 = try reader.read(UInt16.self)

            var widths: [WORD] = []
            var gaps: [WORD] = []
            widths.reserveCapacity(property.count)
            gaps.reserveCapacity(property.count)
            for _ in 0 ..< property.count {
                widths.append(try reader.read(WORD.self))
                gaps.append(try reader.read(WORD.self))
            }
            widthArray = widths
            gapArray = gaps
        }
        self.property = property

        dividerType = try reader.read(UInt8.self)
        dividerThickness = try reader.read(UInt8.self)
        dividerColor = HwpColor(try reader.read(COLORREF.self))

        rawTrailing = try reader.readToEnd()
        rawTrailingWords = rawTrailing.littleEndianUInt16ArrayIfAligned()
        unknown = rawTrailing.isEmpty ? nil : rawTrailing
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = []
    }
}

extension HwpColumn: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates column control tag before decoding

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var column = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        column.rawPayload = record.payload
        return column
    }
}

extension HwpColumn {
    init() {
        otherCtrlId = .column
        property = HwpColumnProperty()
        spacing = 0
        widthArray = nil
        property2 = 0
        gapArray = nil
        dividerType = 0
        dividerThickness = 0
        dividerColor = HwpColor(0, 0, 0)
        rawPayload = Data()
        rawTrailing = Data()
        rawTrailingWords = []
        unknownChildren = []
    }
}
