import Foundation

/**
 문서 정보

 본문에 사용 중인 글꼴, 글자 속성, 문단 속성, 탭, 스타일 등에 문서 내 공통으로 사용되는 세부 정보를 담고 있다.
 */
public struct HwpDocInfo: HwpFromDataWithVersion {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    public let documentProperties: HwpDocumentProperties
    public let idMappings: HwpIdMappings
    public let docData: HwpDocData?
    public let distributeDocData: HwpDistributeDocData?
    public let layoutCompatibility: HwpLayoutCompatibility?
    public let topLevelTrackChangeArray: [HwpTrackChange]
    public let trackChangeArray: [HwpTrackChange]
    public let memoShapeArray: [HwpMemoShape]
    public let trackChangeContentArray: [HwpTrackChangeContent]
    public let trackChangeAuthorArray: [HwpTrackChangeAuthor]
    public let topLevelForbiddenCharArray: [HwpForbiddenChar]
    public let forbiddenCharArray: [HwpForbiddenChar]
    public let unknownRecords: [HwpUnknownRecord]

    public var compatibleDocument: HwpCompatibleDocument?

    init() {
        let defaultIdMappings = HwpIdMappings()
        rawPayload = Data()
        documentProperties = HwpDocumentProperties()
        idMappings = defaultIdMappings
        docData = nil
        distributeDocData = nil
        layoutCompatibility = HwpLayoutCompatibility()
        topLevelTrackChangeArray = []
        trackChangeArray = []
        memoShapeArray = []
        trackChangeContentArray = []
        trackChangeAuthorArray = []
        topLevelForbiddenCharArray = []
        forbiddenCharArray = defaultIdMappings.forbiddenCharArray
        unknownRecords = []
        compatibleDocument = HwpCompatibleDocument()
    }

    // swiftlint:disable:next function_body_length
    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let record = try parseTreeRecord(data: try reader.readBytes(reader.remainBytes))
        let children = record.children

        guard let documentProperties = children
            .first(where: { $0.tagId == HwpDocInfoTag.documentProperties.rawValue })
        else {
            throw HwpError.recordDoesNotExist(tag: HwpDocInfoTag.documentProperties.rawValue)
        }
        self.documentProperties = try HwpDocumentProperties.load(documentProperties.payload)

        guard let idMappings = children
            .first(where: { $0.tagId == HwpDocInfoTag.idMappings.rawValue })
        else {
            throw HwpError.recordDoesNotExist(tag: HwpDocInfoTag.idMappings.rawValue)
        }
        self.idMappings = try HwpIdMappings.load(idMappings, version)

        if let compatibleDocument = children
            .first(where: { $0.tagId == HwpDocInfoTag.compatibleDocument.rawValue })
        {
            self.compatibleDocument = try HwpCompatibleDocument.load(compatibleDocument)
        } else {
            compatibleDocument = nil
        }

        if let docData = children.first(where: { $0.tagId == HwpDocInfoTag.docData.rawValue }) {
            self.docData = try HwpDocData.load(docData)
        } else {
            docData = nil
        }

        if let distributeDocData = children
            .first(where: { $0.tagId == HwpDocInfoTag.distributeDocData.rawValue })
        {
            self.distributeDocData = try HwpDistributeDocData.load(distributeDocData)
        } else {
            distributeDocData = nil
        }

        if let layoutCompatibility = children
            .first(where: { $0.tagId == HwpDocInfoTag.layoutCompatibility.rawValue })
        {
            self.layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibility)
        } else {
            layoutCompatibility = compatibleDocument?.layoutCompatibility
        }

        let topLevelTrackChanges = try children
            .filter { $0.tagId == HwpDocInfoTag.trackChange.rawValue }
            .map(HwpTrackChange.load)
        topLevelTrackChangeArray = topLevelTrackChanges
        trackChangeArray = self.idMappings.trackChangeArray + topLevelTrackChanges

        let topLevelMemoShapes = try children
            .filter { $0.tagId == HwpDocInfoTag.memoShape.rawValue }
            .map(HwpMemoShape.load)
        memoShapeArray = self.idMappings.memoShapeArray + topLevelMemoShapes

        let topLevelTrackChangeContents = try children
            .filter { $0.tagId == HwpDocInfoTag.trackChangeContent.rawValue }
            .map(HwpTrackChangeContent.load)
        trackChangeContentArray =
            self.idMappings.trackChangeContentArray + topLevelTrackChangeContents
        let topLevelTrackChangeAuthors = try children
            .filter { $0.tagId == HwpDocInfoTag.trackChangeAuthor.rawValue }
            .map(HwpTrackChangeAuthor.load)
        trackChangeAuthorArray = self.idMappings.trackChangeAuthorArray + topLevelTrackChangeAuthors
        let topLevelForbiddenChars = try children
            .filter { $0.tagId == HwpDocInfoTag.forbiddenChar.rawValue }
            .map(HwpForbiddenChar.load)
        topLevelForbiddenCharArray = topLevelForbiddenChars
        forbiddenCharArray = self.idMappings.forbiddenCharArray
            + (docData?.forbiddenCharArray ?? [])
            + topLevelForbiddenChars

        unknownRecords = Self.unconsumedRecords(from: children).map(HwpUnknownRecord.init)
        rawPayload = try reader.consumedData(from: startOffset)
    }
}

private extension HwpDocInfo {
    static func unconsumedRecords(from children: [HwpRecord]) -> [HwpRecord] {
        var consumedSingletons = Set<UInt32>()

        return children.filter { child in
            if multiRecordTags.contains(child.tagId) {
                return false
            }

            if singletonRecordTags.contains(child.tagId) {
                if consumedSingletons.contains(child.tagId) {
                    return true
                }
                consumedSingletons.insert(child.tagId)
                return false
            }

            return true
        }
    }

    static var singletonRecordTags: Set<UInt32> {
        [
            HwpDocInfoTag.documentProperties.rawValue,
            HwpDocInfoTag.idMappings.rawValue,
            HwpDocInfoTag.docData.rawValue,
            HwpDocInfoTag.distributeDocData.rawValue,
            HwpDocInfoTag.compatibleDocument.rawValue,
            HwpDocInfoTag.layoutCompatibility.rawValue,
        ]
    }

    static var multiRecordTags: Set<UInt32> {
        [
            HwpDocInfoTag.trackChange.rawValue,
            HwpDocInfoTag.memoShape.rawValue,
            HwpDocInfoTag.trackChangeContent.rawValue,
            HwpDocInfoTag.trackChangeAuthor.rawValue,
            HwpDocInfoTag.forbiddenChar.rawValue,
        ]
    }
}
