public enum HwpCtrlId {
    // common
    case table(HwpTable)
    case genShapeObject(HwpGenShapeObject)
    // other
    case section(HwpSectionDef)
    case column(HwpColumn)
    case pageNumberPosition(HwpPageNumberPosition)
    /// field
    /// not implemented
    case notImplemented(HwpCtrlHeader)
}

extension HwpCtrlId: HwpPrimitive {
    enum CodingKeys: CodingKey {
        case table, genShapeObject
        case section, column, pageNumberPosition
        case notImplemented
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = container.allKeys.first

        switch key {
        case .table:
            let hwpTable = try container.decode(HwpTable.self, forKey: .table)
            self = .table(hwpTable)
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
        case .notImplemented:
            let hwpCtrlHeader = try container.decode(HwpCtrlHeader.self, forKey: .notImplemented)
            self = .notImplemented(hwpCtrlHeader)
        case .none:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unabled to decode enum."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .table(hwpTable):
            try container.encode(hwpTable, forKey: .table)
        case let .genShapeObject(hwpGenShapeObject):
            try container.encode(hwpGenShapeObject, forKey: .genShapeObject)
        case let .section(hwpCtrlSection):
            try container.encode(hwpCtrlSection, forKey: .section)
        case let .column(hwpColumn):
            try container.encode(hwpColumn, forKey: .column)
        case let .pageNumberPosition(hwp):
            try container.encode(hwp, forKey: .pageNumberPosition)
        case let .notImplemented(hwpCtrlHeader):
            try container.encode(hwpCtrlHeader, forKey: .notImplemented)
        }
    }
}
