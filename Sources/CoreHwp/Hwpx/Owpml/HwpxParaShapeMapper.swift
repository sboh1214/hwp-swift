import Foundation

/// `hh:paraPr`·`hh:tabPr`·`hh:style`·`hh:borderFill`를 HWP5 모델로 옮긴다.
///
/// 문단 모양의 정렬·머리 종류·줄 간격 종류는 HWP5에서 속성1 bit field라
/// (표 44) 여기서 bit를 재합성한다 — `HwpParaShapeProperty1`의 파생 접근자
/// (`alignmentRawValue` 등)와 조판기가 그 bit를 읽기 때문이다.
enum HwpxParaShapeMapper {
    /// `hh:paraPr` 하나 → `HwpParaShape`.
    static func mapParaShape(_ node: HwpxXMLNode, tables: HwpxIdTables) -> HwpParaShape {
        let align = node.firstChild(named: "align")
        let heading = node.firstChild(named: "heading")
        let margin = node.firstChild(named: "margin")
        let lineSpacing = node.firstChild(named: "lineSpacing")
        let border = node.firstChild(named: "border")

        let lineSpacingKind = Self.lineSpacingKinds[
            lineSpacing?.attribute("type") ?? "PERCENT"
        ] ?? HwpLineSpacingKind.percent
        let lineSpacingValue = lineSpacing?.int32Attribute("value", default: 160) ?? 160

        let headingType = Self.headingTypes[heading?.attribute("type") ?? "NONE"] ?? 0
        var property1 = lineSpacingKind.rawValue & 0b11
        property1 |= (Self.alignments[align?.attribute("horizontal") ?? "JUSTIFY"] ?? 0) << 2
        property1 |= (headingType & 0b11) << 23
        property1 |= (UInt32(clamping: heading?.intAttribute("level", default: 0) ?? 0)
            & 0b111) << 25
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
            numberingOrBulletId: headingType == 0 ? 0 : UInt16(
                clamping: headingIdTable.resolvedOffset(of: headingIdRef)
            ),
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
    static func mapStyle(_ node: HwpxXMLNode, tables: HwpxIdTables) throws -> HwpStyle {
        let name = node.attribute("name") ?? ""
        let englishName = node.attribute("engName") ?? ""
        try hwpxValidateNameLength(name)
        try hwpxValidateNameLength(englishName)
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
                guard let child = node.firstChild(named: name) else {
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
        if let brush = node.firstChild(named: "fillBrush")?.firstChild(named: "winBrush"),
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
    static let headingTypes: [String: UInt32] = [
        "NONE": 0, "OUTLINE": 1, "NUMBER": 2, "BULLET": 3,
    ]

    static let lineSpacingKinds: [String: HwpLineSpacingKind] = [
        "PERCENT": .percent, "FIXED": .fixed,
        "BETWEEN_LINES": .marginOnly, "AT_LEAST": .atLeast,
    ]

    /// `hh:margin`의 `hc:<name> value= unit=` 자식 — HwpUnitChar 분기 해소
    /// 후이므로 단위는 HWPUNIT이 전제다 (다른 단위는 값 그대로 통과 — 실물
    /// 검증 항목).
    static func marginValue(_ margin: HwpxXMLNode?, _ name: String) -> Int32 {
        margin?.firstChild(named: name)?.int32Attribute("value", default: 0) ?? 0
    }

    /// `width="0.12 mm"` → 표 26 굵기 index (최근접 값).
    static func thicknessIndex(of width: String?) -> UInt8 {
        guard let width,
              let value = Double(width.split(separator: " ").first ?? "")
        else {
            return 0
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
