import Foundation

/// 개체 공통 속성 — `hp:sz`/`hp:pos`/`hp:outMargin`과 개체 요소 자체의
/// 배치 속성(textWrap 등)을 `HwpCommonCtrlProperty`로 옮긴다.
///
/// **textWrap은 HWPX 전용 6값 매핑이다** — 바이너리 HWP5의 실측 4값 매핑
/// (`HwpCommonCtrlTextWrap` 주석의 #1 예고)과 달리 이름 붙은 값이 오며,
/// HWP5 모델에 없는 THROUGH/TIGHT는 어울림(square)으로 근사한다.
enum HwpxObjectCommonMapper {
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
            // 오프셋은 음수가 정상값이다 (기준 위·왼쪽으로 밀린 개체) —
            // UInt32로 읽으면 파싱이 실패해 0으로 접혀 개체가 기준 원점으로
            // 이동한다. 하류가 Int32(bitPattern:)로 되읽으므로 비트열을 보존한다.
            property.verticalOffset = HWPUNIT(
                bitPattern: position.int32Attribute("vertOffset", default: 0)
            )
            property.horizontalOffset = HWPUNIT(
                bitPattern: position.int32Attribute("horzOffset", default: 0)
            )
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

        property.propertyInfo = info
        property.zOrder = node.int32Attribute("zOrder", default: 0)
        property.instanceId = node.uint32Attribute("id", default: 0)
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
