import Foundation

/// `hp:secPr`·`hp:colPr`를 `HwpSectionDef`·`HwpColumn`으로 옮긴다.
///
/// 두 컨트롤 모두 HWP5에서 구역 첫 문단의 extended 2 문자에 붙는다 —
/// HWPX도 같은 배치다 (첫 문단 첫 run 안, 실물 검증). paginator는
/// `sectionDef(in:)` 하나로만 구역 경계를 인식하므로 이 매핑이 구역
/// 지오메트리의 전부다.
enum HwpxSecPrMapper {
    static func mapSectionDef(
        _ secPr: HwpxXMLNode, tables: HwpxIdTables, options: HwpLoadOptions, maxDepth: Int
    ) throws -> HwpSectionDef {
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
        // 잘못된 참조의 진단은 아래 강등 목록 **앞**에 싣는다 — 목록은 대입으로
        // 시작하므로 여기서 `unknownChildren`에 직접 붙이면 덮인다.
        var referenceDiagnostics: [HwpUnknownRecord] = []
        sectionDef.numberParaShapeId = Self.outlineNumberingId(
            secPr.attribute("outlineShapeIDRef"),
            tables: tables,
            diagnostics: &referenceDiagnostics
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
        // 구역 첫 쪽 감추기 — 아래 `applyFirstPageVisibility` 참조.
        applyFirstPageVisibility(
            secPr.paragraphFirstChild(named: "visibility"), to: &sectionDef
        )
        // 각주·미주 모양 — 아래 `applyNoteShapes` 참조.
        try applyNoteShapes(secPr, options: options, to: &sectionDef)
        // 쪽 테두리는 1차 범위 밖 — 빈 문서 기본값을 유지하되, 버려지는 자식은
        // 진단으로 강등해야 "미해석 강등은 진단으로 보고됨" 규약이 지켜진다
        // (tabPr의 tabItem 강등과 같은 채널).
        sectionDef.unknownChildren = referenceDiagnostics + secPr.unconsumedChildRecords(
            consumed: Set(Self.consumedChildren), in: HwpxNamespace.paragraph,
            maxDepth: maxDepth
        )
        // 전부 단일 조회라 둘째 등장부터는 읽히지 않는다 — 소비 표시가
        // 이름 단위라 그대로 두면 값도 진단도 없이 사라진다.
        sectionDef.unknownChildren += secPr.duplicateSingletonRecords(
            of: Self.consumedChildren, in: HwpxNamespace.paragraph, maxDepth: maxDepth
        )
        sectionDef.unknownChildren += consumedWrapperDiagnostics(secPr, maxDepth: maxDepth)
        return sectionDef
    }

    /// `hp:footNotePr`·`hp:endNotePr` → 구역의 각주·미주 모양 (표 133, #168).
    ///
    /// 요소가 없으면 손대지 않는다 — 빈 문서 기본값을 유지해야 값을 지어내지
    /// 않는다. 승격 전에는 두 요소가 통째로 진단 강등돼 번호 모양·장식 문자·
    /// 시작 번호·미주 배치가 기본값에 고정됐고, `rawPayload`가 비어
    /// `HwpFootnoteShape.dividerInfo`가 nil이라 구분선까지 튜닝 폴백으로
    /// 떨어졌다 (HWP 쌍 0.34pt ↔ HWPX 1.0pt).
    static func applyNoteShapes(
        _ secPr: HwpxXMLNode,
        options: HwpLoadOptions,
        to sectionDef: inout HwpSectionDef
    ) throws {
        if let shape = try HwpxFootnoteShapeMapper.map(
            secPr.paragraphFirstChild(named: "footNotePr"), options: options
        ) {
            sectionDef.footNoteShape = shape
        }
        if let shape = try HwpxFootnoteShapeMapper.map(
            secPr.paragraphFirstChild(named: "endNotePr"), options: options
        ) {
            sectionDef.endNoteShape = shape
        }
    }

    /// 소비 래퍼 안 미지 자식 — pagePr는 margin만, margin·startNum·visibility는
    /// 속성만, footNotePr·endNotePr는 다섯 자식의 속성만 읽는다. 래퍼를 소비
    /// 목록에 넣으면 그 서브트리가 위 순회에서 빠지므로, 안쪽 미지 자식은
    /// 여기서 따로 걷어야 진단에서 사라지지 않는다.
    static func consumedWrapperDiagnostics(
        _ secPr: HwpxXMLNode, maxDepth: Int
    ) -> [HwpUnknownRecord] {
        var records: [HwpUnknownRecord] = []
        if let pagePr = secPr.paragraphFirstChild(named: "pagePr") {
            records += pagePr.unconsumedChildRecords(
                consumed: ["margin"], in: HwpxNamespace.paragraph, maxDepth: maxDepth
            )
            records += pagePr.duplicateSingletonRecords(
                of: ["margin"], in: HwpxNamespace.paragraph, maxDepth: maxDepth
            )
            if let margin = pagePr.paragraphFirstChild(named: "margin") {
                records += margin.unconsumedChildRecords(consumed: [], maxDepth: maxDepth)
            }
        }
        for name in ["startNum", "visibility"] {
            guard let node = secPr.paragraphFirstChild(named: name) else { continue }
            records += node.unconsumedChildRecords(consumed: [], maxDepth: maxDepth)
        }
        for name in ["footNotePr", "endNotePr"] {
            guard let node = secPr.paragraphFirstChild(named: name) else { continue }
            records += node.unconsumedChildRecords(
                consumed: Set(Self.consumedNoteShapeChildren), in: HwpxNamespace.paragraph,
                maxDepth: maxDepth
            )
            records += node.duplicateSingletonRecords(
                of: Self.consumedNoteShapeChildren, in: HwpxNamespace.paragraph,
                maxDepth: maxDepth
            )
            for child in Self.consumedNoteShapeChildren {
                records += node.paragraphFirstChild(named: child)?
                    .unconsumedChildRecords(consumed: [], maxDepth: maxDepth) ?? []
            }
        }
        return records
    }

    /// `hp:secPr`에서 값을 읽어 소비하는 자식 요소 — 진단 강등 대상에서 뺀다.
    static let consumedChildren = [
        "pagePr", "startNum", "visibility", "footNotePr", "endNotePr",
    ]

    /// `hp:footNotePr`·`hp:endNotePr`에서 값을 읽어 소비하는 자식 요소.
    static let consumedNoteShapeChildren = [
        "autoNumFormat", "noteLine", "noteSpacing", "numbering", "placement",
    ]

    /// 구역 첫 쪽 감추기(`hp:visibility`) → 표 132 bits 0·1·2·5.
    ///
    /// 머리말·꼬리말이 typed 승격된 뒤(#167) 이 플래그가 없으면 감춰야 할 첫 쪽에도
    /// 머리말이 그려진다. 조판은 `HwpPageChromeBuilder.applySectionHideFlags`가
    /// 머리말·꼬리말·쪽 번호 셋을 표 145 마스크(0x01·0x02·0x20)로 환산해 구역
    /// 첫 쪽에 한 번 쓴다. 나머지 속성(`border`·`fill` 열거·`showLineNumber`)은
    /// 대응 소비자가 없어 옮기지 않는다 — 자식이 아니라 속성이라 진단에도 남지 않는다.
    ///
    /// **속성만 읽는다** — 이 요소는 `mapSectionDef`의 소비 목록에 들어가 위 순회에서
    /// 빠지므로, 안쪽 미지 자식은 호출부가 `startNum`과 같은 자리에서 따로 걷는다.
    static func applyFirstPageVisibility(
        _ visibility: HwpxXMLNode?,
        to sectionDef: inout HwpSectionDef
    ) {
        guard let visibility else { return }
        var mask: UInt32 = 0
        if visibility.boolAttribute("hideFirstHeader") {
            mask |= 1 << 0
        }
        if visibility.boolAttribute("hideFirstFooter") {
            mask |= 1 << 1
        }
        if visibility.boolAttribute("hideFirstMasterPage") {
            mask |= 1 << 2
        }
        if visibility.boolAttribute("hideFirstPageNum") {
            mask |= 1 << 5
        }
        sectionDef.property |= mask
        // 표현이 셋이다 — property·파생 필드·propertyInfo.rawValue.
        sectionDef.propertyInfo.hideHeader = mask & (1 << 0) != 0
        sectionDef.propertyInfo.hideFooter = mask & (1 << 1) != 0
        sectionDef.propertyInfo.hideMasterPage = mask & (1 << 2) != 0
        sectionDef.propertyInfo.hidePageNumberPosition = mask & (1 << 5) != 0
        sectionDef.propertyInfo.rawValue = sectionDef.property
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
        // colSz는 목록이라 전부 소비되지만 colLine은 단일 조회다.
        column.unknownChildren += colPr.duplicateSingletonRecords(
            of: ["colLine"], in: HwpxNamespace.paragraph, maxDepth: maxDepth
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

extension HwpxSecPrMapper {
    /// 잘못된 `outlineShapeIDRef`를 진단으로 남길 때의 합성 레코드 payload 접두.
    /// 요소 강등의 payload가 OWPML local name인 것과 달리 속성 강등이라
    /// `요소@속성=값` 꼴로 적는다 (`parseDiagnostics()`가 그대로 읽는다).
    static let outlineReferenceDiagnosticPrefix = "secPr@outlineShapeIDRef="

    /// `hp:secPr@outlineShapeIDRef` → 구역 정의의 번호 문단 모양 ID (#152).
    ///
    /// HWP5의 필드는 1-based 참조(0 = 없음)라 `numberingOrBulletId`와 같은
    /// 규약으로 id 테이블 오프셋 + 1을 싣는다 — HWPX id는 dense가 아니라
    /// 숫자를 그대로 쓰면 안 된다 (noori 실물: id "2"가 오프셋 1 → 2, HWP 쌍도 2).
    /// 세 경로를 가른다: **생략**은 0 — 한컴 참조 모델이 `m_uOutlineShapeIDRef(0)`
    /// 으로 세우고 `GetAttribute`가 속성 부재 시 값을 건드리지 않는다
    /// (`SectionDefinitionType.cpp`; 빈 문서 기본값 1은 바이너리 저장기의 값이지
    /// 생략의 뜻이 아니다). **잘못된 참조**(테이블에 없는 id)도 0으로 접되 진단
    /// 레코드를 남겨 생략과 구분한다 — 조판이 "참조 없음"으로 보고하는 것은
    /// 같지만 `parseDiagnostics()`에서는 이쪽만 드러난다. 정상 참조는 조판이
    /// 개요 번호 정의를 찾는 유일한 통로다 (`HwpSectionDef.numberParaShapeId`).
    static func outlineNumberingId(
        _ ref: String?,
        tables: HwpxIdTables,
        diagnostics: inout [HwpUnknownRecord]
    ) -> UInt16 {
        guard let ref else {
            return 0
        }
        guard let offset = tables.numbering.offset(of: ref) else {
            diagnostics.append(HwpUnknownRecord(
                tagId: hwpxSyntheticTagId,
                level: 0,
                payload: Data((outlineReferenceDiagnosticPrefix + ref).utf8)
            ))
            return 0
        }
        // 정의는 헤더 매핑이 65,535개로 상한을 걸어 (`mapNumberings`) 오프셋 + 1이
        // UInt16을 넘지 않는다 — clamping은 그 불변식의 방어다.
        return UInt16(clamping: offset + 1)
    }
}

private extension HwpxSecPrMapper {
    static let gutterTypes: [String: UInt32] = [
        "LEFT_ONLY": 0b000, "LEFT_RIGHT": 0b010, "TOP_BOTTOM": 0b100,
    ]

    /// `hp:startNum pageStartsOn` → 구역 정의 속성(표 130) bits 20-21의 값.
    ///
    /// **`EVEN`이 1, `ODD`가 2다** — 한글이 실제로 저장하는 값이다 (#173). 한글
    /// 12.30.0 macOS의 `쪽 > 구역 설정... > 종류`를 홀수로 저장한 HWP는 property
    /// `0x200000`(bits 20-21 = 2), 짝수는 `0x100000`(= 1)이고, 같은 편집
    /// 세션에서 저장한 HWPX는 각각 `ODD`·`EVEN`이다 (`section-page-starts-on`
    /// 쌍, 2026-09-11 실측). 한컴 공개 모델의 직렬화 표(`enumdef.h`
    /// `STARTNUMSTARTONTYPE`: BOTH 0 · EVEN 1 · ODD 2)도 같다. 표 130은 이
    /// 비트의 값을 적지 않아 종전 매핑이 `ODD → 1`을 가정했었다 — 스펙이 값을
    /// 적지 않은 자리는 모델의 열거 값을 읽는다. 사용자 지정 시작 번호는
    /// `BOTH` + `page` 속성이라 종류 비트는 0이다. 미지 이름·생략은 한컴 모델의
    /// `GetAttribute` 규약대로 생성자 기본값 `BOTH`로 접는다.
    static let pageStartModes: [String: Int] = [
        "BOTH": 0, "EVEN": 1, "ODD": 2,
    ]

    static let columnTypes: [String: HwpColumnType] = [
        "NEWSPAPER": .general, "BALANCED_NEWSPAPER": .div, "PARALLEL": .along,
    ]

    static let columnDirections: [String: HwpColumnDirection] = [
        "LEFT": .left, "RIGHT": .right, "MIRROR": .yang,
    ]
}
