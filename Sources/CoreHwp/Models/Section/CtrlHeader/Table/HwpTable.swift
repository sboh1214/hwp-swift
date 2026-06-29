import Foundation

public struct HwpTable {
    public var commonCtrlProperty: HwpCommonCtrlProperty
    public var tableProperty: HwpTableProperty
    public var rawPayload: Data
    public var rawTrailing: Data
    public var cellArray: [HwpTableCell]
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpTable: HwpFromRecordWithVersion {
    // MARK: loader contract exemption - preserves table control trailing payload

    init(_ reader: inout DataReader, _ children: [HwpRecord], _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        commonCtrlProperty = try HwpCommonCtrlProperty(&reader)
        guard commonCtrlProperty.commonCtrlId == .table else {
            throw HwpError.invalidCtrlId(ctrlId: commonCtrlProperty.commonCtrlId.rawValue)
        }
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        guard let tablePropertyIndex = children.firstIndex(where: {
            $0.tagId == HwpSectionTag.table.rawValue
        }) else {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.table.rawValue)
        }
        tableProperty = try HwpTableProperty.load(children[tablePropertyIndex].payload, version)

        let parsedChildren = try Self.parseChildren(
            children,
            excluding: tablePropertyIndex,
            version: version
        )
        if tableProperty.rowCount > 0, tableProperty.columnCount > 0, parsedChildren.cells.isEmpty {
            throw HwpError.recordDoesNotExist(tag: HwpSectionTag.listHeader.rawValue)
        }
        cellArray = parsedChildren.cells
        unknownChildren = parsedChildren.unknownChildren
    }

    // MARK: loader contract exemption - validates table control tag before child parsing

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .ctrlHeader)

        var reader = DataReader(record.payload)
        var table = try self.init(&reader, record.children, version)
        table.rawPayload = record.payload
        return table
    }

    private static func parseChildren(
        _ children: [HwpRecord],
        excluding tablePropertyIndex: Int,
        version: HwpVersion
    ) throws -> (cells: [HwpTableCell], unknownChildren: [HwpUnknownRecord]) {
        var cells = [HwpTableCell]()
        var unknownChildren = [HwpUnknownRecord]()
        var index = 0

        while index < children.count {
            if index == tablePropertyIndex {
                index += 1
                continue
            }

            let child = children[index]
            guard child.tagId == HwpSectionTag.listHeader.rawValue else {
                unknownChildren.append(HwpUnknownRecord(child))
                index += 1
                continue
            }

            let cellHeader = try HwpTableCellHeader.load(child)
            guard cellHeader.paragraphCount >= 0 else {
                throw HwpError.invalidRecordTree(
                    reason: "table cell paragraph count is negative: \(cellHeader.paragraphCount)"
                )
            }

            var paragraphs = [HwpParagraph]()
            for _ in 0 ..< Int(cellHeader.paragraphCount) {
                index += 1
                guard index < children.count else {
                    throw HwpError.invalidRecordTree(reason: "table cell paragraph is missing")
                }
                let paragraphRecord = children[index]
                guard paragraphRecord.tagId == HwpSectionTag.paraHeader.rawValue else {
                    throw HwpError.invalidRecordTree(
                        reason: "table cell expected paragraph, got tag \(paragraphRecord.tagId)"
                    )
                }
                paragraphs.append(try HwpParagraph.load(paragraphRecord, version))
            }
            cells.append(HwpTableCell(header: cellHeader, paragraphArray: paragraphs))
            index += 1
        }

        return (cells, unknownChildren)
    }
}

public struct HwpTableCell {
    public var header: HwpTableCellHeader
    public var paragraphArray: [HwpParagraph]
}

extension HwpTableCell: HwpPrimitive {}

public struct HwpTableCellHeader {
    public var paragraphCount: Int32
    public var property: UInt32
    public var rawTrailing: Data
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpTableCellHeader: HwpFromRecord {
    // MARK: loader contract exemption - preserves table-cell header trailing payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        let startOffset = reader.byteOffset
        paragraphCount = try reader.read(Int32.self)
        property = try reader.read(UInt32.self)
        rawTrailing = try reader.readToEnd()
        rawPayload = try reader.consumedData(from: startOffset)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates LIST_HEADER tag before cell header decode

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .listHeader)

        var reader = DataReader(record.payload)
        var header = try self.init(&reader, record.children)
        header.rawPayload = record.payload
        return header
    }
}
