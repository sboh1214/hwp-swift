import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
import QuartzCore

public final class HwpPageLayer: CALayer, @unchecked Sendable {
    public var paintList: HwpPaintList? {
        didSet {
            setNeedsDisplay()
        }
    }

    public var pageHeight: CGFloat = 0

    override public init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override public init(layer: Any) {
        if let layer = layer as? HwpPageLayer {
            paintList = layer.paintList
            pageHeight = layer.pageHeight
        }
        super.init(layer: layer)
        needsDisplayOnBoundsChange = true
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func draw(in ctx: CGContext) {
        guard let paintList else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        for command in paintList.commands {
            switch command {
            case let .fillRect(rect, color):
                ctx.setFillColor(color)
                ctx.fill(rect)

            case let .strokeRect(rect, color, width):
                ctx.setStrokeColor(color)
                ctx.setLineWidth(width)
                ctx.stroke(rect)

            case let .drawText(attributedString, origin, lineWidth):
                drawText(attributedString, origin: origin, lineWidth: lineWidth, in: ctx)

            case let .drawPath(path, fill, stroke, strokeWidth):
                drawPath(path, fill: fill, stroke: stroke, strokeWidth: strokeWidth, in: ctx)

            case let .drawImage(image, rect):
                ctx.draw(image, in: rect)

            case let .drawPlaceholder(rect, text):
                drawPlaceholder(text, in: rect, context: ctx)

            case let .hyperlink(rect, _):
                ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)
            }
        }
    }

    private func drawText(
        _ attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat,
        in ctx: CGContext
    ) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            CGSize(width: lineWidth, height: .greatestFiniteMagnitude),
            nil
        )
        let textHeight = max(ceil(suggestedSize.height), 1)
        let effectivePageHeight = pageHeight > 0 ? pageHeight : bounds.height
        let textRect = CGRect(
            x: origin.x,
            y: effectivePageHeight - origin.y - textHeight,
            width: lineWidth,
            height: textHeight
        )
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
        )

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: effectivePageHeight)
        ctx.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    private func drawPath(
        _ path: CGPath,
        fill: CGColor?,
        stroke: CGColor?,
        strokeWidth: CGFloat,
        in ctx: CGContext
    ) {
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }

        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(strokeWidth)
            ctx.strokePath()
        }
    }

    private func drawPlaceholder(_ text: String, in rect: CGRect, context ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(rect)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: CGColor(gray: 0, alpha: 1),
            .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            rect.size,
            nil
        )
        let origin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        drawText(attributedString, origin: origin, lineWidth: max(textSize.width, 1), in: ctx)
    }
}
