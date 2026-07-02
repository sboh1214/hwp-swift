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
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
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
                stroke: black,
                strokeWidth: 1
            )]
        case .table:
            var commands: [HwpPaintCommand] = [
                .strokeRect(rect: frame, color: black, width: 1),
            ]
            if let attributed = block.attributedString, attributed.length > 0 {
                commands.append(.drawText(
                    attributedString: attributed,
                    origin: frame.origin,
                    lineWidth: max(frame.width, 1)
                ))
            }
            return commands
        case .textbox:
            let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            var commands: [HwpPaintCommand] = [
                .fillRect(rect: frame, color: white),
                .strokeRect(rect: frame, color: black, width: 1),
            ]
            if let attributed = block.attributedString, attributed.length > 0 {
                commands.append(.drawText(
                    attributedString: attributed,
                    origin: frame.origin,
                    lineWidth: max(frame.width, 1)
                ))
            }
            return commands
        case .footnote:
            let separatorFrame = CGRect(
                x: frame.minX,
                y: frame.minY - 4,
                width: frame.width * 0.3,
                height: 1
            )
            let attributed = block.attributedString ?? NSAttributedString(string: "")
            return [
                .strokeRect(rect: separatorFrame, color: black, width: 1),
                .drawText(
                    attributedString: attributed,
                    origin: frame.origin,
                    lineWidth: max(frame.width, 1)
                ),
            ]
        case .placeholder:
            return [.drawPlaceholder(rect: frame, text: "[placeholder]")]
        }
    }
}
