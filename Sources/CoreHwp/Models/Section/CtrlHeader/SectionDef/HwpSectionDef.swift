import Foundation

/** 구역 정의 */
public struct HwpSectionDef {
    public var pageDef: HwpPageDef
    /** 각주 모양 정보 */
    public var footNoteShape: HwpFootnoteShape
    /** 미주 모양 정보 */
    public var endNoteShape: HwpFootnoteShape
    /** 양쪽 테두리/배경 정보 */
    public var pageBorderFillBoth: HwpPageBorderFill
    /** 짝수쪽 테두리/배경 정보 */
    public var pageBorderFillEven: HwpPageBorderFill
    /** 홀수쪽 테두리/배경 정보 */
    public var pageBorderFillOdd: HwpPageBorderFill
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
    /** raw payload */
    public var rawPayload: Data

    /** ctrl id */
    public var ctrlId: UInt32
    /** 속성(표 130 참조) */
    public var property: UInt32
    /** 속성 bit field */
    public var propertyInfo: HwpSectionDefProperty
    /** 동일한 페이지에서 서로 다른 단 사이의 간격 */
    public var columnSpacing: HWPUNIT16
    /**
     세로로 줄맞춤을 할지 여부

     0 = off, 1 - n = 간격을 HWPUNIT 단위로 지정
     */
    public var verticalLineAlign: HWPUNIT16
    /**
     가로로 줄맞춤을 할지 여부

     0 = off, 1 - n = 간격을 HWPUNIT 단위로 지정
     */
    public var horizontalLineAlign: HWPUNIT16
    /**
     기본 탭 간격

     hwpunit 또는 relative characters
     */
    public var defaultTabSpacing: HWPUNIT
    /** 번호 문단 모양 ID */
    public var numberParaShapeId: UInt16
    /**
     쪽 번호

     (0 = 앞 구역에 이어, n = 임의의 번호로 시작)
     */
    public var pageStartNumber: UInt16
    /**
     그림 번호

     (0 = 앞 구역에 이어, n = 임의의 번호로 시작)
     */
    public var pictureStartNumber: UInt16
    /**
     표 번호

     (0 = 앞 구역에 이어, n = 임의의 번호로 시작)
     */
    public var tableStartNumber: UInt16
    /**
     수식 번호

     (0 = 앞 구역에 이어, n = 임의의 번호로 시작)
     */
    public var equationNumber: UInt16
    /**
     대표Language

     (Language값이 없으면(==0), Application에 지정된 Language)
     5.0.1.5 이상
     */
    public var defaultLanguage: UInt16?
    /** 아직 해석하지 않은 version-specific tail */
    public var unknown: Data
}

extension HwpSectionDef: HwpFromRecordWithVersion {
    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        pageDef = try HwpPageDef.load(requiredChild(.pageDef, children).payload)

        let footnoteRecords = try requiredChildPair(.footnoteShape, children)
        footNoteShape = try HwpFootnoteShape.load(footnoteRecords.first.payload)
        endNoteShape = try HwpFootnoteShape.load(footnoteRecords.second.payload)

        let pageBorderFillRecords = try requiredChildTriple(.pageBorderFill, children)
        pageBorderFillBoth = try HwpPageBorderFill.load(pageBorderFillRecords.first.payload)
        pageBorderFillEven = try HwpPageBorderFill.load(pageBorderFillRecords.second.payload)
        pageBorderFillOdd = try HwpPageBorderFill.load(pageBorderFillRecords.third.payload)
        unknownChildren = unconsumedSectionDefChildren(children)

        ctrlId = try reader.read(UInt32.self)
        guard ctrlId == HwpOtherCtrlId.section.rawValue else {
            throw HwpError.invalidCtrlId(ctrlId: ctrlId)
        }
        property = try reader.read(UInt32.self)
        propertyInfo = try HwpSectionDefProperty.load(property)
        columnSpacing = try reader.read(HWPUNIT16.self)
        verticalLineAlign = try reader.read(HWPUNIT16.self)
        horizontalLineAlign = try reader.read(HWPUNIT16.self)
        defaultTabSpacing = try reader.read(HWPUNIT.self)
        numberParaShapeId = try reader.read(UInt16.self)
        pageStartNumber = try reader.read(UInt16.self)
        pictureStartNumber = try reader.read(UInt16.self)
        tableStartNumber = try reader.read(UInt16.self)
        equationNumber = try reader.read(UInt16.self)
        if version >= HwpVersion(5, 0, 1, 5) {
            defaultLanguage = try reader.read(UInt16.self)
        }

        // MARK: loader contract exemption - preserves SECTION_DEF version-specific tail

        unknown = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
    }

    // MARK: loader contract exemption - validates section control tag before versioned decode

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var sectionDef = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        sectionDef.rawPayload = record.payload
        return sectionDef
    }
}

extension HwpSectionDef {
    init() {
        pageDef = HwpPageDef()
        footNoteShape = HwpFootnoteShape(
            dividerLength: -1, dividerMarginTop: -1, dividerType: 27, dividerThickness: 1
        )
        endNoteShape = HwpFootnoteShape(
            dividerLength: 12280, dividerMarginTop: 224, dividerType: 0, dividerThickness: 0
        )
        pageBorderFillBoth = HwpPageBorderFill(property: 158_923_201)
        pageBorderFillEven = HwpPageBorderFill(property: 656_083_841)
        pageBorderFillOdd = HwpPageBorderFill(property: 1)
        unknownChildren = []
        rawPayload = Data()

        ctrlId = 1_936_024_420
        property = 0
        propertyInfo = HwpSectionDefProperty()
        columnSpacing = 1134
        verticalLineAlign = 0
        horizontalLineAlign = 0
        defaultTabSpacing = 8000
        numberParaShapeId = 1
        pageStartNumber = 0
        pictureStartNumber = 0
        tableStartNumber = 0
        equationNumber = 0

        defaultLanguage = 0
        unknown = Data(Array(repeating: 0, count: 17))
    }
}

private func requiredChild(_ tag: HwpSectionTag, _ children: [HwpRecord]) throws -> HwpRecord {
    guard let child = children.first(where: { $0.tagId == tag.rawValue }) else {
        throw HwpError.recordDoesNotExist(tag: tag.rawValue)
    }
    return child
}

private struct RequiredChildPair {
    let first: HwpRecord
    let second: HwpRecord
}

private struct RequiredChildTriple {
    let first: HwpRecord
    let second: HwpRecord
    let third: HwpRecord
}

private func requiredChildPair(
    _ tag: HwpSectionTag,
    _ children: [HwpRecord]
) throws -> RequiredChildPair {
    var iterator = children.filter { $0.tagId == tag.rawValue }.makeIterator()
    guard let first = iterator.next(), let second = iterator.next() else {
        throw HwpError.recordDoesNotExist(tag: tag.rawValue)
    }
    return RequiredChildPair(first: first, second: second)
}

private func requiredChildTriple(
    _ tag: HwpSectionTag,
    _ children: [HwpRecord]
) throws -> RequiredChildTriple {
    var iterator = children.filter { $0.tagId == tag.rawValue }.makeIterator()
    guard let first = iterator.next(),
          let second = iterator.next(),
          let third = iterator.next()
    else {
        throw HwpError.recordDoesNotExist(tag: tag.rawValue)
    }
    return RequiredChildTriple(first: first, second: second, third: third)
}

private func unconsumedSectionDefChildren(_ children: [HwpRecord]) -> [HwpUnknownRecord] {
    var pageDefCount = 0
    var footnoteShapeCount = 0
    var pageBorderFillCount = 0

    return children.compactMap { child in
        switch child.tagId {
        case HwpSectionTag.pageDef.rawValue:
            pageDefCount += 1
            return pageDefCount == 1 ? nil : HwpUnknownRecord(child)
        case HwpSectionTag.footnoteShape.rawValue:
            footnoteShapeCount += 1
            return footnoteShapeCount <= 2 ? nil : HwpUnknownRecord(child)
        case HwpSectionTag.pageBorderFill.rawValue:
            pageBorderFillCount += 1
            return pageBorderFillCount <= 3 ? nil : HwpUnknownRecord(child)
        default:
            return HwpUnknownRecord(child)
        }
    }
}
