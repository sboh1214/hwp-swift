import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

public struct HwpTextboxFrame: Sendable {
    public let outerFrame: CGRect
    public let paragraphFrames: [HwpParagraphFrame]
    public let borderColor: CGColor?
    public let borderWidth: CGFloat
    public let fillColor: CGColor?

    public init(
        outerFrame: CGRect,
        paragraphFrames: [HwpParagraphFrame],
        borderColor: CGColor?,
        borderWidth: CGFloat,
        fillColor: CGColor?
    ) {
        self.outerFrame = outerFrame
        self.paragraphFrames = paragraphFrames
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.fillColor = fillColor
    }
}

extension HwpTextboxFrame: Hashable {
    public static func == (lhs: HwpTextboxFrame, rhs: HwpTextboxFrame) -> Bool {
        lhs.outerFrame == rhs.outerFrame
            && lhs.paragraphFrames == rhs.paragraphFrames
            && lhs.borderWidth == rhs.borderWidth
            && colorComponentsEqual(lhs.borderColor, rhs.borderColor)
            && colorComponentsEqual(lhs.fillColor, rhs.fillColor)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(outerFrame.origin.x)
        hasher.combine(outerFrame.origin.y)
        hasher.combine(outerFrame.size.width)
        hasher.combine(outerFrame.size.height)
        hasher.combine(paragraphFrames)
        hasher.combine(borderWidth)
        borderColor?.components?.forEach { hasher.combine($0) }
        fillColor?.components?.forEach { hasher.combine($0) }
    }

    private static func colorComponentsEqual(_ lhs: CGColor?, _ rhs: CGColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.components == right.components
        default: false
        }
    }
}

public struct HwpTextboxLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public func layout(
        textbox: CoreHwp.HwpGenShapeObject,
        width: CGFloat,
        index: HwpIndex
    ) -> HwpTextboxFrame? {
        guard let component = textbox.shapeComponentArray.first(where: { !$0.textBoxListArray.isEmpty })
        else {
            return nil
        }

        let outerWidth = HwpUnits.points(fromHwpUnitU: textbox.commonCtrlProperty.width)
        let outerHeight = HwpUnits.points(fromHwpUnitU: textbox.commonCtrlProperty.height)
        let resolvedWidth = outerWidth > 0 ? outerWidth : width
        let outerFrame = CGRect(x: 0, y: 0, width: resolvedWidth, height: max(0, outerHeight))

        let textRunBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout(fontResolver: fontResolver)
        var paragraphFrames: [HwpParagraphFrame] = []

        for list in component.textBoxListArray {
            for paragraph in list.paragraphArray {
                let attributed = textRunBuilder.build(paragraph: paragraph)
                let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
                    ?? CoreHwp.HwpParaShape()
                paragraphFrames.append(
                    paragraphLayout.layout(
                        attributedString: attributed,
                        paraShape: paraShape,
                        columnWidth: width
                    )
                )
            }
        }

        return HwpTextboxFrame(
            outerFrame: outerFrame,
            paragraphFrames: paragraphFrames,
            borderColor: nil,
            borderWidth: 0,
            fillColor: nil
        )
    }
}
