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
        // 표 구조(tr·tc·셀 문단)는 정의상 paragraph vocabulary다 — 전역 known
        // 매칭이면 <hh:tr> 같은 동명 요소가 진짜 행이 된다. hc: 자식 혼재가
        // 없는 자리라 좁혀도 교차 vocabulary를 놓치지 않는다.
        let rows = node.paragraphChildren(named: "tr")
        // 행 수·행당 셀 수는 UInt16 필드(rowCount·rowSize)다 — 접으면
        // 배열과 어긋난 모델이 나간다 (문단 메타데이터와 같은 계약, 복구
        // 모드에선 문단 placeholder로 흡수).
        guard rows.count <= Int(UInt16.max),
              rows.allSatisfy({ $0.paragraphChildren(named: "tc").count <= Int(UInt16.max) })
        else {
            throw HwpError.invalidXML(
                entry: context.entry,
                reason: "table rows or per-row cells exceed \(UInt16.max)"
            )
        }

        var tableProperty = HwpTableProperty()
        // 선언 rowCnt는 쓰지 않는다 — rowSize·셀이 파싱된 <hp:tr>에서
        // 만들어지므로, 어긋난 선언을 믿으면 조판이 빈 행을 깔거나 grid
        // 상한 가드로 표를 통째로 거부한다.
        tableProperty.rowCount = UInt16(clamping: rows.count)
        tableProperty.columnCount = node.uint16Attribute("colCnt", default: 0)
        tableProperty.cellSpacing = Int16(
            clamping: node.intAttribute("cellSpacing", default: 0)
        )
        if let inMargin = node.paragraphFirstChild(named: "inMargin") {
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
            let count = UInt16(clamping: row.paragraphChildren(named: "tc").count)
            rowSize.append(UInt8(count & 0xFF))
            rowSize.append(UInt8(count >> 8))
        }
        tableProperty.rowSize = rowSize

        var cells: [HwpTableCell] = []
        var coveredColumns = 0
        for row in rows {
            for cell in row.paragraphChildren(named: "tc") {
                let mapped = try Self.mapCell(cell, context: context)
                if let property = mapped.header.cellProperty {
                    coveredColumns = max(
                        coveredColumns,
                        Int(property.columnAddress) + Int(property.columnSpan)
                    )
                }
                cells.append(mapped)
            }
        }
        // colCnt가 셀 주소+span이 덮는 폭보다 작으면 (colCnt="0" 포함) 조판의
        // grid 가드가 셀을 거부하거나 표를 통째로 지운다 — 파싱 구조가 덮는
        // 폭 밑으로 내려가지 않게 올리고, 더 큰 선언은 그대로 믿는다.
        tableProperty.columnCount = max(
            tableProperty.columnCount, UInt16(clamping: coveredColumns)
        )

        let depthLimit = context.unknownDepthLimit
        var tableUnknowns = node.unconsumedChildRecords(
            consumed: ["sz", "pos", "outMargin", "inMargin", "tr"],
            in: HwpxNamespace.paragraph,
            maxDepth: depthLimit
        )
        for row in rows {
            tableUnknowns += row.unconsumedChildRecords(
                consumed: ["tc"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
            )
        }
        for wrapperName in ["sz", "pos", "outMargin", "inMargin"] {
            if let wrapper = node.paragraphFirstChild(named: wrapperName) {
                tableUnknowns += wrapper.unconsumedChildRecords(
                    consumed: [], maxDepth: depthLimit
                )
            }
        }

        return HwpTable(
            commonCtrlProperty: HwpxObjectCommonMapper.map(node, ctrlId: .table),
            tableProperty: tableProperty,
            rawPayload: Data(),
            rawTrailing: Data(),
            cellArray: cells,
            unknownChildren: tableUnknowns
        )
    }

    static func mapCell(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpTableCell {
        let cellContext = try context.descending()
        let subList = node.paragraphFirstChild(named: "subList")
        let paragraphNodes = subList?.paragraphChildren(named: "p") ?? []
        var paragraphs: [HwpParagraph] = []
        for (index, paragraphNode) in paragraphNodes.enumerated() {
            paragraphs.append(try HwpxParagraphMapper.map(
                paragraphNode,
                context: cellContext,
                isLastInList: index == paragraphNodes.count - 1
            ))
        }

        let address = node.paragraphFirstChild(named: "cellAddr")
        let span = node.paragraphFirstChild(named: "cellSpan")
        let size = node.paragraphFirstChild(named: "cellSz")
        let margin = node.paragraphFirstChild(named: "cellMargin")
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
        let depthLimit = context.unknownDepthLimit
        var cellUnknowns = node.unconsumedChildRecords(
            consumed: ["subList", "cellAddr", "cellSpan", "cellSz", "cellMargin"],
            in: HwpxNamespace.paragraph,
            maxDepth: depthLimit
        )
        // 소비 래퍼 안 미지 자식 — subList는 문단만, 주소·크기 잎 4종은
        // 속성만 읽는다.
        if let subList {
            cellUnknowns += subList.unconsumedChildRecords(
                consumed: ["p"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
            )
        }
        for leaf in [address, span, size, margin] {
            if let leaf {
                cellUnknowns += leaf.unconsumedChildRecords(
                    consumed: [], maxDepth: depthLimit
                )
            }
        }

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
            unknownChildren: cellUnknowns
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
