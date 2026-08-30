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

        if let pagePr = secPr.paragraphFirstChild(named: "pagePr") {
            var pageDef = HwpPageDef()
            pageDef.width = pagePr.uint32Attribute("width", default: pageDef.width)
            pageDef.height = pagePr.uint32Attribute("height", default: pageDef.height)
            // landscape 속성은 방향 표식일 뿐 조판은 width/height를 그대로
            // 쓴다 (실측: 세로 A4가 landscape="WIDELY"로 저장됨 — 값 의미는
            // 실파일 검증 항목이라 property로 옮기지 않는다).
            if let margin = pagePr.paragraphFirstChild(named: "margin") {
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
            // 제본 방향(bits 1-2) — gutterInsets가 이 비트로 gutter를
            // 왼쪽(한쪽·맞쪽)/위쪽(위로)에 배분한다. 양만 옮기면 위 제본
            // 문서가 왼쪽에 제본 여백을 얻는다.
            pageDef.property = Self.gutterTypes[
                pagePr.attribute("gutterType") ?? "LEFT_ONLY"
            ] ?? 0
            sectionDef.pageDef = pageDef
        }

        sectionDef.columnSpacing = Int16(clamping: secPr.intAttribute(
            "spaceColumns", default: Int(sectionDef.columnSpacing)
        ))
        sectionDef.defaultTabSpacing = secPr.uint32Attribute(
            "tabStop", default: sectionDef.defaultTabSpacing
        )
        if let startNum = secPr.paragraphFirstChild(named: "startNum") {
            sectionDef.pageStartNumber = startNum.uint16Attribute("page", default: 0)
            sectionDef.pictureStartNumber = startNum.uint16Attribute("pic", default: 0)
            sectionDef.tableStartNumber = startNum.uint16Attribute("tbl", default: 0)
            sectionDef.equationNumber = startNum.uint16Attribute("equation", default: 0)
        }
        // 각주/미주 모양·쪽 테두리는 1차 범위 밖 — 빈 문서 기본값을 유지하되,
        // 버려지는 자식은 진단으로 강등해야 "미해석 강등은 진단으로 보고됨"
        // 규약이 지켜진다 (tabPr의 tabItem 강등과 같은 채널).
        sectionDef.unknownChildren = secPr.unconsumedChildRecords(
            consumed: ["pagePr", "startNum"], in: HwpxNamespace.paragraph
        )
        return sectionDef
    }

    static func mapColumn(_ colPr: HwpxXMLNode) -> HwpColumn {
        var column = HwpColumn()
        var property = HwpColumnProperty()
        property.type = Self.columnTypes[colPr.attribute("type") ?? "NEWSPAPER"] ?? .general
        // 바이너리 모델은 count를 8비트(0...255)로 담으므로 HWPX 경로도 같은
        // 범위로 클램프한다 — 상한이 없으면 조작된 colCount가 columnFrames의
        // 0..<count 순회에서 행/OOM을 낸다 (P1).
        property.count = min(255, max(1, colPr.intAttribute("colCount", default: 1)))
        property.direction = Self.columnDirections[colPr.attribute("layout") ?? "LEFT"]
            ?? .left
        property.isSameWidth = colPr.boolAttribute("sameSz", default: true)
        column.property = property
        // sameGap은 동일 폭 다단의 단 간격이다 (HWPUNIT).
        column.spacing = Int16(clamping: colPr.intAttribute("sameGap", default: 0))

        // 폭이 다른 다단: hp:colSz(width·gap)가 단 수만큼 나열된다.
        let sizes = colPr.paragraphChildren(named: "colSz")
        if !property.isSameWidth, !sizes.isEmpty {
            column.widthArray = sizes.map { $0.uint16Attribute("width", default: 0) }
            column.gapArray = sizes.map { $0.uint16Attribute("gap", default: 0) }
            column.spacing = nil
        }

        if let line = colPr.paragraphFirstChild(named: "colLine") {
            column.dividerType = UInt8(clamping: HwpxCharShapeMapper.lineShapeIndex(
                line.attribute("type"), default: 0
            ))
            column.dividerThickness = HwpxParaShapeMapper.thicknessIndex(
                of: line.attribute("width")
            )
            column.dividerColor = line.colorAttribute("color") ?? HwpColor()
        }
        // 미소비 자식(미래 요소)은 진단으로 강등한다 — 비우면
        // parseDiagnostics()가 완전한 파스로 오보한다.
        column.unknownChildren = colPr.unconsumedChildRecords(
            consumed: ["colSz", "colLine"], in: HwpxNamespace.paragraph
        )
        return column
    }
}

private extension HwpxSecPrMapper {
    static let gutterTypes: [String: UInt32] = [
        "LEFT_ONLY": 0b000, "LEFT_RIGHT": 0b010, "TOP_BOTTOM": 0b100,
    ]

    static let columnTypes: [String: HwpColumnType] = [
        "NEWSPAPER": .general, "BALANCED_NEWSPAPER": .div, "PARALLEL": .along,
    ]

    static let columnDirections: [String: HwpColumnDirection] = [
        "LEFT": .left, "RIGHT": .right, "MIRROR": .yang,
    ]
}
