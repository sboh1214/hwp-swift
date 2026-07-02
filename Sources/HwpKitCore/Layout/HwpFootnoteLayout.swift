import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

public struct HwpFootnoteBlock: Sendable, Hashable {
    public let frame: CGRect
    public let paragraphFrames: [HwpParagraphFrame]
    public let number: Int
    public let separatorLine: CGRect

    public init(
        frame: CGRect,
        paragraphFrames: [HwpParagraphFrame],
        number: Int,
        separatorLine: CGRect
    ) {
        self.frame = frame
        self.paragraphFrames = paragraphFrames
        self.number = number
        self.separatorLine = separatorLine
    }

    public static func == (lhs: HwpFootnoteBlock, rhs: HwpFootnoteBlock) -> Bool {
        lhs.number == rhs.number
            && lhs.paragraphFrames == rhs.paragraphFrames
            && lhs.frame.minX == rhs.frame.minX
            && lhs.frame.minY == rhs.frame.minY
            && lhs.frame.width == rhs.frame.width
            && lhs.frame.height == rhs.frame.height
            && lhs.separatorLine.minX == rhs.separatorLine.minX
            && lhs.separatorLine.minY == rhs.separatorLine.minY
            && lhs.separatorLine.width == rhs.separatorLine.width
            && lhs.separatorLine.height == rhs.separatorLine.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
        hasher.combine(paragraphFrames)
        hasher.combine(frame.minX)
        hasher.combine(frame.minY)
        hasher.combine(frame.width)
        hasher.combine(frame.height)
        hasher.combine(separatorLine.minX)
        hasher.combine(separatorLine.minY)
        hasher.combine(separatorLine.width)
        hasher.combine(separatorLine.height)
    }
}

public struct HwpFootnoteLayout {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public func layout(
        footnotes: [CoreHwp.HwpParagraph],
        onPage geometry: HwpPageGeometry,
        index: HwpIndex
    ) -> [HwpFootnoteBlock] {
        guard !footnotes.isEmpty else { return [] }

        let contentFrame = geometry.contentFrame
        let reservedHeight = contentFrame.height * 0.3
        let reservedTop = contentFrame.maxY - reservedHeight
        let columnWidth = contentFrame.width

        let textRunBuilder = HwpTextRunBuilder(index: index, fontResolver: fontResolver)
        let paragraphLayout = HwpParagraphLayout(fontResolver: fontResolver)

        let firstFootnoteY = reservedTop
        let separatorLine = CGRect(
            x: contentFrame.minX,
            y: firstFootnoteY - 4,
            width: contentFrame.width * 0.3,
            height: 1
        )

        var blocks: [HwpFootnoteBlock] = []
        var cumulativeHeight: CGFloat = 0

        let defaultParaShape = index.paraShapes[0] ?? index.paraShapes.values.first

        for (footnoteIdx, paragraph) in footnotes.enumerated() {
            let attributed = textRunBuilder.build(paragraph: paragraph)
            let paraFrame: HwpParagraphFrame = if let shape = defaultParaShape {
                paragraphLayout.layout(
                    attributedString: attributed,
                    paraShape: shape,
                    columnWidth: columnWidth
                )
            } else {
                HwpParagraphFrame(totalHeight: 0, lines: [])
            }

            let blockHeight = max(paraFrame.totalHeight, 1)
            guard cumulativeHeight + blockHeight <= reservedHeight else { break }

            let blockY = firstFootnoteY + cumulativeHeight
            blocks.append(HwpFootnoteBlock(
                frame: CGRect(x: contentFrame.minX, y: blockY, width: columnWidth, height: blockHeight),
                paragraphFrames: [paraFrame],
                number: footnoteIdx + 1,
                separatorLine: separatorLine
            ))
            cumulativeHeight += blockHeight
        }

        return blocks
    }
}
