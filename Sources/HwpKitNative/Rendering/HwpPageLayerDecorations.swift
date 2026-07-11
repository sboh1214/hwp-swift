import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
import QuartzCore

// MARK: - 글자 장식 (CT 미지원: 음영 배경/그림자/취소선, CTRunDraw 경로 밑줄)

extension HwpPageLayer {
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
                || attributes[HwpAttributedStringKey.glyphBaselineOffset] != nil
                || attributes[HwpAttributedStringKey.outlineBody] != nil
        }
        if needsPerRunDrawing {
            for run in runs {
                drawRun(run, origin: origin, in: ctx)
            }
        } else {
            CTLineDraw(line, ctx)
        }

        for run in runs {
            // 밑줄은 CT 대신 항상 직접 (실물 헤어라인 두께 정합)
            drawUnderlineIfNeeded(run, lineOrigin: origin, in: ctx)
            drawStrikethroughIfNeeded(run, lineOrigin: origin, in: ctx)
            drawEmphasisIfNeeded(run, lineOrigin: origin, in: ctx)
            drawTrackInsertUnderlineIfNeeded(run, lineOrigin: origin, in: ctx)
        }
    }

    func runAttributes(_ run: CTRun) -> [NSAttributedString.Key: Any] {
        CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
    }

    /// 음영 배경 (글리프보다 먼저). 메모 앵커는 둥근 녹색 테두리도 두른다
    /// (한글.app 실물 — memo 픽스처 앵커 괄호).
    func drawShadeIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard let shade = attributes[HwpAttributedStringKey.shadeColor] else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        ctx.setFillColor(shade as! CGColor) // swiftlint:disable:this force_cast
        ctx.fill(bounds)
        if let stroke = attributes[HwpAttributedStringKey.memoAnchorStroke] {
            let path = CGPath(
                roundedRect: bounds.insetBy(dx: 0.3, dy: 0.3),
                cornerWidth: 1.5, cornerHeight: 1.5, transform: nil
            )
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setStrokeColor(stroke as! CGColor) // swiftlint:disable:this force_cast
            ctx.setLineWidth(0.6)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// run 하나를 그림자/양각 설정과 함께 그린다
    func drawRun(_ run: CTRun, origin: CGPoint, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let attributes = runAttributes(run)
        var origin = origin
        if let shift = (attributes[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber) {
            // 글자 위치 (표 33): 줄 배치는 그대로, 글리프만 세로 이동
            origin.y += CGFloat(shift.doubleValue)
        }
        if attributes[HwpAttributedStringKey.outlineBody] != nil {
            drawOutlineRun(run, attributes: attributes, origin: origin, in: ctx)
            return
        }
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
            // swiftlint:disable:next force_cast
            let shadow = shadowColor as! CGColor
            // 라운드 4 실측: 실물의 연속/비연속 그림자는 모두 밝은 회색
            // 단일 분리 사본 — 사본 겹침 없이 setShadow 한 번으로 그린다.
            // 텍스트 공간은 y-up으로 뒤집혀 있으므로 아래(+dy)는 -y
            ctx.setShadow(
                offset: CGSize(width: offsetX, height: -offsetY),
                blur: 0,
                color: shadow
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
        // 실물 (CharShapeProperty 라운드 2 재실측): 본체는 원래 글자색
        // (거의 검정)이고, 회색 고스트가 양각은 왼쪽 위 하이라이트,
        // 음각은 오른쪽 아래에 붙는다.
        let ghost = CGColor(gray: 0.62, alpha: 1)
        let offset: CGFloat = 0.7
        // 텍스트 공간은 y-up이므로 시각적 아래 = -y.
        let ghostDX: CGFloat = style == 1 ? -offset : offset
        let ghostDY: CGFloat = style == 1 ? offset : -offset
        ctx.setFillColor(ghost)
        ctx.textPosition = CGPoint(x: origin.x + ghostDX, y: origin.y + ghostDY)
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
        let face = attributes[HwpAttributedStringKey.reliefFaceColor]
        setDecorationFillColor(face, in: ctx)
        ctx.textPosition = origin
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
    }

    /// 외곽선 (표 33): 한글은 글자를 두껍게 확장한 뒤 속을 파낸다 —
    /// 굵은 윤곽 스트로크 후 흰 채움 (CharShapeProperty 실물: 흰 속 +
    /// 검정 컨투어. 헤어라인 글꼴에서는 CT 양수 stroke만으로 속이 안 남는다).
    func drawOutlineRun(
        _ run: CTRun,
        attributes: [NSAttributedString.Key: Any],
        origin: CGPoint,
        in ctx: CGContext
    ) {
        let color = attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        let size = runFont(attributes).map(CTFontGetSize) ?? 10
        ctx.setTextDrawingMode(.stroke)
        ctx.setLineWidth(max(0.8, size * 0.1))
        if let color, CFGetTypeID(color as CFTypeRef) == CGColor.typeID {
            ctx.setStrokeColor(color as! CGColor) // swiftlint:disable:this force_cast
        } else {
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        }
        ctx.textPosition = origin
        CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
        ctx.setTextDrawingMode(.fill)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
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

    /// 변경 추적 삽입 밑줄 — 베이스라인 아래 0.22em (한글 실물 실측)
    func drawTrackInsertUnderlineIfNeeded(
        _ run: CTRun,
        lineOrigin: CGPoint,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        guard let color = attributes[HwpAttributedStringKey.trackInsertUnderline]
        else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        let size = runFont(attributes).map(CTFontGetSize) ?? 10
        setDecorationFillColor(color, in: ctx)
        ctx.fill(CGRect(
            x: bounds.minX,
            y: lineOrigin.y - size * 0.22,
            width: bounds.width,
            height: 0.75
        ))
    }

    /// 취소선 (CT 미지원 — 항상 직접)
    func drawStrikethroughIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.strikethroughStyle] != nil else { return }
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
        guard attributes[HwpAttributedStringKey.underlineStyle] != nil else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        let font = runFont(attributes)
        let position = font.map(CTFontGetUnderlinePosition) ?? -1
        // 실물 밑줄은 헤어라인 (줄 높이의 ~2.3% — CharShapeProperty 실측)
        let thickness: CGFloat = 0.4
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
