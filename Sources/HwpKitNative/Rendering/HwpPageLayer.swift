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

    /// `.drawImageReference` 명령을 해석할 이미지 공급자.
    /// 디코딩이 끝나면 레이어를 다시 그린다.
    public var imageProvider: HwpPageImageProvider? {
        didSet {
            setNeedsDisplay()
        }
    }

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

        #if os(macOS)
            // macOS의 layer 컨텍스트는 기본 bottom-left(y-up)다. 조상 계층의
            // geometry flip 횟수가 홀수면 (예: isFlipped NSView 안) CA가 이미
            // top-down으로 보정해 준다. paint 명령은 top-left 기준이므로
            // 보정이 없을 때만 직접 뒤집는다. 레이어 자체에 isGeometryFlipped를
            // 켜지 않는 이유: flipped 뷰 안에서 이중 flip이 되어 상하 반전된다.
            if !contentsAreFlipped() {
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
        #endif

        for command in paintList.commands {
            execute(command, in: ctx)
        }
    }

    private func execute(_ command: HwpPaintCommand, in ctx: CGContext) {
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
            drawFlippedImage(image, in: rect, context: ctx)

        case let .drawImageReference(binItemId, rect, style):
            drawImageReference(binItemId, style: style, in: rect, context: ctx)

        case let .drawPlaceholder(rect, text):
            drawPlaceholder(text, in: rect, context: ctx)

        case .hyperlink:
            // 시각 표시 없음 (한글.app: 하이퍼링크는 글자 장식만) —
            // rect는 히트 테스트용으로만 유지된다
            break
        }
    }

    private func drawText(
        _ attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat,
        in ctx: CGContext
    ) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        drawFrame(
            framesetter: framesetter,
            attributedString: attributedString,
            origin: origin,
            lineWidth: lineWidth,
            in: ctx
        )
    }

    private func drawFrame(
        framesetter: CTFramesetter,
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat,
        in ctx: CGContext
    ) {
        let length = attributedString.length
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: length),
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
            CFRange(location: 0, length: length),
            path,
            nil
        )

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: effectivePageHeight)
        ctx.scaleBy(x: 1, y: -1)
        drawFrameLines(frame, attributedString: attributedString, textRect: textRect, in: ctx)
        ctx.restoreGState()
    }

    /// 프레임의 줄을 직접 그린다. 양쪽 정렬 줄은 한글처럼 남는 폭을 공백에만
    /// 배분해 다시 조판하고 (`wordJustifiedLine`), 그 외에는 CT 조판 그대로.
    private func drawFrameLines(
        _ frame: CTFrame,
        attributedString: NSAttributedString,
        textRect: CGRect,
        in ctx: CGContext
    ) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (index, line) in lines.enumerated() {
            let lineOrigin = CGPoint(
                x: textRect.minX + origins[index].x,
                y: textRect.minY + origins[index].y + Self.baselineLift(of: line)
            )
            ctx.textPosition = lineOrigin
            let replacement = HwpWordJustification.wordJustifiedLine(
                frameLine: line,
                attributedString: attributedString,
                availableWidth: textRect.width - origins[index].x
            )
            drawDecoratedLine(replacement ?? line, origin: lineOrigin, in: ctx)
        }
    }

    /// 한글 줄 모델의 베이스라인은 글자 크기의 ~0.85배 지점이다 (HCR 폰트의
    /// CT ascent 1.07em보다 높음 — plain-text 실물 실측: 첫 줄 잉크가 1.1mm
    /// 위). CT ascent와의 차이만큼 줄을 위로 올린다 (y-up 공간에서 +y).
    static func baselineLift(of line: CTLine) -> CGFloat {
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        var maxSize: CGFloat = 0
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                if let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
                   CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                {
                    // swiftlint:disable:next force_cast
                    maxSize = max(maxSize, CTFontGetSize(value as! CTFont))
                }
            }
        }
        guard maxSize > 0 else { return 0 }
        return max(0, ascent - maxSize * 0.85)
    }

    /// paint list가 해당 BinItem 이미지를 참조하는지 (targeted redraw 판단용)
    public func containsImageReference(_ binItemId: UInt32) -> Bool {
        guard let paintList else { return false }
        return paintList.commands.contains { command in
            if case let .drawImageReference(key, _, _) = command {
                return key == binItemId
            }
            return false
        }
    }

    /// 컨텍스트가 top-left 기준으로 뒤집혀 있으므로 이미지는 rect 기준으로 재반전해 그린다.
    private func drawFlippedImage(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    private func drawImageReference(
        _ binItemId: UInt32,
        style: HwpImageRenderStyle?,
        in rect: CGRect,
        context ctx: CGContext
    ) {
        guard let imageProvider else {
            drawPlaceholder("[이미지]", in: rect, context: ctx)
            return
        }
        if let image = imageProvider.cachedImage(for: binItemId, style: style) {
            drawFlippedImage(image, in: rect, context: ctx)
            return
        }
        if imageProvider.didFail(for: binItemId, style: style) {
            drawPlaceholder("[이미지]", in: rect, context: ctx)
            return
        }
        // 로딩 중 표시 후 비동기 디코딩을 트리거한다.
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(rect)
        imageProvider.requestImage(for: binItemId, style: style)
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

    private static let placeholderFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func drawPlaceholder(_ text: String, in rect: CGRect, context ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(rect)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: CGColor(gray: 0, alpha: 1),
            .font: Self.placeholderFont,
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
        drawFrame(
            framesetter: framesetter,
            attributedString: attributedString,
            origin: origin,
            lineWidth: max(textSize.width, 1),
            in: ctx
        )
    }
}
