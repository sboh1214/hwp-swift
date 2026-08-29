import Foundation

/// `hp:tbl`을 `HwpTable`로 옮긴다.
///
/// 셀의 `hp:subList` 문단이 `HwpxParagraphMapper`로 재귀하므로 깊이는
/// `HwpxMappingContext.descending()`이 가드한다 (`maxNestingDepth`).
enum HwpxTableMapper {
    static func map(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpTable {
        let rows = node.children(named: "tr")

        var tableProperty = HwpTableProperty()
        tableProperty.rowCount = node.uint16Attribute(
            "rowCnt", default: UInt16(clamping: rows.count)
        )
        tableProperty.columnCount = node.uint16Attribute("colCnt", default: 0)
        tableProperty.cellSpacing = Int16(
            clamping: node.intAttribute("cellSpacing", default: 0)
        )
        if let inMargin = node.firstChild(named: "inMargin") {
            tableProperty.leftInnerMargin = Int16(
                clamping: inMargin.intAttribute("left", default: 0)
            )
            tableProperty.rightInnerMargin = Int16(
                clamping: inMargin.intAttribute("right", default: 0)
            )
            tableProperty.topInnerMargin = Int16(
                clamping: inMargin.intAttribute("top", default: 0)
            )
            tableProperty.bottomInnerMargin = Int16(
                clamping: inMargin.intAttribute("bottom", default: 0)
            )
        }
        tableProperty.borderFillId = context.idTables.borderFillId(
            of: node.attribute("borderFillIDRef")
        )
        // 표 76: bits 0-1 쪽 경계 나눔 (0 없음/1 셀 단위/2 나눔) + bit 2 제목
        // 줄 반복. HWPX는 이름 붙은 값이다 (한컴 기본값 TABLE = 나눔).
        var propertyBits = UInt32(
            Self.pageBreakModes[node.attribute("pageBreak") ?? "TABLE"] ?? 2
        )
        if node.boolAttribute("repeatHeader") {
            propertyBits |= 1 << 2
        }
        tableProperty.property = propertyBits
        // rowSize는 행별 셀 개수의 LE UInt16 나열이다.
        var rowSize: [BYTE] = []
        for row in rows {
            let count = UInt16(clamping: row.children(named: "tc").count)
            rowSize.append(UInt8(count & 0xFF))
            rowSize.append(UInt8(count >> 8))
        }
        tableProperty.rowSize = rowSize

        var cells: [HwpTableCell] = []
        for row in rows {
            for cell in row.children(named: "tc") {
                cells.append(try Self.mapCell(cell, context: context))
            }
        }

        return HwpTable(
            commonCtrlProperty: HwpxObjectCommonMapper.map(node, ctrlId: .table),
            tableProperty: tableProperty,
            rawPayload: Data(),
            rawTrailing: Data(),
            cellArray: cells,
            unknownChildren: node.unconsumedChildRecords(
                consumed: ["sz", "pos", "outMargin", "inMargin", "tr"]
            )
        )
    }

    static func mapCell(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpTableCell {
        let cellContext = try context.descending()
        let subList = node.firstChild(named: "subList")
        let paragraphNodes = subList?.children(named: "p") ?? []
        var paragraphs: [HwpParagraph] = []
        for (index, paragraphNode) in paragraphNodes.enumerated() {
            paragraphs.append(try HwpxParagraphMapper.map(
                paragraphNode,
                context: cellContext,
                isLastInList: index == paragraphNodes.count - 1
            ))
        }

        let address = node.firstChild(named: "cellAddr")
        let span = node.firstChild(named: "cellSpan")
        let size = node.firstChild(named: "cellSz")
        let margin = node.firstChild(named: "cellMargin")
        let cellProperty = HwpTableCellProperty(
            columnAddress: address?.uint16Attribute("colAddr", default: 0) ?? 0,
            rowAddress: address?.uint16Attribute("rowAddr", default: 0) ?? 0,
            columnSpan: max(1, span?.uint16Attribute("colSpan", default: 1) ?? 1),
            rowSpan: max(1, span?.uint16Attribute("rowSpan", default: 1) ?? 1),
            width: size?.uint32Attribute("width", default: 0) ?? 0,
            height: size?.uint32Attribute("height", default: 0) ?? 0,
            marginArray: ["left", "right", "top", "bottom"].map {
                Int16(clamping: margin?.intAttribute($0, default: 0) ?? 0)
            },
            borderFillId: context.idTables.borderFillId(
                of: node.attribute("borderFillIDRef")
            )
        )

        // 셀 텍스트 세로 정렬 — 렌더는 typed verticalAlignment를 읽는다.
        var listProperty = HwpListHeaderProperty()
        listProperty.verticalAlignment = Self.verticalAlignments[
            subList?.attribute("vertAlign") ?? "TOP"
        ] ?? .top
        listProperty.verticalAlignmentRawValue = listProperty.verticalAlignment?.rawValue ?? 0

        let isHeader = node.boolAttribute("header")
        let widthRef = Self.cellPropertyBits(of: node, isHeader: isHeader)
        let header = HwpTableCellHeader(
            paragraphCount: Int32(paragraphs.count),
            property: 0,
            propertyInfo: listProperty,
            listHeaderWidthRef: widthRef,
            cellPropertyInfo: HwpTableCellHeaderProperty(rawValue: widthRef),
            isHeader: isHeader,
            cellProperty: cellProperty,
            rawTrailing: Data(),
            rawPayload: Data(),
            unknownChildren: node.unconsumedChildRecords(
                consumed: ["subList", "cellAddr", "cellSpan", "cellSz", "cellMargin"]
            )
        )
        return HwpTableCell(header: header, paragraphArray: paragraphs)
    }
}

private extension HwpxTableMapper {
    /// 셀 리스트 헤더 속성 비트 — hasMargin은 bit 0(appliesInnerMargin)으로
    /// 옮겨야 조판이 파싱된 hp:cellMargin 값을 셀 고유 여백으로 쓴다
    /// (비트가 없으면 HwpTableLayout.cellMargins가 표 전체 여백으로 폴백).
    static func cellPropertyBits(of node: HwpxXMLNode, isHeader: Bool) -> UInt16 {
        var bits: UInt16 = isHeader ? 1 << 2 : 0
        if node.boolAttribute("hasMargin") {
            bits |= 1
        }
        return bits
    }

    /// 표 76 bits 0-1 대응 — noori HWP↔HWPX 실측: 바이너리 2(나눔)가
    /// pageBreak="CELL"로 저장된다 ([0,0,2,2,2] ↔ [NONE,NONE,CELL,CELL,CELL]).
    /// TABLE→1은 소거법 추론이다 (코퍼스에 TABLE 사례 0건 — 실물 확보 시 확정).
    static let pageBreakModes: [String: Int] = [
        "NONE": 0, "CELL": 2, "TABLE": 1,
    ]

    static let verticalAlignments: [String: HwpListHeaderVerticalAlignment] = [
        "TOP": .top, "CENTER": .center, "BOTTOM": .bottom,
    ]
}
