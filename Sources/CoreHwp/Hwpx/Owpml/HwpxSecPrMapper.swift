import Foundation

/// `hp:secPr`·`hp:colPr`를 `HwpSectionDef`·`HwpColumn`으로 옮긴다.
///
/// 두 컨트롤 모두 HWP5에서 구역 첫 문단의 extended 2 문자에 붙는다 —
/// HWPX도 같은 배치다 (첫 문단 첫 run 안, 실물 검증). paginator는
/// `sectionDef(in:)` 하나로만 구역 경계를 인식하므로 이 매핑이 구역
/// 지오메트리의 전부다.
enum HwpxSecPrMapper {
    static func mapSectionDef(_ secPr: HwpxXMLNode, maxDepth: Int) -> HwpSectionDef {
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
            // 카운터만 옮기면 홀수/짝수쪽 시작이 '양쪽'으로 보고된다 —
            // 구역 정의 속성 bits 20-21("새 쪽 번호 적용")에 함께 싣는다.
            // raw와 파생 필드를 같이 써야 둘이 어긋나지 않는다.
            let startsOn = Self.pageStartModes[
                startNum.attribute("pageStartsOn") ?? "BOTH"
            ] ?? 0
            sectionDef.property |= UInt32(startsOn) << 20
            sectionDef.propertyInfo.newPageNumberApplyRawValue = startsOn
            // 표현이 셋이다 — property·파생 필드·propertyInfo.rawValue.
            // 바이너리는 load(property)가 셋을 함께 세우므로 여기서도 맞춘다.
            sectionDef.propertyInfo.rawValue = sectionDef.property
            sectionDef.pageStartNumber = startNum.uint16Attribute("page", default: 0)
            sectionDef.pictureStartNumber = startNum.uint16Attribute("pic", default: 0)
            sectionDef.tableStartNumber = startNum.uint16Attribute("tbl", default: 0)
            sectionDef.equationNumber = startNum.uint16Attribute("equation", default: 0)
        }
        // 각주/미주 모양·쪽 테두리는 1차 범위 밖 — 빈 문서 기본값을 유지하되,
        // 버려지는 자식은 진단으로 강등해야 "미해석 강등은 진단으로 보고됨"
        // 규약이 지켜진다 (tabPr의 tabItem 강등과 같은 채널).
        sectionDef.unknownChildren = secPr.unconsumedChildRecords(
            consumed: ["pagePr", "startNum"], in: HwpxNamespace.paragraph,
            maxDepth: maxDepth
        )
        // 소비 래퍼 안 미지 자식 — pagePr는 margin만, margin·startNum은
        // 속성만 읽는다.
        if let pagePr = secPr.paragraphFirstChild(named: "pagePr") {
            sectionDef.unknownChildren += pagePr.unconsumedChildRecords(
                consumed: ["margin"], in: HwpxNamespace.paragraph, maxDepth: maxDepth
            )
            if let margin = pagePr.paragraphFirstChild(named: "margin") {
                sectionDef.unknownChildren += margin.unconsumedChildRecords(
                    consumed: [], maxDepth: maxDepth
                )
            }
        }
        if let startNum = secPr.paragraphFirstChild(named: "startNum") {
            sectionDef.unknownChildren += startNum.unconsumedChildRecords(
                consumed: [], maxDepth: maxDepth
            )
        }
        return sectionDef
    }

    static func mapColumn(_ colPr: HwpxXMLNode, maxDepth: Int) -> HwpColumn {
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
        // sameGap은 동일 폭 다단의 단 간격이다 (HWPUNIT).
        column.spacing = Int16(clamping: colPr.intAttribute("sameGap", default: 0))

        // 폭이 다른 다단: hp:colSz(width·gap)가 단 수만큼 나열된다.
        let sizes = colPr.paragraphChildren(named: "colSz")
        if !property.isSameWidth, !sizes.isEmpty, sizes.count <= 255 {
            // 비등폭 단은 파싱된 colSz가 구조의 정본이다 — 선언 colCount와
            // 어긋나면 columnFrames의 count 대조(widths.count == count)가
            // widthArray를 버리고 등폭으로 그린다.
            property.count = sizes.count
            column.widthArray = sizes.map { $0.uint16Attribute("width", default: 0) }
            column.gapArray = sizes.map { $0.uint16Attribute("gap", default: 0) }
            column.spacing = nil
        }
        // typed 필드가 확정된 뒤 raw를 합성한다 — 비등폭 분기가 count를
        // 고쳐 쓰므로 그 앞에서 실으면 두 표현이 어긋난다.
        property.rawValue = property.synthesizedRawValue
        column.property = property

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
            consumed: ["colSz", "colLine"], in: HwpxNamespace.paragraph,
            maxDepth: maxDepth
        )
        if !property.isSameWidth, sizes.count > 255 {
            // 8비트 count가 못 담는 폭 목록은 채택 불능이다 — 등폭 폴백으로
            // 그리되 버리는 colSz를 진단에 남겨 조용히 지나가지 않게 한다.
            column.unknownChildren += sizes.map { $0.syntheticUnknownRecord(maxDepth: maxDepth) }
        } else {
            for size in sizes {
                column.unknownChildren += size.unconsumedChildRecords(consumed: [], maxDepth: maxDepth)
            }
        }
        if let line = colPr.paragraphFirstChild(named: "colLine") {
            column.unknownChildren += line.unconsumedChildRecords(consumed: [], maxDepth: maxDepth)
        }
        return column
    }
}

private extension HwpxSecPrMapper {
    static let gutterTypes: [String: UInt32] = [
        "LEFT_ONLY": 0b000, "LEFT_RIGHT": 0b010, "TOP_BOTTOM": 0b100,
    ]

    /// `hp:startNum pageStartsOn` → 구역 정의 속성 bits 20-21의 값.
    ///
    /// 코퍼스는 `BOTH`(11건)만 쓰므로 나머지 두 값은 **실물 대조 전**이다 —
    /// HWP5 표의 나열 순서(양쪽·홀수쪽·짝수쪽)를 따랐다. 홀수/짝수 시작
    /// 문서를 얻으면 그 값부터 확인할 것.
    static let pageStartModes: [String: Int] = [
        "BOTH": 0, "ODD": 1, "EVEN": 2,
    ]

    static let columnTypes: [String: HwpColumnType] = [
        "NEWSPAPER": .general, "BALANCED_NEWSPAPER": .div, "PARALLEL": .along,
    ]

    static let columnDirections: [String: HwpColumnDirection] = [
        "LEFT": .left, "RIGHT": .right, "MIRROR": .yang,
    ]
}
