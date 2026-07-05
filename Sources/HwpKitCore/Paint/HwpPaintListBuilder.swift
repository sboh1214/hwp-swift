@preconcurrency import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

public struct HwpPaintListBuilder: Sendable {
    private let fontResolver: HwpFontResolver
    private let imageStore: HwpImageStore

    public init(
        fontResolver: HwpFontResolver = HwpFontResolver(),
        imageStore: HwpImageStore = HwpImageStore()
    ) {
        self.fontResolver = fontResolver
        self.imageStore = imageStore
    }

    public func build(for page: HwpPage, index _: HwpIndex) -> HwpPaintList {
        var commands: [HwpPaintCommand] = []
        var didDrawFootnoteSeparator = false
        for block in page.blocks {
            if case let .footnote(footnote) = block.payload {
                commands.append(contentsOf: footnoteCommands(
                    footnote,
                    blockFrame: block.frame,
                    drawSeparator: !didDrawFootnoteSeparator
                ))
                didDrawFootnoteSeparator = true
            } else {
                commands.append(contentsOf: paintCommands(for: block))
            }
            if let url = block.hyperlinkURL {
                commands.append(.hyperlink(rect: block.frame, url: url))
            }
        }
        return HwpPaintList(commands: commands)
    }

    private func paintCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        switch block.payload {
        case let .table(tableFrame):
            return tableCommands(tableFrame, origin: block.frame.origin)
        case let .textbox(textboxFrame):
            return textboxCommands(textboxFrame, origin: block.frame.origin)
        case let .footnote(footnoteBlock):
            return footnoteCommands(footnoteBlock, blockFrame: block.frame, drawSeparator: true)
        case let .shape(geometry):
            return shapeCommands(geometry, origin: block.frame.origin)
        case let .image(imageInfo):
            return imageCommands(imageInfo, frame: block.frame)
        case nil:
            return plainCommands(for: block)
        }
    }

    private func plainCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        let frame = block.frame
        switch block.kind {
        case .text, .table, .textbox, .footnote:
            guard let attributed = block.attributedString, attributed.length > 0 else {
                return []
            }
            return [.drawText(
                attributedString: attributed,
                origin: frame.origin,
                lineWidth: max(frame.width, 1)
            )]
        case .image:
            return [.drawPlaceholder(rect: frame, text: "[이미지]")]
        case .shape:
            return [.drawPath(
                path: CGPath(rect: frame, transform: nil),
                fill: nil,
                stroke: .hwpBlack,
                strokeWidth: 1
            )]
        case .placeholder:
            return [.drawPlaceholder(
                rect: frame,
                text: block.attributedString?.string ?? "[placeholder]"
            )]
        }
    }

    // MARK: - 표

    private func tableCommands(
        _ table: HwpTableFrame,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        for row in table.rows {
            for cell in row.cells {
                let cellRect = cell.cellFrame.offsetBy(dx: origin.x, dy: origin.y)
                if let fill = cell.fillColor {
                    commands.append(.fillRect(rect: cellRect, color: fill.cgColor))
                }
                commands.append(contentsOf: borderCommands(cell.borders, around: cellRect))
                for paragraph in cell.paragraphs where paragraph.attributedString.length > 0 {
                    let paragraphRect = paragraph.rect.offsetBy(dx: origin.x, dy: origin.y)
                    commands.append(.drawText(
                        attributedString: paragraph.attributedString,
                        origin: paragraphRect.origin,
                        lineWidth: max(paragraphRect.width, 1)
                    ))
                }
            }
        }
        return commands
    }

    private func borderCommands(
        _ borders: HwpBorderSet,
        around rect: CGRect
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        func edge(_ width: CGFloat, _ color: HwpRGBColor, _ edgeRect: CGRect) {
            guard width > 0 else { return }
            commands.append(.fillRect(rect: edgeRect, color: color.cgColor))
        }
        edge(borders.top, borders.topColor, CGRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: borders.top
        ))
        edge(borders.bottom, borders.bottomColor, CGRect(
            x: rect.minX, y: rect.maxY - borders.bottom, width: rect.width, height: borders.bottom
        ))
        edge(borders.left, borders.leftColor, CGRect(
            x: rect.minX, y: rect.minY, width: borders.left, height: rect.height
        ))
        edge(borders.right, borders.rightColor, CGRect(
            x: rect.maxX - borders.right, y: rect.minY, width: borders.right, height: rect.height
        ))
        return commands
    }

    // MARK: - 글상자

    private func textboxCommands(
        _ textbox: HwpTextboxFrame,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        let outerRect = textbox.outerFrame.offsetBy(dx: origin.x, dy: origin.y)
        if let fill = textbox.fillColor {
            commands.append(.fillRect(rect: outerRect, color: fill.cgColor))
        } else {
            commands.append(.fillRect(rect: outerRect, color: .hwpWhite))
        }
        if let borderColor = textbox.borderColor, textbox.borderWidth > 0 {
            commands.append(.strokeRect(
                rect: outerRect,
                color: borderColor.cgColor,
                width: textbox.borderWidth
            ))
        } else {
            commands.append(.strokeRect(rect: outerRect, color: .hwpBlack, width: 1))
        }
        for paragraph in textbox.paragraphs where paragraph.attributedString.length > 0 {
            let paragraphRect = paragraph.rect.offsetBy(dx: origin.x, dy: origin.y)
            commands.append(.drawText(
                attributedString: paragraph.attributedString,
                origin: paragraphRect.origin,
                lineWidth: max(paragraphRect.width, 1)
            ))
        }
        return commands
    }

    // MARK: - 각주

    private func footnoteCommands(
        _ footnote: HwpFootnoteBlock,
        blockFrame: CGRect,
        drawSeparator: Bool
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        // 구분선은 페이지의 첫 번째 각주 블록에서 한 번만 그린다.
        if drawSeparator {
            commands.append(.fillRect(
                rect: footnote.separatorLine,
                color: footnote.separatorColor.cgColor
            ))
        }
        for paragraph in footnote.paragraphs where paragraph.attributedString.length > 0 {
            let paragraphRect = paragraph.rect.offsetBy(
                dx: blockFrame.minX,
                dy: blockFrame.minY
            )
            commands.append(.drawText(
                attributedString: paragraph.attributedString,
                origin: paragraphRect.origin,
                lineWidth: max(paragraphRect.width, 1)
            ))
        }
        return commands
    }

    // MARK: - 도형

    private func shapeCommands(
        _ geometry: HwpShapeGeometry,
        origin: CGPoint
    ) -> [HwpPaintCommand] {
        var transform = CGAffineTransform(translationX: origin.x, y: origin.y)
        let translated = geometry.path.copy(using: &transform) ?? geometry.path
        return [.drawPath(
            path: translated,
            fill: geometry.fillColor,
            stroke: geometry.strokeColor,
            strokeWidth: geometry.strokeWidth
        )]
    }

    // MARK: - 이미지

    private func imageCommands(
        _ image: HwpImageBlockInfo,
        frame: CGRect
    ) -> [HwpPaintCommand] {
        guard imageStore.data(forBinItemId: image.binItemId) != nil else {
            return [.drawPlaceholder(rect: frame, text: "[이미지]")]
        }
        var commands: [HwpPaintCommand] = [
            .drawImageReference(binItemId: image.binItemId, rect: frame),
        ]
        if let borderColor = image.borderColor, image.borderWidth > 0 {
            commands.append(.strokeRect(
                rect: frame,
                color: borderColor.cgColor,
                width: image.borderWidth
            ))
        }
        return commands
    }
}
