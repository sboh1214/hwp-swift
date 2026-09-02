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
    /**
     줄표 문자. 앞/뒤 장식 문자가 없을 때 쪽 번호 양옆에 붙는다 ("- 1 -").

     공개 문서(표 147)는 '항상 "-"'라 적지만, 실물은 줄표를 넣은 문서에서 0x2D('-'),
     넣지 않은 문서에서 0이다 (#138). 한글.app이 재저장한 HWPX의 `hp:pageNum`
     `sideChar`에 대응한다. 필드 이름은 호환을 위해 유지한다.
     */
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
        rawTrailing = reader.options.preservedPayload(try reader.readToEnd())
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = []
    }
}

extension HwpPageNumberPosition: HwpTagValidatedRecord, HwpRawPayloadRestoringRecord {
    static let expectedTag: HwpSectionTag = .ctrlHeader

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        try self.init(&reader)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
