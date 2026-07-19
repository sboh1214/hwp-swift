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
            imageProvider = layer.imageProvider
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
        #else
            // iOS: CA가 주는 인앱 레이어 컨텍스트는 이미 top-down (CTM d < 0)
            // 이지만, 테스트·오프스크린 렌더의 원시 bitmap 컨텍스트는 y-up
            // (d > 0)이다. CTM 방향으로 판별해 y-up일 때만 뒤집는다 —
            // 인앱 경로는 불변.
            if ctx.ctm.d > 0 {
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

    /// 줄 배치는 `HwpDrawnTextLayout` (렌더·텍스트 선택 공유 — slight-overflow
    /// 단일 줄, 양쪽 정렬 재조판, baselineLift 포함)이 계산하고, 여기서는
    /// top-down 결과를 이 레이어의 y-up 텍스트 공간으로 변환해 그리기만 한다.
    private func drawText(
        _ attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat,
        in ctx: CGContext
    ) {
        let drawnLines = HwpDrawnTextLayout.lines(
            attributedString: attributedString,
            origin: origin,
            lineWidth: lineWidth
        )
        guard !drawnLines.isEmpty else { return }
        let effectivePageHeight = pageHeight > 0 ? pageHeight : bounds.height
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: effectivePageHeight)
        ctx.scaleBy(x: 1, y: -1)
        for drawnLine in drawnLines {
            let lineOrigin = CGPoint(
                x: drawnLine.baselineOrigin.x,
                y: effectivePageHeight - drawnLine.baselineOrigin.y
            )
            ctx.textPosition = lineOrigin
            drawDecoratedLine(drawnLine.line, origin: lineOrigin, in: ctx)
        }
        ctx.restoreGState()
    }

    /// paint list가 해당 BinItem 이미지를 참조하는지 (targeted redraw 판단용)
    public func containsImageReference(_ binItemId: UInt32) -> Bool {
        guard let paintList else { return false }
        return paintList.commands.contains {
            if case let .drawImageReference(key, _, _) = $0 {
                key == binItemId
            } else {
                false
            }
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
        drawText(
            attributedString,
            origin: origin,
            lineWidth: max(textSize.width, 1),
            in: ctx
        )
    }
}
