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
        }
        return HwpPaintList(commands: commands)
    }

    private func paintCommands(for block: AnyHwpBlock) -> [HwpPaintCommand] {
        let frame = block.frame
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        switch block.kind {
        case .text:
            return [.drawText(
                attributedString: NSAttributedString(string: ""),
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
            return [.strokeRect(rect: frame, color: black, width: 1)]
        case .textbox:
            let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            return [
                .fillRect(rect: frame, color: white),
                .strokeRect(rect: frame, color: black, width: 1),
            ]
        case .footnote:
            let separatorFrame = CGRect(
                x: frame.minX,
                y: frame.minY - 4,
                width: frame.width * 0.3,
                height: 1
            )
            return [
                .strokeRect(rect: separatorFrame, color: black, width: 1),
                .drawText(
                    attributedString: NSAttributedString(string: ""),
                    origin: frame.origin,
                    lineWidth: frame.width
                ),
            ]
        case .placeholder:
            return [.drawPlaceholder(rect: frame, text: "[placeholder]")]
        }
    }
}
