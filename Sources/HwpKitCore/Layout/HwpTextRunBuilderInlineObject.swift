import CoreGraphics
import CoreHwp
import Foundation

extension HwpTextRunBuilder {
    /// controlIndex번째 컨트롤이 treatAsChar 개체면 예약할 크기 (pt).
    func inlineObjectSize(
        controlIndex: Int,
        paragraph: CoreHwp.HwpParagraph
    ) -> CGSize? {
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

        var width = HwpUnits.points(fromHwpUnitU: commonProperty.width)
        var height = HwpUnits.points(fromHwpUnitU: commonProperty.height)
        if width <= 0 || height <= 0, let detail = components.first?.detail {
            if width <= 0 {
                width = HwpUnits.points(fromHwpUnitU: detail.currentWidth)
            }
            if height <= 0 {
                height = HwpUnits.points(fromHwpUnitU: detail.currentHeight)
            }
        }
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
