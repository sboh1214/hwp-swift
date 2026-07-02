import Foundation

/**
 4.3.10.9. 쪽 번호 위치
 */
public struct HwpPageNumberPosition {
    /** ctrl id */
    public var otherCtrlId: HwpOtherCtrlId
    /** 속성 */
    public var property: UInt32
    /** 속성의 비트 필드 */
    public var propertyInfo: HwpPageNumberPositionProperty
    /** 사용자 기호 */
    public var userSymbol: WCHAR
    /** 앞 장식 문자 */
    public var headDecoration: WCHAR
    /** 뒤 장식 문자 */
    public var tailDecoration: WCHAR
    /** 항상 "-" */
    public var unused: WCHAR
    /** unknown */
    public var unknown: UInt32
    /** raw payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 trailing payload */
    public var rawTrailing: Data
    /** unknown child records */
    public var unknownChildren: [HwpUnknownRecord]

    public init() {
        otherCtrlId = .pageNumberPosition
        property = 0
        propertyInfo = HwpPageNumberPositionProperty()
        userSymbol = 0
        headDecoration = 0
        tailDecoration = 0
        unused = 0
        unknown = 0
        rawPayload = Data()
        rawTrailing = Data()
        unknownChildren = []
    }

    public init(
        otherCtrlId: HwpOtherCtrlId,
        property: UInt32,
        propertyInfo: HwpPageNumberPositionProperty,
        userSymbol: WCHAR,
        headDecoration: WCHAR,
        tailDecoration: WCHAR,
        unused: WCHAR,
        unknown: UInt32,
        rawPayload: Data,
        rawTrailing: Data,
        unknownChildren: [HwpUnknownRecord]
    ) {
        self.otherCtrlId = otherCtrlId
        self.property = property
        self.propertyInfo = propertyInfo
        self.userSymbol = userSymbol
        self.headDecoration = headDecoration
        self.tailDecoration = tailDecoration
        self.unused = unused
        self.unknown = unknown
        self.rawPayload = rawPayload
        self.rawTrailing = rawTrailing
        self.unknownChildren = unknownChildren
    }
}

extension HwpPageNumberPosition: HwpFromData {
    // MARK: loader contract exemption - preserves page-number-position trailing payload

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        let ctrlId = try reader.read(UInt32.self)
        guard let otherCtrlId = HwpOtherCtrlId(rawValue: ctrlId),
              otherCtrlId == .pageNumberPosition
        else {
            throw HwpError.invalidCtrlId(ctrlId: ctrlId)
        }
        self.otherCtrlId = otherCtrlId
        property = try reader.read(UInt32.self)
        propertyInfo = try HwpPageNumberPositionProperty.load(property)
        userSymbol = try reader.read(WCHAR.self)
        headDecoration = try reader.read(WCHAR.self)
        tailDecoration = try reader.read(WCHAR.self)
        unused = try reader.read(WCHAR.self)
        if reader.remainBytes >= MemoryLayout<UInt32>.size {
            unknown = try reader.read(UInt32.self)
        } else {
            unknown = 0
        }
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = []
    }
}

extension HwpPageNumberPosition: HwpFromRecord {
    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates control-header tag before decoding

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var pageNumberPosition = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        pageNumberPosition.rawPayload = record.payload
        return pageNumberPosition
    }
}
