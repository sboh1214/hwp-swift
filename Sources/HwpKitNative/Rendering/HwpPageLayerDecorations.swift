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
        }
        if needsPerRunDrawing {
            for run in runs {
                drawRun(run, origin: origin, in: ctx)
            }
        } else {
            CTLineDraw(line, ctx)
        }

        // 키 큰 인라인 개체 줄에서 밑줄은 올라간 베이스라인이 아니라 개체
        // 하단 (lift 전 위치)에 남는다 (공공누리 실물)
        let underlineOrigin = CGPoint(
            x: origin.x,
            y: origin.y - HwpPageLayer.underlineReturnDrop(of: line)
        )
        for run in runs {
            // 밑줄은 CT 대신 항상 직접 (실물 헤어라인 두께 정합)
            drawUnderlineIfNeeded(run, lineOrigin: underlineOrigin, in: ctx)
            drawStrikethroughIfNeeded(run, lineOrigin: origin, in: ctx)
            drawEmphasisIfNeeded(run, lineOrigin: origin, in: ctx)
            drawTrackInsertUnderlineIfNeeded(run, lineOrigin: origin, in: ctx)
            drawTabLeaderIfNeeded(run, lineOrigin: origin, in: ctx)
        }
    }

    /// 탭 전진 구간의 점선 리더 (legacy 목차 실물: 가운데점 '……' 연속)
    func drawTabLeaderIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.tabLeader] != nil else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        guard bounds.width > 4 else { return }
        let size = runFont(attributes).map(CTFontGetSize) ?? 10
        let color = attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        setDecorationFillColor(color, in: ctx)
        // 실물 리더 실측 (legacy 목차): 점 지름 ~0.08em, 중심 간격 ~0.3em,
        // x-height 중간 높이
        let dotY = lineOrigin.y + size * 0.16
        let radius = max(0.4, size * 0.04)
        let spacing = max(2.5, size * 0.3)
        var x = bounds.minX + spacing / 2
        while x < bounds.maxX - radius {
            ctx.fillEllipse(in: CGRect(
                x: x - radius, y: dotY - radius,
                width: radius * 2, height: radius * 2
            ))
            x += spacing
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
        let typographic = runBounds(of: run, lineOrigin: lineOrigin)
        // 실물 음영 상자는 정확히 1em — run의 typographic ascent가 아니라
        // 글리프에 밀착한 em 박스다 (라운드 7 실측: 상하 각 1px 여유)
        let size = runFont(attributes).map(CTFontGetSize) ?? typographic.height
        let bounds = CGRect(
            x: typographic.minX,
            y: lineOrigin.y - size * 0.15,
            width: typographic.width,
            height: size
        )
        ctx.setFillColor(shade as! CGColor) // swiftlint:disable:this force_cast
        ctx.fill(bounds)
        if let stroke = attributes[HwpAttributedStringKey.memoAnchorStroke] {
            // 실물: 범위 양 끝의 둥근 괄호 쌍 — 여는 쪽은 옅고 닫는 쪽이
            // 진하다 (라운드 10 실측)
            func bracket(atX x: CGFloat, cornerX: CGFloat) -> CGPath {
                let path = CGMutablePath()
                let radius: CGFloat = 1.2
                path.move(to: CGPoint(x: cornerX, y: bounds.minY))
                path.addArc(
                    tangent1End: CGPoint(x: x, y: bounds.minY),
                    tangent2End: CGPoint(x: x, y: bounds.minY + radius),
                    radius: radius
                )
                path.addLine(to: CGPoint(x: x, y: bounds.maxY - radius))
                path.addArc(
                    tangent1End: CGPoint(x: x, y: bounds.maxY),
                    tangent2End: CGPoint(x: cornerX, y: bounds.maxY),
                    radius: radius
                )
                return path
            }
            let strokeColor = stroke as! CGColor // swiftlint:disable:this force_cast
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(strokeColor)
            ctx.addPath(bracket(atX: bounds.maxX, cornerX: bounds.maxX - 1.2))
            ctx.setLineWidth(0.9)
            ctx.strokePath()
            ctx.addPath(bracket(atX: bounds.minX, cornerX: bounds.minX + 1.2))
            ctx.setLineWidth(0.55)
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
            // setShadow는 base space 기준이라 오프셋 방향이 뒤틀린다
            // (라운드 8 실측: 왼쪽으로 출력) — 사본을 직접 그린다.
            // 연속 그림자는 본문~사본 사이를 스텝으로 채운 면 덩어리
            // (실물: 획에 밀착된 연속 회색), 비연속은 분리 사본 하나.
            // run은 kCTForegroundColorFromContext — 컨텍스트 fill 색.
            let continuous = attributes[HwpAttributedStringKey.shadowContinuous] != nil
            let steps: [CGFloat] = continuous ? [0.25, 0.5, 0.75, 1.0] : [1.0]
            ctx.setFillColor(shadow)
            for step in steps {
                // 텍스트 공간은 y-up이므로 시각적 아래(+dy)는 -y
                ctx.textPosition = CGPoint(
                    x: origin.x + offsetX * step,
                    y: origin.y - offsetY * step
                )
                CTRunDraw(run, ctx, CFRange(location: 0, length: 0))
            }
            let face = attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
            // swiftlint:disable:next force_cast
            ctx.setFillColor(face.map { $0 as! CGColor } ?? CGColor(gray: 0, alpha: 1))
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
            // 실물: 점 중심이 글리프 잉크 상단에서 ~0.26em (라운드 11 실측
            // — CT ascent 기준 배치는 0.2em 더 높았다)
            let dotY = lineOrigin.y + bounds.maxY + (ascent + descent) * 0.13
            ctx.fillEllipse(in: CGRect(
                x: centerX - radius, y: dotY - radius,
                width: radius * 2, height: radius * 2
            ))
        }
    }

    /// 변경 추적 삽입 밑줄 — 베이스라인 아래 0.35em (한글 실물: 디센더
    /// 아래 글리프 높이의 ~39% — 라운드 7 실측)
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
            y: lineOrigin.y - size * 0.35,
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
        // 실물 취소선도 밑줄과 같은 헤어라인 (라운드 8 실측 ~0.45pt)
        ctx.fill(CGRect(
            x: bounds.minX,
            y: lineOrigin.y + xHeight / 2,
            width: bounds.width,
            height: 0.4
        ))
    }

    /// CTRunDraw 경로에서 밑줄을 직접 그린다 (CTLineDraw만 밑줄을 지원).
    func drawUnderlineIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.underlineStyle] != nil else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        let size = runFont(attributes).map(CTFontGetSize) ?? 10
        // 실물 밑줄은 헤어라인 (줄 높이의 ~2.3%), 한글 글리프 바닥 잉크
        // 바로 아래 — 폰트 underlinePosition은 잉크를 관통한다 (라운드 7 실측)
        let thickness: CGFloat = 0.4
        let color = attributes[HwpAttributedStringKey.underlineColor]
            ?? attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        setDecorationFillColor(color, in: ctx)
        ctx.fill(CGRect(
            x: bounds.minX,
            y: lineOrigin.y - size * 0.20 - thickness / 2,
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
