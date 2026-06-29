public enum HwpCtrlId {
    // common
    case table(HwpTable)
    case shape(HwpShapeControl)
    case line(HwpShapeControl)
    case rectangle(HwpShapeControl)
    case ellipse(HwpShapeControl)
    case arc(HwpShapeControl)
    case polygon(HwpShapeControl)
    case curve(HwpShapeControl)
    case equation(HwpShapeControl)
    case equationLegacy(HwpShapeControl)
    case picture(HwpShapeControl)
    case ole(HwpShapeControl)
    case container(HwpShapeControl)
    case genShapeObject(HwpGenShapeObject)
    // other
    case section(HwpSectionDef)
    case column(HwpColumn)
    case pageNumberPosition(HwpPageNumberPosition)
    case header(HwpListControl)
    case footer(HwpListControl)
    case footnote(HwpListControl)
    case endnote(HwpListControl)
    case form(HwpOtherControl)
    case autoNumber(HwpOtherControl)
    case newNumber(HwpOtherControl)
    case pageHide(HwpOtherControl)
    case pageCT(HwpOtherControl)
    case indexmark(HwpOtherControl)
    case bookmark(HwpOtherControl)
    case overlapping(HwpOtherControl)
    case comment(HwpOtherControl)
    case hiddenComment(HwpOtherControl)
    case other(HwpOtherControl)
    /// field
    case hyperLink(HwpHyperlink)
    case memo(HwpFieldControl)
    case revision(HwpFieldControl)
    case field(HwpFieldControl)
    /// not implemented
    case notImplemented(HwpCtrlHeader)
    case unknown(HwpCtrlHeader)
}

extension HwpCtrlId: HwpPrimitive {
    enum CodingKeys: CodingKey {
        case table, shape
        case line, rectangle, ellipse, arc, polygon, curve
        case equation, equationLegacy, picture, ole, container, genShapeObject
        case section, column, pageNumberPosition
        case header, footer, footnote, endnote
        case form
        case autoNumber, newNumber, pageHide, pageCT, indexmark, bookmark
        case overlapping, comment, hiddenComment, other
        case hyperLink, memo, revision, field
        case notImplemented, unknown
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected exactly one HwpCtrlId case, got \(keys.count)."
                )
            )
        }

        switch key {
        case .table:
            let hwpTable = try container.decode(HwpTable.self, forKey: .table)
            self = .table(hwpTable)
        case .shape:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .shape)
            self = .shape(hwp)
        case .line:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .line)
            self = .line(hwp)
        case .rectangle:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .rectangle)
            self = .rectangle(hwp)
        case .ellipse:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .ellipse)
            self = .ellipse(hwp)
        case .arc:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .arc)
            self = .arc(hwp)
        case .polygon:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .polygon)
            self = .polygon(hwp)
        case .curve:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .curve)
            self = .curve(hwp)
        case .equation:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .equation)
            self = .equation(hwp)
        case .equationLegacy:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .equationLegacy)
            self = .equationLegacy(hwp)
        case .picture:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .picture)
            self = .picture(hwp)
        case .ole:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .ole)
            self = .ole(hwp)
        case .container:
            let hwp = try container.decode(HwpShapeControl.self, forKey: .container)
            self = .container(hwp)
        case .genShapeObject:
            let hwpGenShapeObject = try container.decode(
                HwpGenShapeObject.self, forKey: .genShapeObject
            )
            self = .genShapeObject(hwpGenShapeObject)
        case .section:
            let hwpCtrlSection = try container.decode(HwpSectionDef.self, forKey: .section)
            self = .section(hwpCtrlSection)
        case .column:
            let hwpColumn = try container.decode(HwpColumn.self, forKey: .column)
            self = .column(hwpColumn)
        case .pageNumberPosition:
            let hwp = try container.decode(HwpPageNumberPosition.self, forKey: .pageNumberPosition)
            self = .pageNumberPosition(hwp)
        case .header:
            let hwp = try container.decode(HwpListControl.self, forKey: .header)
            self = .header(hwp)
        case .footer:
            let hwp = try container.decode(HwpListControl.self, forKey: .footer)
            self = .footer(hwp)
        case .footnote:
            let hwp = try container.decode(HwpListControl.self, forKey: .footnote)
            self = .footnote(hwp)
        case .endnote:
            let hwp = try container.decode(HwpListControl.self, forKey: .endnote)
            self = .endnote(hwp)
        case .form:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .form)
            self = .form(hwp)
        case .autoNumber:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .autoNumber)
            self = .autoNumber(hwp)
        case .newNumber:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .newNumber)
            self = .newNumber(hwp)
        case .pageHide:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .pageHide)
            self = .pageHide(hwp)
        case .pageCT:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .pageCT)
            self = .pageCT(hwp)
        case .indexmark:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .indexmark)
            self = .indexmark(hwp)
        case .bookmark:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .bookmark)
            self = .bookmark(hwp)
        case .overlapping:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .overlapping)
            self = .overlapping(hwp)
        case .comment:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .comment)
            self = .comment(hwp)
        case .hiddenComment:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .hiddenComment)
            self = .hiddenComment(hwp)
        case .other:
            let hwp = try container.decode(HwpOtherControl.self, forKey: .other)
            self = .other(hwp)
        case .hyperLink:
            let hwpHyperlink = try container.decode(HwpHyperlink.self, forKey: .hyperLink)
            self = .hyperLink(hwpHyperlink)
        case .memo:
            let hwp = try container.decode(HwpFieldControl.self, forKey: .memo)
            self = .memo(hwp)
        case .revision:
            let hwp = try container.decode(HwpFieldControl.self, forKey: .revision)
            self = .revision(hwp)
        case .field:
            let hwp = try container.decode(HwpFieldControl.self, forKey: .field)
            self = .field(hwp)
        case .notImplemented:
            let hwpCtrlHeader = try container.decode(HwpCtrlHeader.self, forKey: .notImplemented)
            self = .notImplemented(hwpCtrlHeader)
        case .unknown:
            let hwpCtrlHeader = try container.decode(HwpCtrlHeader.self, forKey: .unknown)
            self = .unknown(hwpCtrlHeader)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .table(hwpTable):
            try container.encode(hwpTable, forKey: .table)
        case let .shape(hwp):
            try container.encode(hwp, forKey: .shape)
        case let .line(hwp):
            try container.encode(hwp, forKey: .line)
        case let .rectangle(hwp):
            try container.encode(hwp, forKey: .rectangle)
        case let .ellipse(hwp):
            try container.encode(hwp, forKey: .ellipse)
        case let .arc(hwp):
            try container.encode(hwp, forKey: .arc)
        case let .polygon(hwp):
            try container.encode(hwp, forKey: .polygon)
        case let .curve(hwp):
            try container.encode(hwp, forKey: .curve)
        case let .equation(hwp):
            try container.encode(hwp, forKey: .equation)
        case let .equationLegacy(hwp):
            try container.encode(hwp, forKey: .equationLegacy)
        case let .picture(hwp):
            try container.encode(hwp, forKey: .picture)
        case let .ole(hwp):
            try container.encode(hwp, forKey: .ole)
        case let .container(hwp):
            try container.encode(hwp, forKey: .container)
        case let .genShapeObject(hwpGenShapeObject):
            try container.encode(hwpGenShapeObject, forKey: .genShapeObject)
        case let .section(hwpCtrlSection):
            try container.encode(hwpCtrlSection, forKey: .section)
        case let .column(hwpColumn):
            try container.encode(hwpColumn, forKey: .column)
        case let .pageNumberPosition(hwp):
            try container.encode(hwp, forKey: .pageNumberPosition)
        case let .header(hwp):
            try container.encode(hwp, forKey: .header)
        case let .footer(hwp):
            try container.encode(hwp, forKey: .footer)
        case let .footnote(hwp):
            try container.encode(hwp, forKey: .footnote)
        case let .endnote(hwp):
            try container.encode(hwp, forKey: .endnote)
        case let .form(hwp):
            try container.encode(hwp, forKey: .form)
        case let .autoNumber(hwp):
            try container.encode(hwp, forKey: .autoNumber)
        case let .newNumber(hwp):
            try container.encode(hwp, forKey: .newNumber)
        case let .pageHide(hwp):
            try container.encode(hwp, forKey: .pageHide)
        case let .pageCT(hwp):
            try container.encode(hwp, forKey: .pageCT)
        case let .indexmark(hwp):
            try container.encode(hwp, forKey: .indexmark)
        case let .bookmark(hwp):
            try container.encode(hwp, forKey: .bookmark)
        case let .overlapping(hwp):
            try container.encode(hwp, forKey: .overlapping)
        case let .comment(hwp):
            try container.encode(hwp, forKey: .comment)
        case let .hiddenComment(hwp):
            try container.encode(hwp, forKey: .hiddenComment)
        case let .other(hwp):
            try container.encode(hwp, forKey: .other)
        case let .hyperLink(hwpHyperlink):
            try container.encode(hwpHyperlink, forKey: .hyperLink)
        case let .memo(hwp):
            try container.encode(hwp, forKey: .memo)
        case let .revision(hwp):
            try container.encode(hwp, forKey: .revision)
        case let .field(hwp):
            try container.encode(hwp, forKey: .field)
        case let .notImplemented(hwpCtrlHeader):
            try container.encode(hwpCtrlHeader, forKey: .notImplemented)
        case let .unknown(hwpCtrlHeader):
            try container.encode(hwpCtrlHeader, forKey: .unknown)
        }
    }
}
