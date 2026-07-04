@preconcurrency import CoreGraphics
@preconcurrency import CoreHwp
import Foundation

public struct HwpPaintListBuilder: Sendable {
    private let fontResolver: HwpFontResolver

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        self.fontResolver = fontResolver
    }

    public func build(for page: HwpPage, index _: HwpIndex) -> HwpPaintList {
        var commands: [HwpPaintCommand] = []
        for block in page.blocks {
            commands.append(contentsOf: paintCommands(for: block))
            if let url = block.hyperlinkURL {
                commands.append(.hyperlink(rect: block.frame, url: url))
            }
        }
        return HwpPaintList(commands: commands)
    }

    private func paintCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        let frame = block.frame
        switch block.kind {
        case .text:
            let attributed = block.attributedString ?? NSAttributedString(string: "")
            return [.drawText(
                attributedString: attributed,
                origin: frame.origin,
                lineWidth: frame.width
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
        case .table:
            return tableCommands(for: block, frame: frame)
        case .textbox:
            return textboxCommands(for: block, frame: frame)
        case .footnote:
            return footnoteCommands(for: block, frame: frame)
        case .placeholder:
            return [.drawPlaceholder(rect: frame, text: "[placeholder]")]
        }
    }

    private func tableCommands(for block: AnyHwpBlock, frame: CGRect) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = [
            .strokeRect(rect: frame, color: .hwpBlack, width: 1),
        ]
        if let text = textCommand(for: block, frame: frame) {
            commands.append(text)
        }
        return commands
    }

    private func textboxCommands(for block: AnyHwpBlock, frame: CGRect) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = [
            .fillRect(rect: frame, color: .hwpWhite),
            .strokeRect(rect: frame, color: .hwpBlack, width: 1),
        ]
        if let text = textCommand(for: block, frame: frame) {
            commands.append(text)
        }
        return commands
    }

    private func footnoteCommands(for block: AnyHwpBlock, frame: CGRect) -> [HwpPaintCommand] {
        let separatorFrame = CGRect(
            x: frame.minX,
            y: frame.minY - 4,
            width: frame.width * 0.3,
            height: 1
        )
        let attributed = block.attributedString ?? NSAttributedString(string: "")
        return [
            .strokeRect(rect: separatorFrame, color: .hwpBlack, width: 1),
            .drawText(
                attributedString: attributed,
                origin: frame.origin,
                lineWidth: max(frame.width, 1)
            ),
        ]
    }

    private func textCommand(for block: AnyHwpBlock, frame: CGRect) -> HwpPaintCommand? {
        guard let attributed = block.attributedString, attributed.length > 0 else {
            return nil
        }
        return .drawText(
            attributedString: attributed,
            origin: frame.origin,
            lineWidth: max(frame.width, 1)
        )
    }
}
