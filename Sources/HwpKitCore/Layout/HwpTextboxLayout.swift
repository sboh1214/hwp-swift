import CoreGraphics
import CoreHwp
import Foundation

public struct HwpTextboxFrame: @unchecked Sendable, Hashable {
    /// 블록-로컬 좌표계 (origin 0,0)의 글상자 영역
    public let outerFrame: CGRect
    /// 글상자 안 문단 (텍스트 + 지오메트리 + paraId)
    public let paragraphs: [HwpLaidOutParagraph]
    public let borderColor: HwpRGBColor?
    public let borderWidth: CGFloat
    public let fillColor: HwpRGBColor?

    public init(
        outerFrame: CGRect,
        paragraphs: [HwpLaidOutParagraph],
        borderColor: HwpRGBColor?,
        borderWidth: CGFloat,
        fillColor: HwpRGBColor?
    ) {
        self.outerFrame = outerFrame
        self.paragraphs = paragraphs
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.fillColor = fillColor
    }

    /// 하위 호환: 문단 지오메트리만 필요할 때
    public var paragraphFrames: [HwpParagraphFrame] {
        paragraphs.map(\.frame)
    }
}

public struct HwpTextboxLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    /// gso 컨트롤의 글상자를 레이아웃한다.
    public func layout(
        textbox: CoreHwp.HwpGenShapeObject,
        width: CGFloat,
        index: HwpIndex
    ) -> HwpTextboxFrame? {
        layout(
            components: textbox.shapeComponentArray,
            commonProperty: textbox.commonCtrlProperty,
            fallbackWidth: width,
            index: index
        )
    }

    /// 글상자 리스트를 가진 첫 개체 요소를 찾아 레이아웃한다.
    /// 텍스트 wrap 폭은 개체 폭에서 글상자 텍스트 여백 (표 90)을 뺀 값이다.
    public func layout(
        components: [CoreHwp.HwpShapeComponent],
        commonProperty: CoreHwp.HwpCommonCtrlProperty,
        fallbackWidth: CGFloat,
        index: HwpIndex,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> HwpTextboxFrame? {
        guard let component = components.first(where: { !$0.textBoxListArray.isEmpty })
        else { return nil }

        let info = commonProperty.propertyInfo
        let outerWidth = HwpObjectSizeResolver.width(
            commonProperty.width,
            basis: info.widthRelativeTo,
            resolver: sizeResolver
        )
        let outerHeight = HwpObjectSizeResolver.height(
            commonProperty.height,
            basis: info.heightRelativeTo,
            resolver: sizeResolver
        )
        let resolvedWidth = outerWidth > 0 ? outerWidth : fallbackWidth

        let insets = textInsets(of: component)
        let wrapWidth = max(1, resolvedWidth - insets.left - insets.right)
        var paragraphs = laidOutParagraphs(
            of: component,
            insets: insets,
            wrapWidth: wrapWidth,
            index: index,
            sizeResolver: sizeResolver
        )

        let contentHeight = (paragraphs.last.map(\.rect.maxY) ?? insets.top) + insets.bottom
        let resolvedHeight = max(outerHeight, contentHeight)

        paragraphs = verticallyAligned(
            paragraphs,
            component: component,
            slack: max(0, resolvedHeight - contentHeight)
        )

        let appearance = appearance(of: component)

        return HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: resolvedWidth, height: max(0, resolvedHeight)),
            paragraphs: paragraphs,
            borderColor: appearance.borderColor,
            borderWidth: appearance.borderWidth,
            fillColor: appearance.fillColor
        )
    }

    /// 글상자 리스트의 문단들을 위에서 아래로 순차 배치한다 (블록-로컬 rect).
    private func laidOutParagraphs(
        of component: CoreHwp.HwpShapeComponent,
        insets: TextInsets,
        wrapWidth: CGFloat,
        index: HwpIndex,
        sizeResolver: HwpObjectSizeResolver?
    ) -> [HwpLaidOutParagraph] {
        // 글상자는 라인 캐시 높이를 쓰지 않는다 — CT 측정 그대로 (픽셀 정합)
        let measurer = HwpParagraphMeasurer(
            index: index,
            fontResolver: fontResolver,
            sizeResolver: sizeResolver
        )
        var paragraphs: [HwpLaidOutParagraph] = []
        var contentY = insets.top
        for list in component.textBoxListArray {
            for paragraph in list.paragraphArray {
                let measured = measurer.measure(paragraph, width: wrapWidth)
                paragraphs.append(HwpLaidOutParagraph(
                    attributedString: measured.attributed,
                    frame: measured.frame,
                    rect: CGRect(
                        x: insets.left,
                        y: contentY,
                        width: wrapWidth,
                        height: measured.frame.totalHeight
                    ),
                    paragraphId: paragraph.paraHeader.paraId,
                    hyperlinkURL: paragraph.hyperlinkURL
                ))
                contentY += measured.frame.totalHeight
            }
        }
        return paragraphs
    }

    /// 세로 정렬 (표 89 리스트 헤더 속성)에 따라 문단 rect를 아래로 민다.
    private func verticallyAligned(
        _ paragraphs: [HwpLaidOutParagraph],
        component: CoreHwp.HwpShapeComponent,
        slack: CGFloat
    ) -> [HwpLaidOutParagraph] {
        let alignment = component.textBoxListArray.first?
            .header.propertyInfo.verticalAlignment ?? .top
        let offset: CGFloat = switch alignment {
        case .top: 0
        case .center: slack / 2
        case .bottom: slack
        }
        guard offset > 0 else { return paragraphs }
        return paragraphs.map { paragraph in
            HwpLaidOutParagraph(
                attributedString: paragraph.attributedString,
                frame: paragraph.frame,
                rect: paragraph.rect.offsetBy(dx: 0, dy: offset),
                paragraphId: paragraph.paragraphId,
                hyperlinkURL: paragraph.hyperlinkURL
            )
        }
    }

    /// 글상자 텍스트 여백 (표 90). 정보가 없으면 0.
    private struct TextInsets {
        var left: CGFloat = 0
        var right: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    private func textInsets(of component: CoreHwp.HwpShapeComponent) -> TextInsets {
        guard let info = component.textBoxListArray.first?.textBoxInfo else {
            return TextInsets()
        }
        return TextInsets(
            left: max(0, HwpUnits.points(fromHwpUnit16: info.leftMargin)),
            right: max(0, HwpUnits.points(fromHwpUnit16: info.rightMargin)),
            top: max(0, HwpUnits.points(fromHwpUnit16: info.topMargin)),
            bottom: max(0, HwpUnits.points(fromHwpUnit16: info.bottomMargin))
        )
    }

    /// 개체 요소 세부에서 해석한 테두리/채우기 외형
    private struct Appearance {
        var borderColor: HwpRGBColor?
        var borderWidth: CGFloat = 0
        var fillColor: HwpRGBColor?
    }

    private func appearance(of component: CoreHwp.HwpShapeComponent) -> Appearance {
        var appearance = Appearance()
        guard let detail = component.detail else { return appearance }
        if let borderLine = detail.borderLine, borderLine.hasVisibleLine {
            appearance.borderColor = HwpRGBColor(borderLine.color)
            let width = HwpUnits.points(fromHwpUnit: borderLine.width)
            appearance.borderWidth = width > 0 ? width : 1
        }
        if let fill = detail.fill, fill.hasSolidFill,
           let background = fill.solidBackgroundColor
        {
            appearance.fillColor = HwpRGBColor(background)
        }
        return appearance
    }
}
