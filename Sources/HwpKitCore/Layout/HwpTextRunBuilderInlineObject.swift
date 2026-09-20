import CoreGraphics
import CoreHwp
import Foundation

extension HwpTextRunBuilder {
    /// treatAsChar 개체 마커의 줄 공간 예약 — 예약 크기와, 그 **폭**을 다른 단
    /// 기하로 다시 풀 열쇠 (`HwpInlineObjectReservation.rescaledForColumn`).
    struct InlineObjectReservation {
        let size: CGSize
        /// 마커에 실을 예약 폭 열쇠 — 폭이 단 폭에 딸린 기준일 때만 비어 있지 않다.
        let widthKeyAttributes: [NSAttributedString.Key: Any]
    }

    /// controlIndex번째 컨트롤이 treatAsChar 개체면 그 줄 공간 예약 (크기는 pt).
    ///
    /// 예약은 개체의 **바깥 상자**다 — 개체 크기에 바깥 여백(표 70)을 더한 것이 줄의 한
    /// 글자 폭·높이다 (#193, `HwpObjectAnchorGeometry.OuterMargins`). 개체는 그 안에서
    /// 왼쪽·위쪽 여백만큼 들어가 놓인다 (`HwpObjectAnchorGeometry.inlineObjectOrigin`).
    func inlineObjectReservation(
        controlIndex: Int,
        paragraph: CoreHwp.HwpParagraph
    ) -> InlineObjectReservation? {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.indices.contains(controlIndex),
              let (commonProperty, components) = Self.inlineObjectParts(of: ctrls[controlIndex]),
              let commonProperty, commonProperty.propertyInfo.treatAsChar
        else { return nil }

        let stored = HwpObjectSizeResolver.size(of: commonProperty, resolver: sizeResolver)
        var width = stored.width
        var height = stored.height
        let margins = HwpObjectAnchorGeometry.OuterMargins(commonProperty)
        // 저작 폭이 0이라 개체 요소 detail로 폴백하면 그 폭은 절대값(HWPUNIT)이므로
        // 단 폭에 딸리지 않는다 — 예약 폭 열쇠도 그때는 싣지 않는다.
        var widthKeyAttributes = HwpInlineObjectReservation.widthKeyAttributes(
            raw: commonProperty.width, basis: commonProperty.propertyInfo.widthRelativeTo,
            horizontalMargin: margins.horizontal
        )
        if width <= 0 || height <= 0, let detail = components.first?.detail {
            if width <= 0 {
                width = HwpUnits.points(fromHwpUnitU: detail.currentWidth)
                widthKeyAttributes = [:]
            }
            if height <= 0 {
                height = HwpUnits.points(fromHwpUnitU: detail.currentHeight)
            }
        }
        guard width > 0, height > 0 else { return nil }
        return InlineObjectReservation(
            size: CGSize(width: width + margins.horizontal, height: height + margins.vertical),
            widthKeyAttributes: widthKeyAttributes
        )
    }

    /// 줄 공간을 예약할 수 있는 컨트롤의 공통 속성과 개체 요소 — 개체가 아니면 nil.
    private static func inlineObjectParts(
        of ctrl: CoreHwp.HwpCtrlId
    ) -> (CoreHwp.HwpCommonCtrlProperty?, [CoreHwp.HwpShapeComponent])? {
        switch ctrl {
        case let .genShapeObject(genShape):
            (genShape.commonCtrlProperty, genShape.shapeComponentArray)
        case let .table(table):
            // 글자처럼 취급 표도 줄 공간을 예약한다 (noori 실측: 캐시 줄 높이
            // = 표 높이 + 위·아래 바깥 여백). 앵커 배치는 HwpPaginator.appendInlineAnchoredTable.
            (table.commonCtrlProperty, [])
        case let .shape(shape),
             let .line(shape),
             let .rectangle(shape),
             let .ellipse(shape),
             let .arc(shape),
             let .polygon(shape),
             let .curve(shape),
             let .equation(shape),
             let .equationLegacy(shape),
             let .picture(shape),
             let .ole(shape),
             let .container(shape):
            (shape.commonCtrlProperty, shape.shapeComponentArray)
        default:
            nil
        }
    }
}
