import Foundation

/// `hh:paraPr`·`hh:tabPr`·`hh:style`·`hh:borderFill`를 HWP5 모델로 옮긴다.
///
/// 문단 모양의 정렬·머리 종류·줄 간격 종류는 HWP5에서 속성1 bit field라
/// (표 44) 여기서 bit를 재합성한다 — `HwpParaShapeProperty1`의 파생 접근자
/// (`alignmentRawValue` 등)와 조판기가 그 bit를 읽기 때문이다.
enum HwpxParaShapeMapper {
    /// 표 44 bit 25-27이 담는 문단 수준 저장값(0-기반)의 상한 — 사람이 읽는 8수준.
    static let maximumHeadingLevelRawValue = 7

    /// 3비트에 담기지 않는 `hh:heading@level`의 진단 payload 접두 —
    /// `secPr@outlineShapeIDRef=`와 같은 `요소@속성=값` 꼴이다.
    static let headingLevelDiagnosticPrefix = "heading@level="

    /// `hh:paraPr` 하나 → `HwpParaShape`.
    ///
    /// 문단 머리 수준은 HWP5 표 44의 3비트 필드라 0-7(1-8수준)만 담긴다. OWPML은
    /// `hh:heading@level`을 그보다 크게 적을 수 있는데(9·10수준), 그대로 `& 0b111`로
    /// 접으면 9수준이 1수준으로 읽혀 번호 생성(#153)이 그럴듯하지만 틀린 라벨을
    /// 만든다. 한글 자신도 바이너리에서 그 수준을 머리 종류 **없음**으로 저장하므로
    /// (헌법주석의 `개요 8`·`개요 9` 스타일 문단 모양이 `headingType == 0`) 같은
    /// 값으로 접고, 접었다는 사실을 진단 레코드로 남긴다 — 탐색 목록은 스타일
    /// 이름(`개요 N`) 폴백으로 그 문단을 여전히 잡는다.
    static func mapParaShape(
        _ node: HwpxXMLNode,
        tables: HwpxIdTables,
        diagnostics: inout [HwpUnknownRecord]
    ) -> HwpParaShape {
        let align = node.headFirstChild(named: "align")
        let heading = node.headFirstChild(named: "heading")
        let margin = node.headFirstChild(named: "margin")
        let lineSpacing = node.headFirstChild(named: "lineSpacing")
        let border = node.headFirstChild(named: "border")

        let lineSpacingKind = Self.lineSpacingKinds[
            lineSpacing?.attribute("type") ?? "PERCENT"
        ] ?? HwpLineSpacingKind.percent
        let rawLineSpacingValue = lineSpacing?.int32Attribute("value", default: 160) ?? 160
        // 비율(%)은 순수 배율이라 그대로, HWPUNIT 종류(고정·최소·여백만)는
        // 여백과 같은 2배 저장 규약을 따른다 (noori 실측: FIXED 3600↔1800).
        let lineSpacingValue = lineSpacingKind == .percent
            ? rawLineSpacingValue
            : Int32(clamping: Int64(rawLineSpacingValue) * 2)

        let (headingType, headingLevel) = Self.headingFields(heading, diagnostics: &diagnostics)
        var property1 = lineSpacingKind.rawValue & 0b11
        property1 |= (Self.alignments[align?.attribute("horizontal") ?? "JUSTIFY"] ?? 0) << 2
        property1 |= (headingType & 0b11) << 23
        property1 |= (UInt32(clamping: headingLevel) & 0b111) << 25
        if border?.boolAttribute("connect") == true {
            property1 |= 1 << 28
        }
        if border?.boolAttribute("ignoreMargin") == true {
            property1 |= 1 << 29
        }

        let headingIdTable = headingType == 3 ? tables.bullet : tables.numbering
        let headingIdRef = heading?.attribute("idRef")

        return HwpParaShape(
            hwpxProperty1: property1,
            marginLeft: Self.marginValue(margin, "left"),
            marginRight: Self.marginValue(margin, "right"),
            indent: Self.marginValue(margin, "intent"),
            paragraphSpacingTop: Self.marginValue(margin, "prev"),
            paragraphSpacingBottom: Self.marginValue(margin, "next"),
            lineSpacing: lineSpacingValue,
            tabDefId: UInt16(
                clamping: tables.tabDef.resolvedOffset(of: node.attribute("tabPrIDRef"))
            ),
            // 번호·글머리표 참조는 borderFill과 같은 1-based다 (0 = 없음) —
            // 조판이 `numberingOrBulletId > 0` 게이트 뒤에서 -1로 되돌리므로
            // 0-based 오프셋을 그대로 실으면 첫 정의가 사라지고 이후 참조가
            // 한 칸씩 앞을 가리킨다. 개요(1)는 이 배열을 쓰지 않아 0이다.
            // +1은 **조회에 성공했을 때만**이다 — `resolvedOffset`의 댕글링
            // 폴백 0에 더하면 없는 참조가 첫 정의를 가리키게 된다.
            numberingOrBulletId: headingType == 2 || headingType == 3
                ? headingIdTable.offset(of: headingIdRef)
                .map { UInt16(clamping: $0 + 1) } ?? 0
                : 0,
            borderFillId: tables.borderFillId(of: border?.attribute("borderFillIDRef")),
            borderSpacingLeft: Int16(
                clamping: border?.intAttribute("offsetLeft", default: 0) ?? 0
            ),
            borderSpacingRight: Int16(
                clamping: border?.intAttribute("offsetRight", default: 0) ?? 0
            ),
            borderSpacingTop: Int16(
                clamping: border?.intAttribute("offsetTop", default: 0) ?? 0
            ),
            borderSpacingBottom: Int16(
                clamping: border?.intAttribute("offsetBottom", default: 0) ?? 0
            ),
            property3: lineSpacingKind.rawValue,
            lineSpacing2: UInt32(clamping: lineSpacingValue)
        )
    }

    /// `hh:tabPr` → `HwpTabDef`. 명시 탭 정지(`hh:tabItem`)는 1차 범위 밖이라
    /// 자동 탭 속성만 옮긴다 (bit 0 = 왼쪽 끝 자동 탭, bit 1 = 오른쪽 끝).
    static func mapTabDef(_ node: HwpxXMLNode) -> HwpTabDef {
        var property: UInt32 = 0
        if node.boolAttribute("autoTabLeft") {
            property |= 0b1
        }
        if node.boolAttribute("autoTabRight") {
            property |= 0b10
        }
        return HwpTabDef(property: property)
    }

    /// `hh:style` → `HwpStyle`.
    static func mapStyle(
        _ node: HwpxXMLNode, tables: HwpxIdTables, entry: String
    ) throws -> HwpStyle {
        let name = node.attribute("name") ?? ""
        let englishName = node.attribute("engName") ?? ""
        try hwpxValidateNameLength(name, entry: entry)
        try hwpxValidateNameLength(englishName, entry: entry)
        return HwpStyle(
            name,
            englishName,
            property: node.attribute("type") == "CHAR" ? 1 : 0,
            nextId: BYTE(
                clamping: tables.style.resolvedOffset(of: node.attribute("nextStyleIDRef"))
            ),
            paraShapeId: UInt16(
                clamping: tables.paraShape.resolvedOffset(of: node.attribute("paraPrIDRef"))
            ),
            charShapeId: UInt16(
                clamping: tables.charShape.resolvedOffset(of: node.attribute("charPrIDRef"))
            )
        )
    }

    /// `hh:borderFill` → `HwpBorderFill` — 4방향 테두리와 단색 채우기만
    /// 해석한다 (그러데이션·이미지 채우기는 1차 범위 밖).
    static func mapBorderFill(_ node: HwpxXMLNode) -> HwpBorderFill {
        let borders = ["leftBorder", "rightBorder", "topBorder", "bottomBorder"]
            .map { name -> HwpBorderLine in
                guard let child = node.headFirstChild(named: name) else {
                    return HwpBorderLine()
                }
                return HwpBorderLine(
                    typeRawValue: UInt8(clamping: HwpxCharShapeMapper.lineShapeIndex(
                        child.attribute("type"), default: 0
                    )),
                    thickness: Self.thicknessIndex(of: child.attribute("width")),
                    color: child.colorAttribute("color") ?? HwpColor()
                )
            }

        var fillInfo: [BYTE] = []
        if let brush = node.coreFirstChild(named: "fillBrush")?
            .coreFirstChild(named: "winBrush"),
            let faceColor = brush.colorAttribute("faceColor")
        {
            // 표 28 단색 채우기: type(4B LE=1) + 배경색 COLORREF + 무늬색
            // COLORREF + 무늬 종류 Int32(-1 = 무늬 없음).
            fillInfo = [1, 0, 0, 0]
            fillInfo += Self.colorrefBytes(faceColor)
            fillInfo += Self.colorrefBytes(
                brush.colorAttribute("hatchColor") ?? HwpColor()
            )
            fillInfo += [0xFF, 0xFF, 0xFF, 0xFF]
        }

        return HwpBorderFill(hwpxBorders: borders, fillInfo: fillInfo)
    }
}

extension HwpxParaShapeMapper {
    /// 표 44 bit 2-4 정렬: 0 양쪽, 1 왼쪽, 2 오른쪽, 3 가운데, 4 배분, 5 나눔.
    static let alignments: [String: UInt32] = [
        "JUSTIFY": 0, "LEFT": 1, "RIGHT": 2, "CENTER": 3,
        "DISTRIBUTE": 4, "DISTRIBUTE_SPACE": 5,
    ]

    /// 표 44 bit 23-24 문단 머리 종류: 0 없음, 1 개요, 2 번호, 3 글머리표.
    /// `hh:heading`의 머리 종류와 저장 수준. 3비트 밖 수준은 머리 종류 없음(0·0)으로
    /// 접고 진단을 남긴다 — 머리 종류가 없으면 수준은 뜻이 없어 접지 않는다.
    static func headingFields(
        _ heading: HwpxXMLNode?,
        diagnostics: inout [HwpUnknownRecord]
    ) -> (type: UInt32, level: Int) {
        let type = headingTypes[heading?.attribute("type") ?? "NONE"] ?? 0
        let level = heading?.intAttribute("level", default: 0) ?? 0
        guard type != 0, !(0 ... maximumHeadingLevelRawValue).contains(level) else {
            return (type, level)
        }
        diagnostics.append(HwpUnknownRecord(
            tagId: hwpxSyntheticTagId,
            level: 0,
            payload: Data((headingLevelDiagnosticPrefix + String(level)).utf8)
        ))
        return (0, 0)
    }

    static let headingTypes: [String: UInt32] = [
        "NONE": 0, "OUTLINE": 1, "NUMBER": 2, "BULLET": 3,
    ]

    static let lineSpacingKinds: [String: HwpLineSpacingKind] = [
        "PERCENT": .percent, "FIXED": .fixed,
        "BETWEEN_LINES": .marginOnly, "AT_LEAST": .atLeast,
    ]

    /// `hh:margin`의 `hc:<name> value= unit=` 자식 — HwpUnitChar 분기 해소
    /// 후이므로 단위는 HWPUNIT이 전제다 (다른 단위는 값 그대로 통과 — 실물
    /// 검증 항목). HWP5 모델은 이 길이들을 HWPUNIT의 2배로 저장하므로
    /// (조판이 /2로 소비 — noori HWP↔HWPX 실측: indent -2620↔-1310 등
    /// 전 항목 2배) 모델 경계에서 2배로 올린다.
    static func marginValue(_ margin: HwpxXMLNode?, _ name: String) -> Int32 {
        let value = margin?.coreFirstChild(named: name)?
            .int32Attribute("value", default: 0) ?? 0
        return Int32(clamping: Int64(value) * 2)
    }

    /// `width="0.12 mm"` → 표 26 굵기 index (최근접 값).
    ///
    /// 생략·숫자로 못 읽는 값은 `default:`로 접는다. 한컴 `GetAttribute`는 이름이
    /// 표(`g_LineWithList`)에 없으면 값을 건드리지 않아 **호출 클래스의 생성자
    /// 값**이 남으므로, 그 값을 아는 호출부는 넘겨야 참조와 같아진다
    /// (`hp:noteLine@width`는 `CNoteLine()`의 `LWT_0_12` = index 1).
    static func thicknessIndex(of width: String?, default defaultValue: UInt8 = 0) -> UInt8 {
        guard let width,
              let value = Double(width.split(separator: " ").first ?? "")
        else {
            return defaultValue
        }
        let table = HwpBorderFill.borderThicknessMillimeters
        var best = 0
        for (index, millimeters) in table.enumerated()
            where abs(millimeters - value) < abs(table[best] - value)
        {
            best = index
        }
        return UInt8(best)
    }

    static func colorrefBytes(_ color: HwpColor) -> [BYTE] {
        [
            BYTE(clamping: color.red),
            BYTE(clamping: color.green),
            BYTE(clamping: color.blue),
            0,
        ]
    }
}
