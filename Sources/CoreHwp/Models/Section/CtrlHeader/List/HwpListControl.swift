import Foundation

/** 리스트 본문을 가지는 컨트롤 */
public struct HwpListControl: HwpPrimitive {
    /** 컨트롤 헤더 */
    public var header: HwpCtrlHeader
    /** 리스트와 그 안의 문단 */
    public var listArray: [HwpListControlList]
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    public init() {
        header = HwpCtrlHeader(ctrlId: HwpOtherCtrlId.header.rawValue, rawPayload: Data())
        listArray = []
        unknownChildren = []
    }

    public init(
        header: HwpCtrlHeader,
        listArray: [HwpListControlList],
        unknownChildren: [HwpUnknownRecord]
    ) {
        self.header = header
        self.listArray = listArray
        self.unknownChildren = unknownChildren
    }

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        let header = try HwpCtrlHeader.load(record)
        let parsedChildren = try parseChildren(record.children, version)
        return HwpListControl(
            header: header,
            listArray: parsedChildren.lists,
            unknownChildren: parsedChildren.unknownChildren
        )
    }
}

/** 리스트 컨트롤의 리스트 항목 */
public struct HwpListControlList: HwpPrimitive {
    /** 리스트 헤더 */
    public var header: HwpListHeader
    /** 리스트 헤더 원본 payload */
    public var headerRawPayload: Data
    /** 리스트 헤더의 아직 해석하지 않은 child record */
    public var headerUnknownChildren: [HwpUnknownRecord]
    /** 리스트 안의 문단 */
    public var paragraphArray: [HwpParagraph]
}

private extension HwpListControl {
    static func parseChildren(
        _ children: [HwpRecord],
        _ version: HwpVersion
    ) throws -> (lists: [HwpListControlList], unknownChildren: [HwpUnknownRecord]) {
        var lists = [HwpListControlList]()
        var unknownChildren = [HwpUnknownRecord]()
        var index = 0

        while index < children.count {
            let child = children[index]
            guard child.tagId == HwpSectionTag.listHeader.rawValue else {
                unknownChildren.append(HwpUnknownRecord(child))
                index += 1
                continue
            }

            let header = try HwpListHeader.load(child.payload)
            guard header.paragraphCount >= 0 else {
                throw HwpError.invalidRecordTree(
                    reason: "list control paragraph count is negative: \(header.paragraphCount)"
                )
            }

            var paragraphs = [HwpParagraph]()
            for _ in 0 ..< Int(header.paragraphCount) {
                index += 1
                guard index < children.count else {
                    throw HwpError.invalidRecordTree(reason: "list control paragraph is missing")
                }
                let paragraphRecord = children[index]
                guard paragraphRecord.tagId == HwpSectionTag.paraHeader.rawValue else {
                    throw HwpError.invalidRecordTree(
                        reason: "list control expected paragraph, got tag \(paragraphRecord.tagId)"
                    )
                }
                paragraphs.append(try HwpParagraph.load(paragraphRecord, version))
            }

            lists.append(HwpListControlList(
                header: header,
                headerRawPayload: child.payload,
                headerUnknownChildren: child.children.map(HwpUnknownRecord.init),
                paragraphArray: paragraphs
            ))
            index += 1
        }

        guard !lists.isEmpty else {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue)
        }

        return (lists, unknownChildren)
    }
}
