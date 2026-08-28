import Foundation

/**
 문서 정보 스트림으로, 본문에서 공통으로 사용하는 글꼴, 글자 모양, 문단
 모양, 탭, 스타일 등의 정보를 담는다.

 본문 구역(`HwpSection`)의 레코드가 ID로 참조하는 전역 정의는
 `idMappings`에 모여 있다. `HwpFile.docInfo`로 접근한다.
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

    // MARK: loader contract exemption - DocInfo stream must be parsed as one record tree

    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        let record = try parseTreeRecord(
            data: try reader.readBytes(reader.remainBytes),
            options: reader.options
        )
        let children = Self.classify(record.children)

        guard let documentProperties = children.documentProperties else {
            throw HwpError.recordDoesNotExist(tag: HwpDocInfoTag.documentProperties.rawValue)
        }
        self.documentProperties = try HwpDocumentProperties.load(
            documentProperties.payload,
            options: reader.options
        )

        guard let idMappings = children.idMappings else {
            throw HwpError.recordDoesNotExist(tag: HwpDocInfoTag.idMappings.rawValue)
        }
        self.idMappings = try HwpIdMappings.load(idMappings, version)

        compatibleDocument = try children.compatibleDocument.map(HwpCompatibleDocument.load)
        docData = try children.docData.map(HwpDocData.load)
        distributeDocData = try children.distributeDocData.map(HwpDistributeDocData.load)

        if let layoutCompatibility = children.layoutCompatibility {
            self.layoutCompatibility = try HwpLayoutCompatibility.load(layoutCompatibility)
        } else {
            // compatibleDocument를 먼저 확정해야 하는 폴백 — 분류 순서와 무관하게
            // 로드 순서가 이 의존을 지킨다.
            layoutCompatibility = compatibleDocument?.layoutCompatibility
        }

        let topLevelTrackChanges = try children.trackChanges.map(HwpTrackChange.load)
        topLevelTrackChangeArray = topLevelTrackChanges
        trackChangeArray = self.idMappings.trackChangeArray + topLevelTrackChanges

        memoShapeArray = try self.idMappings.memoShapeArray
            + children.memoShapes.map(HwpMemoShape.load)
        trackChangeContentArray = try self.idMappings.trackChangeContentArray
            + children.trackChangeContents.map(HwpTrackChangeContent.load)
        trackChangeAuthorArray = try self.idMappings.trackChangeAuthorArray
            + children.trackChangeAuthors.map(HwpTrackChangeAuthor.load)

        let topLevelForbiddenChars = try children.forbiddenChars.map(HwpForbiddenChar.load)
        topLevelForbiddenCharArray = topLevelForbiddenChars
        forbiddenCharArray = self.idMappings.forbiddenCharArray
            + (docData?.forbiddenCharArray ?? [])
            + topLevelForbiddenChars

        unknownRecords = children.unconsumed.map(HwpUnknownRecord.init)
        rawPayload = try reader.consumedData(from: startOffset)
    }
}

private extension HwpDocInfo {
    /// children 단일 패스 분류 결과. singleton 태그는 첫 레코드만 소비하고
    /// 중복은 `unconsumed`로, multi-record 태그는 등장 순서대로 전부 모은다.
    /// `unconsumed`는 원래 children 순서를 보존한다 (중복 singleton + 미지 태그).
    struct ClassifiedChildren {
        var documentProperties: HwpRecord?
        var idMappings: HwpRecord?
        var compatibleDocument: HwpRecord?
        var docData: HwpRecord?
        var distributeDocData: HwpRecord?
        var layoutCompatibility: HwpRecord?
        var trackChanges: [HwpRecord] = []
        var memoShapes: [HwpRecord] = []
        var trackChangeContents: [HwpRecord] = []
        var trackChangeAuthors: [HwpRecord] = []
        var forbiddenChars: [HwpRecord] = []
        var unconsumed: [HwpRecord] = []

        mutating func consumeSingleton(
            _ record: HwpRecord,
            into slot: WritableKeyPath<Self, HwpRecord?>
        ) {
            if self[keyPath: slot] == nil {
                self[keyPath: slot] = record
            } else {
                unconsumed.append(record)
            }
        }
    }

    static let singletonSlots: [UInt32: WritableKeyPath<ClassifiedChildren, HwpRecord?>] = [
        HwpDocInfoTag.documentProperties.rawValue: \.documentProperties,
        HwpDocInfoTag.idMappings.rawValue: \.idMappings,
        HwpDocInfoTag.compatibleDocument.rawValue: \.compatibleDocument,
        HwpDocInfoTag.docData.rawValue: \.docData,
        HwpDocInfoTag.distributeDocData.rawValue: \.distributeDocData,
        HwpDocInfoTag.layoutCompatibility.rawValue: \.layoutCompatibility,
    ]

    static let multiSlots: [UInt32: WritableKeyPath<ClassifiedChildren, [HwpRecord]>] = [
        HwpDocInfoTag.trackChange.rawValue: \.trackChanges,
        HwpDocInfoTag.memoShape.rawValue: \.memoShapes,
        HwpDocInfoTag.trackChangeContent.rawValue: \.trackChangeContents,
        HwpDocInfoTag.trackChangeAuthor.rawValue: \.trackChangeAuthors,
        HwpDocInfoTag.forbiddenChar.rawValue: \.forbiddenChars,
    ]

    static func classify(_ children: [HwpRecord]) -> ClassifiedChildren {
        var result = ClassifiedChildren()
        for child in children {
            if let slot = singletonSlots[child.tagId] {
                result.consumeSingleton(child, into: slot)
            } else if let slot = multiSlots[child.tagId] {
                result[keyPath: slot].append(child)
            } else {
                result.unconsumed.append(child)
            }
        }
        return result
    }
}
