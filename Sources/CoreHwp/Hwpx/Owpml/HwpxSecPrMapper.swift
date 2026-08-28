import Foundation

/// `hp:secPr`·`hp:colPr`를 `HwpSectionDef`·`HwpColumn`으로 옮긴다.
///
/// 두 컨트롤 모두 HWP5에서 구역 첫 문단의 extended 2 문자에 붙는다 —
/// HWPX도 같은 배치다 (첫 문단 첫 run 안, 실물 검증). paginator는
/// `sectionDef(in:)` 하나로만 구역 경계를 인식하므로 이 매핑이 구역
/// 지오메트리의 전부다.
enum HwpxSecPrMapper {
    static func mapSectionDef(_ secPr: HwpxXMLNode) -> HwpSectionDef {
        var sectionDef = HwpSectionDef()

        if let pagePr = secPr.firstChild(named: "pagePr") {
            var pageDef = HwpPageDef()
            pageDef.width = pagePr.uint32Attribute("width", default: pageDef.width)
            pageDef.height = pagePr.uint32Attribute("height", default: pageDef.height)
            // landscape 속성은 방향 표식일 뿐 조판은 width/height를 그대로
            // 쓴다 (실측: 세로 A4가 landscape="WIDELY"로 저장됨 — 값 의미는
            // 실파일 검증 항목이라 property로 옮기지 않는다).
            if let margin = pagePr.firstChild(named: "margin") {
                pageDef.marginLeft = margin.uint32Attribute("left", default: pageDef.marginLeft)
                pageDef.marginRight = margin.uint32Attribute(
                    "right", default: pageDef.marginRight
                )
                pageDef.marginTop = margin.uint32Attribute("top", default: pageDef.marginTop)
                pageDef.marginBottom = margin.uint32Attribute(
                    "bottom", default: pageDef.marginBottom
                )
                pageDef.marginHeader = margin.uint32Attribute(
                    "header", default: pageDef.marginHeader
                )
                pageDef.marginFootnote = margin.uint32Attribute(
                    "footer", default: pageDef.marginFootnote
                )
                pageDef.marginGutter = margin.uint32Attribute(
                    "gutter", default: pageDef.marginGutter
                )
            }
            sectionDef.pageDef = pageDef
        }

        sectionDef.columnSpacing = Int16(clamping: secPr.intAttribute(
            "spaceColumns", default: Int(sectionDef.columnSpacing)
        ))
        sectionDef.defaultTabSpacing = secPr.uint32Attribute(
            "tabStop", default: sectionDef.defaultTabSpacing
        )
        if let startNum = secPr.firstChild(named: "startNum") {
            sectionDef.pageStartNumber = startNum.uint16Attribute("page", default: 0)
            sectionDef.pictureStartNumber = startNum.uint16Attribute("pic", default: 0)
            sectionDef.tableStartNumber = startNum.uint16Attribute("tbl", default: 0)
            sectionDef.equationNumber = startNum.uint16Attribute("equation", default: 0)
        }
        // 각주/미주 모양·쪽 테두리는 1차 범위 밖 — 빈 문서 기본값을 유지한다
        // (해당 fixture는 변환 대상에서 제외됨).
        return sectionDef
    }

    static func mapColumn(_ colPr: HwpxXMLNode) -> HwpColumn {
        var column = HwpColumn()
        var property = HwpColumnProperty()
        property.type = Self.columnTypes[colPr.attribute("type") ?? "NEWSPAPER"] ?? .general
        property.count = max(1, colPr.intAttribute("colCount", default: 1))
        property.direction = Self.columnDirections[colPr.attribute("layout") ?? "LEFT"]
            ?? .left
        property.isSameWidth = colPr.boolAttribute("sameSz", default: true)
        column.property = property
        // sameGap은 동일 폭 다단의 단 간격이다 (HWPUNIT).
        column.spacing = Int16(clamping: colPr.intAttribute("sameGap", default: 0))

        // 폭이 다른 다단: hp:colSz(width·gap)가 단 수만큼 나열된다.
        let sizes = colPr.children(named: "colSz")
        if !property.isSameWidth, !sizes.isEmpty {
            column.widthArray = sizes.map { $0.uint16Attribute("width", default: 0) }
            column.gapArray = sizes.map { $0.uint16Attribute("gap", default: 0) }
            column.spacing = nil
        }

        if let line = colPr.firstChild(named: "colLine") {
            column.dividerType = UInt8(clamping: HwpxCharShapeMapper.lineShapeIndex(
                line.attribute("type"), default: 0
            ))
            column.dividerThickness = HwpxParaShapeMapper.thicknessIndex(
                of: line.attribute("width")
            )
            column.dividerColor = line.colorAttribute("color") ?? HwpColor()
        }
        return column
    }
}

private extension HwpxSecPrMapper {
    static let columnTypes: [String: HwpColumnType] = [
        "NEWSPAPER": .general, "BALANCED_NEWSPAPER": .div, "PARALLEL": .along,
    ]

    static let columnDirections: [String: HwpColumnDirection] = [
        "LEFT": .left, "RIGHT": .right, "MIRROR": .yang,
    ]
}
