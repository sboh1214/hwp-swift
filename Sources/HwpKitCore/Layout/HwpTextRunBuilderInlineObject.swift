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
    func inlineObjectReservation(
        controlIndex: Int,
        paragraph: CoreHwp.HwpParagraph
    ) -> InlineObjectReservation? {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.indices.contains(controlIndex)
        else { return nil }

        let commonProperty: CoreHwp.HwpCommonCtrlProperty?
        let components: [CoreHwp.HwpShapeComponent]
        switch ctrls[controlIndex] {
        case let .genShapeObject(genShape):
            commonProperty = genShape.commonCtrlProperty
            components = genShape.shapeComponentArray
        case let .table(table):
            // 글자처럼 취급 표도 줄 공간을 예약한다 (noori 실측: 캐시 줄 높이
            // = 표 높이). 앵커 배치는 HwpPaginator.appendInlineAnchoredTable.
            commonProperty = table.commonCtrlProperty
            components = []
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
            commonProperty = shape.commonCtrlProperty
            components = shape.shapeComponentArray
        default:
            return nil
        }
        guard let commonProperty, commonProperty.propertyInfo.treatAsChar else { return nil }

        let stored = HwpObjectSizeResolver.size(of: commonProperty, resolver: sizeResolver)
        var width = stored.width
        var height = stored.height
        // 저작 폭이 0이라 개체 요소 detail로 폴백하면 그 폭은 절대값(HWPUNIT)이므로
        // 단 폭에 딸리지 않는다 — 예약 폭 열쇠도 그때는 싣지 않는다.
        var widthKeyAttributes = HwpInlineObjectReservation.widthKeyAttributes(
            raw: commonProperty.width, basis: commonProperty.propertyInfo.widthRelativeTo
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
            size: CGSize(width: width, height: height),
            widthKeyAttributes: widthKeyAttributes
        )
    }
}
