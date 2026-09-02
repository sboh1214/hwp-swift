import Foundation

/// 개체 공통 속성 — `hp:sz`/`hp:pos`/`hp:outMargin`과 개체 요소 자체의
/// 배치 속성(textWrap 등)을 `HwpCommonCtrlProperty`로 옮긴다.
///
/// **textWrap은 HWPX 전용 6값 매핑이다** — 바이너리 HWP5의 실측 4값 매핑
/// (`HwpCommonCtrlTextWrap` 주석의 #1 예고)과 달리 이름 붙은 값이 오며,
/// HWP5 모델에 없는 THROUGH/TIGHT는 어울림(square)으로 근사한다.
enum HwpxObjectCommonMapper {
    /// `hp:pos`의 오프셋은 음수가 정상값인데(기준 위·왼쪽으로 밀린 개체)
    /// 표현이 **두 가지**다 — 한글.app 저장본은 UInt32 비트 패턴으로 적고
    /// (실측: noori의 표가 -140을 `4294967156`으로), 스키마가 허용하는 부호
    /// 리터럴도 올 수 있다. 한쪽만 받으면 다른 쪽이 파싱 실패로 0이 되어
    /// 개체가 기준 원점으로 이동한다.
    ///
    /// 두 해석은 배타적이라 모호하지 않다 — `-140`은 UInt32로, `4294967156`은
    /// Int32로 각각 파싱되지 않고, 겹치는 `0...Int32.max`는 두 경로가 같은
    /// 비트열을 낸다. 하류는 `Int32(bitPattern:)`으로 되읽는다.
    static func offset(_ node: HwpxXMLNode, _ name: String) -> HWPUNIT {
        guard let raw = node.attribute(name) else {
            return 0
        }
        if let signed = Int32(raw) {
            return HWPUNIT(bitPattern: signed)
        }
        return UInt32(raw) ?? 0
    }

    static func map(_ node: HwpxXMLNode, ctrlId: HwpCommonCtrlId) -> HwpCommonCtrlProperty {
        var property = HwpCommonCtrlProperty(commonCtrlId: ctrlId)
        var info = HwpCommonCtrlPropertyInfo()

        if let size = node.paragraphFirstChild(named: "sz") {
            property.width = size.uint32Attribute("width", default: 0)
            property.height = size.uint32Attribute("height", default: 0)
            info.widthRelativeTo = widthRelativeTos[size.attribute("widthRelTo") ?? "ABSOLUTE"]
                ?? .absolute
            info.widthRelativeToRawValue = info.widthRelativeTo?.rawValue ?? 4
            info.heightRelativeTo = heightRelativeTos[
                size.attribute("heightRelTo") ?? "ABSOLUTE"
            ] ?? .absolute
            info.heightRelativeToRawValue = info.heightRelativeTo?.rawValue ?? 2
            info.protectSizeInParagraphVertRelTo = size.boolAttribute("protect")
        }

        if let position = node.paragraphFirstChild(named: "pos") {
            info.treatAsChar = position.boolAttribute("treatAsChar")
            info.affectsLineSpacing = position.boolAttribute("affectLSpacing")
            info.allowOverlap = position.boolAttribute("allowOverlap")
            info.restrictInPage = position.boolAttribute("flowWithText")
            info.verticalRelativeTo = verticalRelativeTos[
                position.attribute("vertRelTo") ?? "PARA"
            ] ?? .paragraph
            info.verticalRelativeToRawValue = info.verticalRelativeTo?.rawValue ?? 2
            info.horizontalRelativeTo = horizontalRelativeTos[
                position.attribute("horzRelTo") ?? "COLUMN"
            ] ?? .column
            info.horizontalRelativeToRawValue = info.horizontalRelativeTo?.rawValue ?? 2
            info.verticalAlignment = alignments[position.attribute("vertAlign") ?? "TOP"]
                ?? .topOrLeft
            info.verticalAlignmentRawValue = info.verticalAlignment?.rawValue ?? 0
            info.horizontalAlignment = alignments[position.attribute("horzAlign") ?? "LEFT"]
                ?? .topOrLeft
            info.horizontalAlignmentRawValue = info.horizontalAlignment?.rawValue ?? 0
            property.verticalOffset = Self.offset(position, "vertOffset")
            property.horizontalOffset = Self.offset(position, "horzOffset")
        }

        if let outMargin = node.paragraphFirstChild(named: "outMargin") {
            property.marginArray = ["left", "right", "top", "bottom"].map {
                Int16(clamping: outMargin.intAttribute($0, default: 0))
            }
        }

        info.textWrap = textWraps[node.attribute("textWrap") ?? "SQUARE"] ?? .square
        info.textWrapRawValue = info.textWrap?.rawValue ?? 0
        info.textFlowSide = textFlowSides[node.attribute("textFlow") ?? "BOTH_SIDES"]
            ?? .bothSides
        info.textFlowSideRawValue = info.textFlowSide?.rawValue ?? 0
        info.numberingCategory = numberingCategories[
            node.attribute("numberingType") ?? "NONE"
        ] ?? HwpCommonCtrlNumberingCategory.none
        info.numberingCategoryRawValue = info.numberingCategory?.rawValue ?? 0

        // typed 필드만 채우면 raw 두 자리가 0으로 남아 "종이 기준·어울림"
        // 이라는 어긋난 값이 함께 공개된다 (렌더는 typed만 보므로 조판이 아니라
        // 모델 정합성 문제다). 읽기 순서를 역산해 둘을 함께 세운다.
        info.rawValue = info.synthesizedRawValue
        property.propertyInfo = info
        property.property = info.rawValue
        property.zOrder = node.int32Attribute("zOrder", default: 0)
        // 인스턴스 아이디는 `instid`다 — `id`는 OWPML 요소 식별자라 실물에서
        // 값이 갈린다 (픽스처 그림 7개에서 서로 다르다). 표는 `instid`를
        // 선언하지 않으므로 폴백이 필수다: 없애면 모든 표의 instanceId가 0이
        // 되어 조판의 truncatedTableRowLimits 버킷이 뭉개진다.
        if let declared = node.attribute("instid").flatMap(UInt32.init) {
            property.instanceId = declared
        } else {
            property.instanceId = node.uint32Attribute("id", default: 0)
        }
        return property
    }
}

private extension HwpxObjectCommonMapper {
    /// HWPX 6값 → HWP5 4값 근사 — #1이 예고한 별도 매핑.
    static let textWraps: [String: HwpCommonCtrlTextWrap] = [
        "SQUARE": .square, "TIGHT": .square, "THROUGH": .square,
        "TOP_AND_BOTTOM": .topAndBottom,
        "BEHIND_TEXT": .behindText, "IN_FRONT_OF_TEXT": .inFrontOfText,
    ]

    static let textFlowSides: [String: HwpCommonCtrlTextFlowSide] = [
        "BOTH_SIDES": .bothSides, "LEFT_ONLY": .leftOnly,
        "RIGHT_ONLY": .rightOnly, "LARGEST_ONLY": .largestOnly,
    ]

    /// 한컴 저장본은 그림을 numberingType="PICTURE"로 쓴다 (실측: 픽스처
    /// section XML에 PICTURE만 있고 FIGURE는 0건) — HWP 모델의 .figure로 함께
    /// 매핑해야 실제 그림이 .none으로 떨어지지 않는다 (P2).
    static let numberingCategories: [String: HwpCommonCtrlNumberingCategory] = [
        "NONE": .none, "FIGURE": .figure, "PICTURE": .figure,
        "TABLE": .table, "EQUATION": .equation,
    ]

    static let widthRelativeTos: [String: HwpCommonCtrlObjectWidthRelativeTo] = [
        "PAPER": .paper, "PAGE": .page, "COLUMN": .column,
        "PARA": .paragraph, "ABSOLUTE": .absolute,
    ]

    static let heightRelativeTos: [String: HwpCommonCtrlObjectHeightRelativeTo] = [
        "PAPER": .paper, "PAGE": .page, "ABSOLUTE": .absolute,
    ]

    static let verticalRelativeTos: [String: HwpCommonCtrlVerticalRelativeTo] = [
        "PAPER": .paper, "PAGE": .page, "PARA": .paragraph,
    ]

    static let horizontalRelativeTos: [String: HwpCommonCtrlHorizontalRelativeTo] = [
        "PAPER": .paper, "PAGE": .page, "COLUMN": .column, "PARA": .paragraph,
    ]

    static let alignments: [String: HwpCommonCtrlRelativeAlignment] = [
        "TOP": .topOrLeft, "LEFT": .topOrLeft, "CENTER": .center,
        "BOTTOM": .bottomOrRight, "RIGHT": .bottomOrRight,
        "INSIDE": .inside, "OUTSIDE": .outside,
    ]
}
