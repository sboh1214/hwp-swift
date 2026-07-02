import Foundation

public struct HwpParagraph: HwpFromRecordWithVersion {
    public let paraHeader: HwpParaHeader

    public var paraText: HwpParaText?
    public var paraCharShape: HwpParaCharShape
    public var paraLineSeg: HwpParaLineSeg
    public var ctrlHeaderArray: [HwpCtrlId]?
    public var paraRangeTagArray: [HwpParaRangeTag]?
    public var listHeaderArray: [HwpListHeader]?
    @ExcludeEquatable
    public var unknownChildren: [HwpUnknownRecord]

    public init() {
        paraHeader = HwpParaHeader()
        paraText = HwpParaText()
        paraCharShape = HwpParaCharShape()
        paraLineSeg = HwpParaLineSeg()
        paraRangeTagArray = [HwpParaRangeTag]()
        listHeaderArray = [HwpListHeader]()
        unknownChildren = []
        ctrlHeaderArray = [
            .section(HwpSectionDef()),
            .column(HwpColumn()),
        ]
    }

    // MARK: loader contract exemption - validates paragraph record tag before decoding children

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .paraHeader)

        var reader = DataReader(record.payload)
        let paragraph = try self.init(&reader, record.children, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return paragraph
    }

    // MARK: loader contract exemption - paragraph header payload is forwarded to versioned loader

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws {
        paraHeader = try HwpParaHeader.load(try reader.readToEnd(), version)

        if let paraText = children
            .first(where: { $0.tagId == HwpSectionTag.paraText.rawValue })
        {
            let loadedParaText = try HwpParaText.load(paraText.payload)
            self.paraText = loadedParaText
            try Self.validateParaTextCount(paraHeader, loadedParaText)
        }

        guard let paraCharShape = children
            .first(where: { $0.tagId == HwpSectionTag.paraCharShape.rawValue })
        else {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.paraCharShape.rawValue)
        }
        self.paraCharShape = try HwpParaCharShape.load(paraCharShape.payload)
        try Self.validateParaCharShapeCount(paraHeader, self.paraCharShape)

        if let paraLineSeg = children
            .first(where: { $0.tagId == HwpSectionTag.paraLineSeg.rawValue })
        {
            self.paraLineSeg = try HwpParaLineSeg.load(paraLineSeg.payload)
            if !paraLineSeg.payload.isEmpty {
                try Self.validateParaLineSegCount(paraHeader, self.paraLineSeg)
            }
        } else {
            // Some Hancom-saved compatibility documents omit this layout cache.
            paraLineSeg = try HwpParaLineSeg.load(Data())
        }

        paraRangeTagArray = try children
            .filter { $0.tagId == HwpSectionTag.paraRangeTag.rawValue }
            .map { try HwpParaRangeTag.load($0.payload) }
        try Self.validateParaRangeTagCount(paraHeader, paraRangeTagArray ?? [])

        ctrlHeaderArray = try children
            .filter { $0.tagId == HwpSectionTag.ctrlHeader.rawValue }
            .map {
                let header = try HwpCtrlHeader.load($0)
                let ctrlId = header.ctrlId
                if let common = HwpCommonCtrlId(rawValue: ctrlId) {
                    if common == .table {
                        return try Self.tableOrNotImplemented($0, version)
                    } else if common == .genShapeObject {
                        return try Self.genShapeObjectOrNotImplemented($0, version)
                    }
                    return try Self.commonShapeControl($0, common, version)
                } else if let other = HwpOtherCtrlId(rawValue: ctrlId) {
                    if other == .column {
                        return try Self.columnOrOther($0)
                    } else if other == .section {
                        return try Self.sectionDefOrOther($0, version)
                    } else if other == .pageNumberPosition {
                        return try Self.pageNumberPositionOrOther($0)
                    } else if other == .header {
                        return try Self.listControlOrOther($0, .header, version)
                    } else if other == .footer {
                        return try Self.listControlOrOther($0, .footer, version)
                    } else if other == .footnote {
                        return try Self.listControlOrOther($0, .footnote, version)
                    } else if other == .endnote {
                        return try Self.listControlOrOther($0, .endnote, version)
                    }
                    return try Self.otherControl($0, other)
                } else if let field = HwpFieldCtrlId(rawValue: ctrlId) {
                    if field == .hyperLink {
                        return try Self.hyperLinkOrField($0)
                    }
                    let control = try HwpFieldControl.load($0)
                    if control.isMemoField {
                        return .memo(control)
                    }
                    if control.isRevisionField {
                        return .revision(control)
                    }
                    return .field(control)
                } else {
                    return .unknown(header)
                }
            }

        listHeaderArray = try children
            .filter { $0.tagId == HwpSectionTag.listHeader.rawValue }
            .map { try HwpListHeader.load($0.payload) }

        unknownChildren = Self.unconsumedRecords(from: children).map(HwpUnknownRecord.init)
    }
}

private extension HwpParagraph {
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
            HwpSectionTag.paraText.rawValue,
            HwpSectionTag.paraCharShape.rawValue,
            HwpSectionTag.paraLineSeg.rawValue,
        ]
    }

    static var multiRecordTags: Set<UInt32> {
        [
            HwpSectionTag.paraRangeTag.rawValue,
            HwpSectionTag.ctrlHeader.rawValue,
            HwpSectionTag.listHeader.rawValue,
        ]
    }

    static func validateParaTextCount(
        _ header: HwpParaHeader,
        _ text: HwpParaText
    ) throws {
        let expectedCount = Int(header.charCount)
        let actualCount = text.rawPayload.count / MemoryLayout<WCHAR>.size
        guard expectedCount == actualCount else {
            throw HwpError.invalidRecordTree(
                reason:
                """
                paragraph text count mismatch: header declares \(expectedCount), \
                PARA_TEXT contains \(actualCount)
                """
            )
        }
    }

    static func validateParaCharShapeCount(
        _ header: HwpParaHeader,
        _ charShape: HwpParaCharShape
    ) throws {
        let expectedCount = Int(header.charShapeInfoCount)
        let actualCount = charShape.startingIndex.count
        guard expectedCount == actualCount else {
            throw HwpError.invalidRecordTree(
                reason:
                """
                paragraph char shape count mismatch: header declares \(expectedCount), \
                PARA_CHAR_SHAPE contains \(actualCount)
                """
            )
        }
    }

    static func validateParaLineSegCount(
        _ header: HwpParaHeader,
        _ lineSeg: HwpParaLineSeg
    ) throws {
        let expectedCount = Int(header.alignInfoCount)
        let actualCount = lineSeg.paraLineSegInternalArray.count
        guard expectedCount == actualCount else {
            throw HwpError.invalidRecordTree(
                reason:
                """
                paragraph line segment count mismatch: header declares \(expectedCount), \
                PARA_LINE_SEG contains \(actualCount)
                """
            )
        }
    }

    static func validateParaRangeTagCount(
        _ header: HwpParaHeader,
        _ rangeTags: [HwpParaRangeTag]
    ) throws {
        let expectedCount = Int(header.rangeTagInfoCount)
        let actualCount = rangeTags.count
        guard expectedCount == actualCount else {
            throw HwpError.invalidRecordTree(
                reason:
                """
                paragraph range tag count mismatch: header declares \(expectedCount), \
                PARA_RANGE_TAG contains \(actualCount)
                """
            )
        }
    }

    static func genShapeObjectOrNotImplemented(
        _ record: HwpRecord,
        _ version: HwpVersion
    ) throws -> HwpCtrlId {
        do {
            return try .genShapeObject(HwpGenShapeObject.load(record, version))
        } catch let error as HwpError {
            guard error.canFallbackToRawGenShapeObject else {
                throw error
            }
            return try .notImplemented(HwpCtrlHeader.load(record))
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func commonShapeControl(
        _ record: HwpRecord,
        _ ctrlId: HwpCommonCtrlId,
        _ version: HwpVersion
    ) throws -> HwpCtrlId {
        let control: HwpShapeControl
        do {
            control = try HwpShapeControl.load(record, version)
        } catch let error as HwpError {
            guard error.canFallbackToRawGenShapeObject else {
                throw error
            }
            return try .notImplemented(HwpCtrlHeader.load(record))
        }

        switch ctrlId {
        case .line:
            return .line(control)
        case .rectangle:
            return .rectangle(control)
        case .ellipse:
            return .ellipse(control)
        case .arc:
            return .arc(control)
        case .polygon:
            return .polygon(control)
        case .curve:
            return .curve(control)
        case .equation:
            return .equation(control)
        case .equationLegacy:
            return .equationLegacy(control)
        case .picture:
            return .picture(control)
        case .ole:
            return .ole(control)
        case .container:
            return .container(control)
        case .table, .genShapeObject:
            throw HwpError.invalidRecordTree(
                reason: "common shape control \(ctrlId) was dispatched through common shape parser"
            )
        }
    }

    static func tableOrNotImplemented(
        _ record: HwpRecord,
        _ version: HwpVersion
    ) throws -> HwpCtrlId {
        do {
            return try .table(HwpTable.load(record, version))
        } catch let error as HwpError {
            guard error.canFallbackToRawControl else {
                throw error
            }
            return try .notImplemented(HwpCtrlHeader.load(record))
        }
    }

    static func hyperLinkOrField(_ record: HwpRecord) throws -> HwpCtrlId {
        do {
            return try .hyperLink(HwpHyperlink.load(record))
        } catch let error as HwpError {
            guard error.canFallbackToRawControl else {
                throw error
            }
            return try .field(HwpFieldControl.load(record))
        }
    }

    static func pageNumberPositionOrOther(_ record: HwpRecord) throws -> HwpCtrlId {
        do {
            return try .pageNumberPosition(HwpPageNumberPosition.load(record))
        } catch let error as HwpError {
            guard error.canFallbackToRawControl else {
                throw error
            }
            return try .other(HwpOtherControl.load(record))
        }
    }

    static func columnOrOther(_ record: HwpRecord) throws -> HwpCtrlId {
        do {
            return try .column(HwpColumn.load(record))
        } catch let error as HwpError {
            guard error.canFallbackToRawControl else {
                throw error
            }
            return try .other(HwpOtherControl.load(record))
        }
    }

    static func sectionDefOrOther(_ record: HwpRecord, _ version: HwpVersion) throws -> HwpCtrlId {
        do {
            return try .section(HwpSectionDef.load(record, version))
        } catch let error as HwpError {
            guard error.canFallbackToRawControl else {
                throw error
            }
            return try .other(HwpOtherControl.load(record))
        }
    }

    static func listControlOrOther(
        _ record: HwpRecord,
        _ ctrlId: HwpOtherCtrlId,
        _ version: HwpVersion
    ) throws -> HwpCtrlId {
        do {
            let control = try HwpListControl.load(record, version)
            switch ctrlId {
            case .header:
                return .header(control)
            case .footer:
                return .footer(control)
            case .footnote:
                return .footnote(control)
            case .endnote:
                return .endnote(control)
            default:
                return .other(try HwpOtherControl.load(record))
            }
        } catch let error as HwpError {
            guard error.canFallbackToRawListControl else {
                throw error
            }
            return try .other(HwpOtherControl.load(record))
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func otherControl(_ record: HwpRecord, _ ctrlId: HwpOtherCtrlId) throws -> HwpCtrlId {
        let control = try HwpOtherControl.load(record)
        switch ctrlId {
        case .form:
            return .form(control)
        case .autoNumber:
            return .autoNumber(control)
        case .newNumber:
            return .newNumber(control)
        case .pageHide:
            return .pageHide(control)
        case .pageCT:
            return .pageCT(control)
        case .indexmark:
            return .indexmark(control)
        case .bookmark:
            return .bookmark(control)
        case .overlapping:
            return .overlapping(control)
        case .comment:
            return .comment(control)
        case .hiddenComment:
            return .hiddenComment(control)
        default:
            return .other(control)
        }
    }
}

private extension HwpError {
    var canFallbackToRawControl: Bool {
        switch self {
        case .truncatedData, .invalidUnicodeScalar, .invalidRawValueForEnum:
            true
        default:
            false
        }
    }

    var canFallbackToRawListControl: Bool {
        switch self {
        case .recordDoesNotExist, .invalidRecordTree:
            true
        default:
            canFallbackToRawControl
        }
    }

    var canFallbackToRawGenShapeObject: Bool {
        switch self {
        case .invalidRecordTree:
            true
        default:
            canFallbackToRawControl
        }
    }
}
