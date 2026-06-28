import Foundation

/**
 아이디 매핑 헤더

 Tag ID : HWPTAG_ID_MAPPINGS
 */
public struct HwpIdMappings {
    /** 메모 모양 (5.0.2.1 이상) */
    public var memoShapeCount: Int32?
    /** 변경 추적 내용 (5.0.3.2 이상) */
    public var changeTraceCount: Int32?
    /** 변경추적 사용자 (5.0.3.2 이상) */
    public var changeTraceUserCount: Int32?

    /** 바이너리 데이터 */
    public var binDataArray: [HwpBinData]

    /** 한글 글꼴 */
    public var faceNameKoreanArray: [HwpFaceName]
    /** 영어 글꼴 */
    public var faceNameEnglishArray: [HwpFaceName]
    /** 한자 글꼴 */
    public var faceNameChineseArray: [HwpFaceName]
    /** 일어 글꼴 */
    public var faceNameJapaneseArray: [HwpFaceName]
    /** 기타 글꼴 */
    public var faceNameEtcArray: [HwpFaceName]
    /** 기호 글꼴 */
    public var faceNameSymbolArray: [HwpFaceName]
    /** 사용자 글꼴 */
    public var faceNameUserArray: [HwpFaceName]

    /** 테두리/배경 */
    public var borderFillArray: [HwpBorderFill]
    /** 글자 모양 */
    public var charShapeArray: [HwpCharShape]
    /** 탭 정의 */
    public var tabDefArray: [HwpTabDef]
    /** 문단 번호 */
    public var numberingArray: [HwpNumbering]
    /** 글머리표 */
    public var bulletArray: [HwpBullet]
    /** 문단 모양 */
    public var paraShapeArray: [HwpParaShape]
    /** 스타일 */
    public var styleArray: [HwpStyle]
    /** 메모 모양 */
    public var memoShapeArray: [HwpMemoShape]
    /** 변경 추적 정보 */
    public var trackChangeArray: [HwpTrackChange]
    /** 변경 추적 내용 */
    public var trackChangeContentArray: [HwpTrackChangeContent]
    /** 변경 추적 작성자 */
    public var trackChangeAuthorArray: [HwpTrackChangeAuthor]
    /**
     금칙처리문자

     NOTE : 문서화되어있지 않음
     */
    public var forbiddenCharArray: [HwpForbiddenChar]
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpIdMappings: HwpFromRecordWithVersion {
    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateDocInfoRecordTag(record, expectedTag: .idMappings)

        var reader = DataReader(record.payload)
        let idMappings = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return idMappings
    }

    // swiftlint:disable:next function_body_length
    init() {
        memoShapeCount = 0
        changeTraceCount = 0
        changeTraceUserCount = 0

        binDataArray = [HwpBinData]()

        let dotum = HwpFaceName("함초롬돋움", [2, 11, 6, 4, 0, 1, 1, 1, 1, 1], "HCR Dotum")
        let batang = HwpFaceName("함초롬바탕", [2, 3, 6, 4, 0, 1, 1, 1, 1, 1], "HCR Batang")

        faceNameKoreanArray = [dotum, batang]

        faceNameEnglishArray = [dotum, batang]

        faceNameChineseArray = [dotum, batang]

        faceNameJapaneseArray = [dotum, batang]

        faceNameEtcArray = [dotum, batang]

        faceNameSymbolArray = [dotum, batang]

        faceNameUserArray = [dotum, batang]

        // swiftlint:disable line_length
        borderFillArray = [
            HwpBorderFill(fillInfo: [0, 0, 0, 0, 0, 0, 0, 0]),
            HwpBorderFill(fillInfo: [1, 0, 0, 0, 255, 255, 255, 255, 153, 153, 153, 0, 255, 255, 255, 255, 0, 0, 0, 0, 0]),
        ]

        charShapeArray = [
            HwpCharShape(faceId: [1, 1, 1, 1, 1, 1, 1], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 1000, faceColor: HwpColor()),
            HwpCharShape(faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 1000, faceColor: HwpColor()),
            HwpCharShape(faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 900, faceColor: HwpColor()),
            HwpCharShape(faceId: [1, 1, 1, 1, 1, 1, 1], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 900, faceColor: HwpColor()),
            HwpCharShape(faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [-5, -5, -5, -5, -5, -5, -5], baseSize: 900, faceColor: HwpColor()),
            HwpCharShape(faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 1600, faceColor: HwpColor(46, 46, 46)),
            HwpCharShape(faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0], baseSize: 1100, faceColor: HwpColor()),
        ]

        tabDefArray = [HwpTabDef(property: 0), HwpTabDef(property: 1), HwpTabDef(property: 2)]

        numberingArray = [
            HwpNumbering(formatArray: [
                HwpNumberingFormat(property: [12, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 3, format: "^1."),
                HwpNumberingFormat(property: [12, 1, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 3, format: "^2."),
                HwpNumberingFormat(property: [12, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 3, format: "^3)"),
                HwpNumberingFormat(property: [12, 1, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 3, format: "^4)"),
                HwpNumberingFormat(property: [12, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 4, format: "(^5)"),
                HwpNumberingFormat(property: [12, 1, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 4, format: "(^6)"),
                HwpNumberingFormat(property: [44, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 2, format: "^7"),
            ],
            startingIndex: 0,
            startingIndexArray: [1, 1, 1, 1, 1, 1, 1],
            extendedFormatArray: [
                HwpNumberingFormat(property: [8, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 0, format: ""),
                HwpNumberingFormat(property: [8, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 0, format: ""),
                HwpNumberingFormat(property: [8, 0, 0, 0, 0, 0, 50, 0, 255, 255, 255, 255], formatLength: 0, format: ""),
            ],
            extendedStartingIndexArray: [1, 1, 1]),
        ]

        bulletArray = [HwpBullet]()

        paraShapeArray = [
            HwpParaShape(property1: 384, marginLeft: 0, tabDefId: 0, unknown: 0),
            HwpParaShape(property1: 384, marginLeft: 3000, tabDefId: 0, unknown: 0),
            HwpParaShape(property1: 8_399_232, marginLeft: 2000, tabDefId: 1, unknown: 0),
            HwpParaShape(property1: 41_953_664, marginLeft: 4000, tabDefId: 1, unknown: 1),
            HwpParaShape(property1: 75_508_096, marginLeft: 6000, tabDefId: 1, unknown: 2),
            HwpParaShape(property1: 109_062_528, marginLeft: 8000, tabDefId: 1, unknown: 3),
            HwpParaShape(property1: 142_616_960, marginLeft: 10000, tabDefId: 1, unknown: 4),
            HwpParaShape(property1: 176_171_392, marginLeft: 12000, tabDefId: 1, unknown: 5),
            HwpParaShape(property1: 209_725_824, marginLeft: 14000, tabDefId: 1, unknown: 6),
            HwpParaShape(property1: 256, marginLeft: 0, lineSpacing: 150, tabDefId: 0, lineSpacing2: 150, unknown: 0),
            HwpParaShape(property1: 384, marginLeft: 0, indent: -2620, lineSpacing: 130, tabDefId: 0, lineSpacing2: 130, unknown: 0),
            HwpParaShape(property1: 260, marginLeft: 0, lineSpacing: 130, tabDefId: 0, lineSpacing2: 130, unknown: 0),
            HwpParaShape(property1: 10500, marginLeft: 0, paragraphSpacingTop: 2400, paragraphSpacingBottom: 600, tabDefId: 1, unknown: 0),
            HwpParaShape(property1: 260, marginLeft: 0, paragraphSpacingBottom: 1400, tabDefId: 2, unknown: 0),
            HwpParaShape(property1: 260, marginLeft: 2200, paragraphSpacingBottom: 1400, tabDefId: 2, unknown: 0),
            HwpParaShape(property1: 260, marginLeft: 4400, paragraphSpacingBottom: 1400, tabDefId: 2, unknown: 0),
            HwpParaShape(property1: 209_715_584, marginLeft: 18000, tabDefId: 1, unknown: 8),
            HwpParaShape(property1: 209_715_584, marginLeft: 20000, tabDefId: 1, unknown: 9),
            HwpParaShape(property1: 209_715_584, marginLeft: 16000, tabDefId: 1, unknown: 7),
        ]

        styleArray = [
            HwpStyle("바탕글", "Normal", nextId: 0, paraShapeId: 0, charShapeId: 0),
            HwpStyle("본문", "Body", nextId: 1, paraShapeId: 1, charShapeId: 0),
            HwpStyle("개요 1", "Outline 1", nextId: 2, paraShapeId: 2, charShapeId: 0),
            HwpStyle("개요 2", "Outline 2", nextId: 3, paraShapeId: 3, charShapeId: 0),
            HwpStyle("개요 3", "Outline 3", nextId: 4, paraShapeId: 4, charShapeId: 0),
            HwpStyle("개요 4", "Outline 4", nextId: 5, paraShapeId: 5, charShapeId: 0),
            HwpStyle("개요 5", "Outline 5", nextId: 6, paraShapeId: 6, charShapeId: 0),
            HwpStyle("개요 6", "Outline 6", nextId: 7, paraShapeId: 7, charShapeId: 0),
            HwpStyle("개요 7", "Outline 7", nextId: 8, paraShapeId: 8, charShapeId: 0),
            HwpStyle("개요 8", "Outline 8", nextId: 9, paraShapeId: 18, charShapeId: 0),
            HwpStyle("개요 9", "Outline 9", nextId: 10, paraShapeId: 16, charShapeId: 0),
            HwpStyle("개요 10", "Outline 10", nextId: 11, paraShapeId: 17, charShapeId: 0),
            HwpStyle("쪽 번호", "Page Number", property: 1, nextId: 0, paraShapeId: 0, charShapeId: 1),
            HwpStyle("머리말", "Header", nextId: 13, paraShapeId: 9, charShapeId: 2),
            HwpStyle("각주", "Footnote", nextId: 14, paraShapeId: 10, charShapeId: 3),
            HwpStyle("미주", "Endnote", nextId: 15, paraShapeId: 10, charShapeId: 3),
            HwpStyle("메모", "Memo", nextId: 16, paraShapeId: 11, charShapeId: 4),
            HwpStyle("차례 제목", "TOC Heading", nextId: 17, paraShapeId: 12, charShapeId: 5),
            HwpStyle("차례 1", "TOC 1", nextId: 18, paraShapeId: 13, charShapeId: 6),
            HwpStyle("차례 2", "TOC 2", nextId: 19, paraShapeId: 14, charShapeId: 6),
            HwpStyle("차례 3", "TOC 3", nextId: 20, paraShapeId: 15, charShapeId: 6),
        ]

        memoShapeArray = []
        trackChangeArray = []
        trackChangeContentArray = []
        trackChangeAuthorArray = []
        forbiddenCharArray = [HwpForbiddenChar(data: Data(repeating: 0, count: 16))]
        unknownChildren = []
        // swiftlint:enable line_length
    }

    // swiftlint:disable:next function_body_length
    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws {
        let binaryDataCount = try reader.read(Int32.self)
        let faceNameKoreanCount = try reader.read(Int32.self)
        let faceNameEnglishCount = try reader.read(Int32.self)
        let faceNameChineseCount = try reader.read(Int32.self)
        let faceNameJapaneseCount = try reader.read(Int32.self)
        let faceNameEtcCount = try reader.read(Int32.self)
        let faceNameSymbolCount = try reader.read(Int32.self)
        let faceNameUserCount = try reader.read(Int32.self)
        let borderFillCount = try reader.read(Int32.self)
        let charShapeCount = try reader.read(Int32.self)
        let tabDefCount = try reader.read(Int32.self)
        let numberingCount = try reader.read(Int32.self)
        let bulletCount = try reader.read(Int32.self)
        let paraShapeCount = try reader.read(Int32.self)
        let styleCount = try reader.read(Int32.self)
        if version >= HwpVersion(5, 0, 2, 1) {
            memoShapeCount = try reader.read(Int32.self)
        }
        if version >= HwpVersion(5, 0, 3, 2) {
            changeTraceCount = try reader.read(Int32.self)
            changeTraceUserCount = try reader.read(Int32.self)
        }

        var childrenArray = children
        var previouslyCountedTags = Set<UInt32>()

        func popRequired(
            _ expectedTag: HwpDocInfoTag,
            _ count: Int32,
            completesTag: Bool = true
        ) throws -> [HwpRecord] {
            let records = try popTagged(
                expectedTag,
                count,
                from: &childrenArray,
                preservingPreviouslyCountedTags: previouslyCountedTags
            )
            if completesTag {
                previouslyCountedTags.insert(expectedTag.rawValue)
            }
            return records
        }

        binDataArray = try popRequired(.binData, binaryDataCount)
            .map { try HwpBinData.load($0.payload) }
        faceNameKoreanArray = try popRequired(.faceName, faceNameKoreanCount, completesTag: false)
            .map { try HwpFaceName.load($0.payload) }
        faceNameEnglishArray = try popRequired(.faceName, faceNameEnglishCount, completesTag: false)
            .map { try HwpFaceName.load($0.payload) }
        faceNameChineseArray = try popRequired(.faceName, faceNameChineseCount, completesTag: false)
            .map { try HwpFaceName.load($0.payload) }
        let faceNameJapaneseRecords = try popRequired(
            .faceName,
            faceNameJapaneseCount,
            completesTag: false
        )
        faceNameJapaneseArray = try faceNameJapaneseRecords.map { try HwpFaceName.load($0.payload) }
        faceNameEtcArray = try popRequired(.faceName, faceNameEtcCount, completesTag: false)
            .map { try HwpFaceName.load($0.payload) }
        faceNameSymbolArray = try popRequired(.faceName, faceNameSymbolCount, completesTag: false)
            .map { try HwpFaceName.load($0.payload) }
        faceNameUserArray = try popRequired(.faceName, faceNameUserCount)
            .map { try HwpFaceName.load($0.payload) }

        borderFillArray = try popRequired(.borderFill, borderFillCount)
            .map { try HwpBorderFill.load($0.payload) }
        charShapeArray = try popRequired(.charShape, charShapeCount)
            .map { try HwpCharShape.load($0.payload, version) }
        tabDefArray = try popRequired(.tabDef, tabDefCount)
            .map { try HwpTabDef.load($0.payload) }
        numberingArray = try popRequired(.numbering, numberingCount)
            .map { try HwpNumbering.load($0.payload, version) }
        bulletArray = try popRequired(.bullet, bulletCount)
            .map { try HwpBullet.load($0.payload) }
        paraShapeArray = try popRequired(.paraShape, paraShapeCount)
            .map { try HwpParaShape.load($0.payload, version) }
        styleArray = try popRequired(.style, styleCount)
            .map { try HwpStyle.load($0.payload) }
        memoShapeArray = try popOptionalTagged(
            .memoShape,
            memoShapeCount ?? 0,
            from: &childrenArray
        )
        .map(HwpMemoShape.load)
        trackChangeArray = try popAllTagged(.trackChange, from: &childrenArray)
            .map(HwpTrackChange.load)
        trackChangeContentArray = try popOptionalTagged(
            .trackChangeContent,
            changeTraceCount ?? 0,
            from: &childrenArray
        )
        .map(HwpTrackChangeContent.load)
        trackChangeAuthorArray = try popOptionalTagged(
            .trackChangeAuthor,
            changeTraceUserCount ?? 0,
            from: &childrenArray
        ).map(HwpTrackChangeAuthor.load)

        forbiddenCharArray = [HwpForbiddenChar]()
        unknownChildren = []

        if childrenArray.isEmpty {
            return
        }
        for child in childrenArray {
            switch child.tagId {
            case HwpDocInfoTag.forbiddenChar.rawValue:
                forbiddenCharArray.append(try HwpForbiddenChar.load(child))
            default:
                unknownChildren.append(HwpUnknownRecord(child))
            }
        }
    }
}

private func popTagged(
    _ expectedTag: HwpDocInfoTag,
    _ count: Int32,
    from children: inout [HwpRecord],
    preservingPreviouslyCountedTags previouslyCountedTags: Set<UInt32> = []
) throws -> [HwpRecord] {
    let expectedCount = try validatedRecordCount(count, for: expectedTag)
    guard expectedCount > 0 else {
        return []
    }
    guard expectedCount <= children.count else {
        throw HwpError.invalidRecordTree(
            reason:
            "record count \(expectedCount) exceeds available child records \(children.count)"
        )
    }

    var records = [HwpRecord]()
    var consumedIndexes = Set<Int>()
    for (index, child) in children.enumerated() {
        if child.tagId == expectedTag.rawValue {
            records.append(child)
            consumedIndexes.insert(index)
            if records.count == expectedCount {
                break
            }
        } else if previouslyCountedTags.contains(child.tagId) {
            continue
        } else if HwpDocInfoTag(rawValue: child.tagId) == .reserved {
            continue
        } else if HwpDocInfoTag(rawValue: child.tagId) != nil {
            throw HwpError.invalidRecordTree(
                reason: "expected DocInfo tag \(expectedTag.rawValue), got \(child.tagId)"
            )
        }
    }

    guard records.count == expectedCount else {
        throw HwpError.invalidRecordTree(
            reason: "expected \(expectedCount) tag \(expectedTag.rawValue), got \(records.count)"
        )
    }

    children = children.enumerated()
        .filter { !consumedIndexes.contains($0.offset) }
        .map(\.element)
    return records
}

private func popOptionalTagged(
    _ expectedTag: HwpDocInfoTag,
    _ count: Int32,
    from children: inout [HwpRecord]
) throws -> [HwpRecord] {
    let expectedCount = try validatedRecordCount(count, for: expectedTag)
    guard expectedCount > 0 else {
        return []
    }

    var records = [HwpRecord]()
    var remaining = [HwpRecord]()
    for child in children {
        if child.tagId == expectedTag.rawValue, records.count < expectedCount {
            records.append(child)
        } else {
            remaining.append(child)
        }
    }
    guard records.count == expectedCount else {
        throw HwpError.invalidRecordTree(
            reason: "expected \(expectedCount) tag \(expectedTag.rawValue), got \(records.count)"
        )
    }
    children = remaining
    return records
}

private func validatedRecordCount(_ count: Int32, for tag: HwpDocInfoTag) throws -> Int {
    guard let expectedCount = Int(exactly: count), expectedCount >= 0 else {
        throw HwpError.invalidRecordTree(
            reason: "invalid DocInfo record count \(count) for tag \(tag.rawValue)"
        )
    }
    return expectedCount
}

private func popAllTagged(
    _ expectedTag: HwpDocInfoTag,
    from children: inout [HwpRecord]
) -> [HwpRecord] {
    var records = [HwpRecord]()
    var remaining = [HwpRecord]()
    for child in children {
        if child.tagId == expectedTag.rawValue {
            records.append(child)
        } else {
            remaining.append(child)
        }
    }
    children = remaining
    return records
}
