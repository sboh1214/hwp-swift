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
                y: textRect.minY + origins[index].y
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

// MARK: - 글자 장식 (CT 미지원: 음영 배경/그림자/취소선, CTRunDraw 경로 밑줄)

private extension HwpPageLayer {
    /// 줄 하나를 run 단위로 그린다: 음영 배경 → 글리프 (그림자/양각 포함) →
    /// 취소선/강조점. 밑줄은 CTLineDraw가 그리므로 그림자·양각이 없으면
    /// CTLineDraw 유지.
    func drawDecoratedLine(_ line: CTLine, origin: CGPoint, in ctx: CGContext) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], !runs.isEmpty else { return }

        for run in runs {
            drawShadeIfNeeded(run, lineOrigin: origin, in: ctx)
        }

        let needsPerRunDrawing = runs.contains { run in
            let attributes = runAttributes(run)
            return attributes[HwpAttributedStringKey.shadowColor] != nil
                || attributes[HwpAttributedStringKey.reliefStyle] != nil
        }
        if needsPerRunDrawing {
            for run in runs {
                drawRun(run, origin: origin, in: ctx)
            }
            // CTRunDraw는 밑줄을 그리지 않으므로 직접 보완한다
            for run in runs {
                drawUnderlineIfNeeded(run, lineOrigin: origin, in: ctx)
            }
        } else {
            CTLineDraw(line, ctx)
        }

        for run in runs {
            drawStrikethroughIfNeeded(run, lineOrigin: origin, in: ctx)
            drawEmphasisIfNeeded(run, lineOrigin: origin, in: ctx)
        }
    }

    func runAttributes(_ run: CTRun) -> [NSAttributedString.Key: Any] {
        CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
    }

    /// 음영 배경 (글리프보다 먼저)
    func drawShadeIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        guard let shade = runAttributes(run)[HwpAttributedStringKey.shadeColor] else { return }
        ctx.setFillColor(shade as! CGColor) // swiftlint:disable:this force_cast
        ctx.fill(runBounds(of: run, lineOrigin: lineOrigin))
    }

    /// run 하나를 그림자/양각 설정과 함께 그린다
    func drawRun(_ run: CTRun, origin: CGPoint, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let attributes = runAttributes(run)
        if let reliefStyle = (attributes[HwpAttributedStringKey.reliefStyle] as? NSNumber)?
            .intValue
        {
            drawReliefRun(run, style: reliefStyle, attributes: attributes, origin: origin, in: ctx)
            return
        }
        if let shadowColor = attributes[HwpAttributedStringKey.shadowColor] {
            let offsetX = (attributes[HwpAttributedStringKey.shadowOffsetX] as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            let offsetY = (attributes[HwpAttributedStringKey.shadowOffsetY] as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            // 텍스트 공간은 y-up으로 뒤집혀 있으므로 아래(+dy)는 -y
            ctx.setShadow(
                offset: CGSize(width: offsetX, height: -offsetY),
                blur: 0,
                color: (shadowColor as! CGColor) // swiftlint:disable:this force_cast
            )
        }
        ctx.textPosition = origin
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
    }

    /// 양각 (1)/음각 (2): 밝은/어두운 오프셋 사본 뒤 원래 색 글리프.
    /// run은 kCTForegroundColorFromContext라 컨텍스트 fill 색으로 그려진다.
    func drawReliefRun(
        _ run: CTRun,
        style: Int,
        attributes: [NSAttributedString.Key: Any],
        origin: CGPoint,
        in ctx: CGContext
    ) {
        let highlight = CGColor(gray: 1, alpha: 1)
        let dark = CGColor(gray: 0.45, alpha: 1)
        // 양각: 밝음 왼쪽 위 / 어두움 오른쪽 아래. 음각: 반대.
        // 텍스트 공간은 y-up이므로 시각적 위 = +y.
        let first = style == 1 ? highlight : dark
        let second = style == 1 ? dark : highlight
        ctx.setFillColor(first)
        ctx.textPosition = CGPoint(x: origin.x - 0.5, y: origin.y + 0.5)
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
        ctx.setFillColor(second)
        ctx.textPosition = CGPoint(x: origin.x + 0.5, y: origin.y - 0.5)
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
        let face = attributes[HwpAttributedStringKey.reliefFaceColor]
        setDecorationFillColor(face, in: ctx)
        ctx.textPosition = origin
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
    }

    /// 강조점: 글리프 위 가운데 작은 점 (공백 폭 글리프는 건너뜀)
    func drawEmphasisIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.emphasisMark] != nil else { return }
        let glyphCount = CTRunGetGlyphCount(run)
        guard glyphCount > 0 else { return }
        var positions = [CGPoint](repeating: .zero, count: glyphCount)
        var advances = [CGSize](repeating: .zero, count: glyphCount)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTRunGetTypographicBounds(
            run, CFRange(location: 0, length: 0), &ascent, &descent, &leading
        )
        let color = attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        setDecorationFillColor(color, in: ctx)
        let radius: CGFloat = max(0.6, ascent * 0.07)
        for index in 0 ..< glyphCount {
            let advance = advances[index].width
            // 공백류 (잉크 없는 넓은 advance 단독 글리프)는 근사적으로 건너뛴다:
            // CT 공백 글리프는 폭만 있고, 한글.app도 공백엔 강조점을 찍지 않는다.
            guard advance > 0.1 else { continue }
            let bounds = CTRunGetImageBounds(
                run, nil, CFRange(location: index, length: 1)
            )
            guard !bounds.isNull, bounds.width > 0.1 else { continue }
            let centerX = lineOrigin.x + positions[index].x + advance / 2
            let dotY = lineOrigin.y + ascent + radius + 0.5
            ctx.fillEllipse(in: CGRect(
                x: centerX - radius, y: dotY - radius,
                width: radius * 2, height: radius * 2
            ))
        }
    }

    /// 취소선 (CT 미지원 — 항상 직접)
    func drawStrikethroughIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[.strikethroughStyle] != nil else { return }
        let color = attributes[HwpAttributedStringKey.strikethroughColor]
            ?? attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        let xHeight = runFont(attributes).map(CTFontGetXHeight) ?? bounds.height * 0.4
        setDecorationFillColor(color, in: ctx)
        ctx.fill(CGRect(
            x: bounds.minX,
            y: lineOrigin.y + xHeight / 2,
            width: bounds.width,
            height: 0.75
        ))
    }

    /// CTRunDraw 경로에서 밑줄을 직접 그린다 (CTLineDraw만 밑줄을 지원).
    func drawUnderlineIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[.underlineStyle] != nil else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        let font = runFont(attributes)
        let position = font.map(CTFontGetUnderlinePosition) ?? -1
        let thickness = font.map { max(0.5, CTFontGetUnderlineThickness($0)) } ?? 0.75
        let color = attributes[HwpAttributedStringKey.underlineColor]
            ?? attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        setDecorationFillColor(color, in: ctx)
        ctx.fill(CGRect(
            x: bounds.minX,
            y: lineOrigin.y + position - thickness / 2,
            width: bounds.width,
            height: thickness
        ))
    }

    func setDecorationFillColor(_ color: Any?, in ctx: CGContext) {
        if let color {
            ctx.setFillColor(color as! CGColor) // swiftlint:disable:this force_cast
        } else {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        }
    }

    /// run 속성의 CTFont (CF 타입 검사 포함)
    func runFont(_ attributes: [NSAttributedString.Key: Any]) -> CTFont? {
        guard let value = attributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
        else { return nil }
        return (value as! CTFont) // swiftlint:disable:this force_cast
    }

    /// run의 타이포그래피 경계 (텍스트 공간, baseline 기준)
    func runBounds(of run: CTRun, lineOrigin: CGPoint) -> CGRect {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTRunGetTypographicBounds(
            run, CFRange(location: 0, length: 0), &ascent, &descent, &leading
        ))
        var position = CGPoint.zero
        if CTRunGetGlyphCount(run) > 0 {
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
        }
        return CGRect(
            x: lineOrigin.x + position.x,
            y: lineOrigin.y - descent,
            width: width,
            height: ascent + descent
        )
    }
}
