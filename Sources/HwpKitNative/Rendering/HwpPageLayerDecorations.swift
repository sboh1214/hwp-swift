import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKitCore
import QuartzCore

// MARK: - 글자 장식 (CT 미지원: 음영 배경/그림자/취소선, CTRunDraw 경로 밑줄)

extension HwpPageLayer {
    /// 줄 하나를 run 단위로 그린다: 음영 배경 → 글리프 (그림자/양각 포함) →
    /// 취소선/강조점. 글리프는 run 하나하나가 다르게 그려질 이유(그림자·양각·
    /// 글자 위치·한 줄 끝 표식)가 없으면 CTLineDraw 한 번으로, 있으면 run마다
    /// 그린다 (`drawRun`). 밑줄·취소선 같은 선은 어느 경로든 아래에서 직접 그린다.
    /// `endsParagraph`(`HwpDrawnLine.endsParagraph`)는 문단의 마지막 줄 — MS 워드 호환
    /// 문단 끝 상자가 이 줄에만 든다.
    func drawDecoratedLine(
        _ line: CTLine, origin: CGPoint, endsParagraph: Bool, in ctx: CGContext
    ) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], !runs.isEmpty else { return }

        for run in runs {
            drawShadeIfNeeded(run, lineOrigin: origin, in: ctx)
        }

        let needsPerRunDrawing = runs.contains { run in
            let attributes = runAttributes(run)
            return attributes[HwpAttributedStringKey.shadowColor] != nil
                || attributes[HwpAttributedStringKey.reliefStyle] != nil
                || attributes[HwpAttributedStringKey.glyphBaselineOffset] != nil
                || attributes[HwpAttributedStringKey.lineBreak] != nil
        }
        if needsPerRunDrawing {
            for run in runs {
                drawRun(run, origin: origin, in: ctx)
            }
        } else {
            CTLineDraw(line, ctx)
        }

        // 장식은 글리프가 아니라 **줄 원점**을 기준으로 그린다 — `drawRun`이
        // `glyphBaselineOffset`(글자 위치·첨자)으로 글리프만 옮겨도 선은 제자리다.
        // 한글.app도 글자 위치에서는 그렇다 (2026-09-09 실측: `hh:offset` 50으로
        // 글리프가 5pt 내려가도 취소선·아래 밑줄·위 밑줄이 모두 같은 y에 남았다).
        // 첨자만 예외이고 선마다 다르다 (2026-09-15 실측, #179): 취소선·글자 가운데
        // 밑줄은 첨자로 옮겨진 베이스라인을 따라가고(`scriptBaselineOffset`), 글자
        // 아래·위 밑줄은 첨자에도 제자리다. 위치·두께의 크기 기준은 각 함수 주석에.
        //
        // 밑줄(글자 아래·위·삽입)은 세 문서 갈래 모두 **줄 단위**다 (#187·#226) — 줄마다 한
        // 번 푼 기준이 그 줄 모든 밑줄의 자리·두께를 정한다. 한글 문서·한글 2007 호환
        // 문서는 줄 상자 높이(밑줄 가장자리가 상자 바닥·상단에 붙는다)와 줄 글자의 기본 크기
        // 최댓값(두께·선 모양 축척), MS 워드 호환 문서는 글꼴 줄 상자다. 둘 다 세로 배치가
        // 쓰는 상자와 같은 값이다 (`HwpDrawnTextLayout.underlineReference(of:endsParagraph:)`).
        // 키 큰 글자처럼 취급 개체 줄에서 밑줄이 개체 하단에 남는 것(공공누리 실물)도 이
        // 상자 바닥 규칙의 한 경우다 — 종전의 원점 되돌림(`underlineReturnDrop`)을 대신한다.
        // 취소선은 run마다 자기 크기·글꼴이라 아래에서 따로 푼다.
        let underlineReference = HwpDrawnTextLayout.underlineReference(
            of: line, endsParagraph: endsParagraph
        )
        let strikethroughFonts = msWordStrikethroughFonts(of: runs)
        // 점선·물결 같은 선 모양(#191)은 글자 모양 run(같은 `charShapeId`의 잇닿은 run)
        // 단위로 패턴을 편다 — 그 묶음의 첫 run만 span을 받고 나머지는 nil이다.
        let shapeSpans = lineShapeSpans(of: runs, lineOrigin: origin)
        for (index, run) in runs.enumerated() {
            // 밑줄은 CT 대신 항상 직접 (CT 밑줄은 폰트 지표 위치·두께라 실물과 갈린다)
            drawUnderlineIfNeeded(
                run, lineOrigin: origin, reference: underlineReference,
                shapeSpan: shapeSpans[index], in: ctx
            )
            drawAboveUnderlineIfNeeded(
                run, lineOrigin: origin, reference: underlineReference,
                shapeSpan: shapeSpans[index], in: ctx
            )
            drawStrikethroughIfNeeded(
                run, lineOrigin: origin, msWordFont: strikethroughFonts[index],
                shapeSpan: shapeSpans[index], in: ctx
            )
            drawEmphasisIfNeeded(run, lineOrigin: origin, in: ctx)
            drawTrackInsertUnderlineIfNeeded(
                run, lineOrigin: origin, reference: underlineReference, in: ctx
            )
            drawTabLeaderIfNeeded(run, lineOrigin: origin, in: ctx)
        }
    }

    /// 이 run이 MS 워드 호환 문서의 것인지 — 조판이 한글 문서가 아닌 문서의 모든 run에
    /// 싣는 `compatibleDocumentTarget`(표 55)이 `msWord`일 때만 참이다. 한글 2007 호환은
    /// 또 다른 기하이고 (`isHwp2007Compatible`, #210), 훈민정음 호환·record 없음은 한글
    /// 문서와 같은 기하다.
    func isMsWordCompatible(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let raw = attributes[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
        else { return false }
        return raw.uint32Value == HwpCompatibleDocumentTarget.msWord.rawValue
    }

    /// MS 워드 호환 문서에서 run마다 취소선의 기준이 되는 글꼴 — 한글 문서 줄이면 전부
    /// nil. 한글은 취소선을 **글자 모양 run** 단위로 그 run의 첫 글리프 글꼴에 놓는다
    /// (2026-09-15 실측: 한글 슬롯 함초롬·라틴 슬롯 Apple SD인 run "Ag밑줄Ag한글"의
    /// 취소선이 전체가 Apple SD 자리 +0.2492em, 슬롯을 바꾼 run은 함초롬 자리 +0.2913em).
    /// 조판은 글자 모양 하나를 스크립트 슬롯마다 쪼개고 CoreText는 대체 글꼴 경계에서
    /// 또 쪼개므로, 같은 글자 모양 id(`HwpAttributedStringKey.charShapeId`)의 잇닿은 run을
    /// 한 글자 모양 run으로 묶어 첫 run의 글꼴을 함께 쓴다 — 안 묶으면 한 run 안에서
    /// 취소선이 글꼴마다 계단이 진다. 속성 사전 전체를 비교하지 않는 이유는 양쪽 정렬
    /// 자간(`kCTKernAttributeName`)·문단 끝 상자(`msWordParagraphEndBox`)가 한 글자 모양
    /// 안에서 달라지고, 글꼴만 다른 별개 글자 모양은 사전이 같아 보이기 때문이다
    /// (#187 리뷰). id 없는 폴백 모양 run은 홀로 선다.
    func msWordStrikethroughFonts(of runs: [CTRun]) -> [CTFont?] {
        var fonts: [CTFont?] = []
        var groupShape: NSNumber?
        var groupFont: CTFont?
        for run in runs {
            let attributes = runAttributes(run)
            guard isMsWordCompatible(attributes) else {
                fonts.append(nil)
                groupShape = nil
                continue
            }
            let font = runFont(attributes)
            // 글자 모양 id(`charShapeId`)로 묶는다 — 속성 사전 전체를 비교하면 양쪽 정렬
            // 자간·문단 끝 상자처럼 글자 모양 안에서 달라지는 키가 run을 가르고, 크기·
            // 색이 같은 다른 글자 모양이 묶인다. id 없는 폴백 모양 run은 홀로 선다.
            let shape = attributes[HwpAttributedStringKey.charShapeId] as? NSNumber
            if let shape, let groupShape, shape == groupShape {
                fonts.append(groupFont ?? font)
            } else {
                groupShape = shape
                groupFont = font
                fonts.append(font)
            }
        }
        return fonts
    }

    /// 장식선의 기준 크기 — run 글꼴 크기가 아니라 **글자 모양의 기본 크기**
    /// (`hwp.baseFontSize`, 슬롯 상대 크기·첨자 축소 전)다. 세 문서 갈래가 같다 — 한글
    /// 문서와 한글 2007 호환 문서는 em 비율에, MS 워드 호환 문서는 글꼴 상자(em)에 이
    /// 크기를 곱한다. 한글 12.30 실측: 한글 문서에서 기본 40pt·상대 크기 50%인 run의 밑줄이
    /// −6.84pt·1.56pt, 취소선 +14.04pt (#226 — 20pt 자리라면 −3.40·0.80·+7.00이다), 한글
    /// 2007 호환 문서는 −6.24pt·+13.92pt (#210). MS 워드 호환 문서(2026-09-16, PR 리뷰)는 한
    /// 글자 모양 안에서 한글 슬롯 50%·라틴 100%로 갈라도 (함초롬 20pt `가나` + Helvetica
    /// 40pt `Ag`) 밑줄이 함초롬 40pt 상자 자리·두께 그대로고 (−10.3pt·2.64pt, 슬롯 50% 상자로
    /// 재면 −4.3pt), 취소선도 첫 글리프 글꼴 × 40pt (+11.64pt, 20pt 기준이면 +5.84)다. 밑줄은
    /// 줄 단위라 대개 줄의 기준(`HwpDecorationLineGeometry.UnderlineReference`)을 쓰고, 이 값은
    /// 취소선과 줄 기준이 비었을 때의 폴백이다. 표식 run은 허용 목록이 `baseFontSize`를 남겨
    /// 같은 값을 갖고, 키가 없는 합성 문자열은 첨자 축소 전 크기(`preScriptFontSize` —
    /// `spaceTargetSize`, 그것도 없으면 run 글꼴 크기)로 떨어진다.
    func decorationBaseFontSize(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        if let base = attributes[HwpAttributedStringKey.baseFontSize] as? NSNumber,
           base.doubleValue > 0
        {
            return CGFloat(base.doubleValue)
        }
        return preScriptFontSize(attributes)
    }

    /// 탭 전진 구간의 점선 리더 (legacy 목차 실물: 가운데점 '……' 연속)
    func drawTabLeaderIfNeeded(_ run: CTRun, lineOrigin: CGPoint, in ctx: CGContext) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.tabLeader] != nil else { return }
        let bounds = runBounds(of: run, lineOrigin: lineOrigin)
        guard bounds.width > 4 else { return }
        // 각 탭이 겨냥한 stop(탭 끝 이후 첫 stop)의 채움을 위치로 판정한다 —
        // 채움 없는 stop을 겨냥한 탭은 리더를 그리지 않는다 (#4). stop을 못
        // 찾거나 목록이 없으면 기존 동작(그림)으로 폴백해 legacy 렌더를 보존한다.
        if let stops = attributes[HwpAttributedStringKey.tabLeaderStops] as? [NSNumber],
           stops.count >= 2
        {
            let tabEnd = bounds.maxX - lineOrigin.x
            var index = 0
            while index + 1 < stops.count {
                if CGFloat(truncating: stops[index]) >= tabEnd - 2 {
                    if stops[index + 1].intValue == 0 {
                        return
                    }
                    break
                }
                index += 2
            }
        }
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
        let attributes = runAttributes(run)
        // 한 줄 끝(10) run은 줄 나눔만 하고 글리프는 그리지 않는다 (#146) — 한컴
        // 번들의 HY 계열 폰트는 U+000A에 잉크 있는 글리프(진행 폭 1em)를 가져,
        // 그대로 그리면 Shift+Enter 자리마다 조판 부호가 보인다. 장식은 조판이
        // 이미 떼어 냈으므로 (`HwpTextRunBuilder.appendLineBreak`) 글리프만 건너뛴다.
        guard attributes[HwpAttributedStringKey.lineBreak] == nil else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // CTRunDraw는 run의 텍스트 매트릭스를 **적용하지 않는다** — 조판이 장평
        // (`faceScaleX`)과 기울임 근사를 CTFont 매트릭스로 싣고 CoreText가 그것을
        // run 텍스트 매트릭스로 옮겨 두는데, CTLineDraw는 그 매트릭스로 그리고
        // CTRunDraw는 컨텍스트의 텍스트 매트릭스를 그대로 쓴다. 안 맞추면 장평 95%
        // 줄이 이 경로에서만 5% 넓게 그려진다 (legacy 각주 실측: 잉크 +8.5%).
        // 텍스트 매트릭스는 그래픽 상태에 들지 않으므로 restoreGState가 되돌리지
        // 않는다 — 다음 CTLineDraw를 위해 직접 항등으로 돌린다.
        ctx.textMatrix = CTRunGetTextMatrix(run)
        defer { ctx.textMatrix = .identity }
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

    /// 변경 추적 삽입 밑줄 — 일반 '글자 아래' 밑줄과 **같은 자리·같은 두께**를 빨강으로
    /// 그린다 (#187 실측: 한글 문서 13개 글꼴·MS 워드 호환 문서 32개 글꼴 전부 삽입
    /// 밑줄 = 일반 밑줄). 종전(#176)의 전용 상수 −0.26em·0.064em은 `track-changes`
    /// 실물(MS 워드 호환 문서)의 함초롬돋움 값이었고, 그 값은 이제 호환 문서의 글꼴
    /// 지표 기하(`msWord`)가 낸다. 한글 2007 호환 문서에서도 일반 밑줄과 같은
    /// 고정 0.36pt 선이다 (#210 실측: 삽입 밑줄 −4.92pt = 일반 밑줄, 삭제선 +11.16pt ≒
    /// 일반 취소선 +11.04pt — 쪽이 0.8배로 줄어 글리프가 31.68pt로 찍힌 표본).
    /// 자리도 일반 밑줄처럼 **줄 단위**다 (#226 실측: 10pt 삽입 글자가 40pt 무장식 글자와 한
    /// 줄이면 −6.75pt·두께 1.5pt(40pt 몫), 40pt 문단 끝 글자와 한 줄이면 −6.15pt·10pt 두께,
    /// 같은 줄의 일반 밑줄과 같은 y — 0.8배 축소 쪽 좌표를 되돌린 값).
    func drawTrackInsertUnderlineIfNeeded(
        _ run: CTRun,
        lineOrigin: CGPoint,
        reference: HwpDecorationLineGeometry.UnderlineReference,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        guard let color = attributes[HwpAttributedStringKey.trackInsertUnderline]
        else { return }
        let line = underlineBelowLine(attributes, reference: reference)
        // 변경 추적 표시선에는 선 모양이 없다 — 늘 실선.
        fillLine(
            run, lineOrigin: lineOrigin, line: line, color: color,
            shaped: ShapedLine(
                shape: .line, placement: .underlineBelow,
                fontSize: underlineShapeScale(attributes, reference: reference), span: nil
            ),
            in: ctx
        )
    }

    /// 취소선 — 밑줄 종류 '글자 가운데'(표 35 값 2)와 변경 추적 삭제선도 이 선을
    /// 공유한다 (CT 미지원 — 항상 직접).
    ///
    /// 첨자 run에서는 **첨자로 옮겨진 베이스라인**(`scriptBaselineOffset`)을 기준으로
    /// **줄어든 글꼴 크기**의 0.35배 위에 그린다 — 한글이 그렇게 그린다 (2026-09-15
    /// 실측 #179, 함초롬바탕·Apple SD 동일: 10pt 위 첨자 6.36pt 글리프가 4.32pt 올라간
    /// 표본에서 선은 원래 베이스라인 위 6.60pt = 4.32 + 0.35 × 6.36(장치 0.12pt 양자화,
    /// 첨자 단독 표본의 올림은 4.44), 아래 첨자가 1.20pt 내려가면 1.08pt = −1.20 + 2.28;
    /// 글자 가운데 밑줄도 같은 자리). 글자 위치(`hh:offset`)로 옮겨진 몫은 따라가지
    /// 않는다 — 첨자와 글자 위치를 함께 준 run에서도 선은 첨자 몫만 옮겨진 자리
    /// (위 첨자 + 위치 50에서 6.72pt)에 남는다. 종전에는 이동 없이 원래 베이스라인 위
    /// 0.35 × 축소 크기에 그려 위 첨자 글리프 아래·아래 첨자 글리프 위로 벗어났다.
    /// 변경 추적 삭제선은 같은 경로라 함께 옮겨지지만 첨자 표본은 없다.
    ///
    /// 두께는 **첨자 축소 전 기본 크기**의 0.04배다 — 한글은 첨자 run의 선도 본문과 같은
    /// 폭으로 그린다 (같은 실측: 10pt 첨자 선 0.36pt = 본문과 같음, 축소 크기 6.36pt
    /// 기준이면 0.24pt).
    ///
    /// 자리·두께의 크기는 세 문서 갈래 모두 run 글꼴 크기가 아니라 **글자 모양 기본 크기**
    /// (`decorationBaseFontSize`, 슬롯 상대 크기 무관)에 첨자 축소 비율만 곱한 값이다 —
    /// 한글 문서 실측(#226): 기본 40pt·상대 크기 50% run의 취소선 +14.04pt·1.56pt, 기본
    /// 20pt·상대 크기 50% 위 첨자는 옮겨진 베이스라인 위 0.35 × 12.8pt. `msWordFont`는 MS
    /// 워드 호환 문서에서 이 run의 취소선 기준 글꼴(`msWordStrikethroughFonts`) — 한글
    /// 문서면 nil이고 글자 크기 비례로 그린다. 그 글꼴의 상자에 곱하는 크기도 같은 기본
    /// 크기다 (한글 실측: 한글 50%·라틴 100%로 갈린 글자 모양 run의 취소선이 한 줄, 자리는
    /// 첫 글리프 글꼴 × 40pt, 두께 1.56pt = 0.04 × 40). 슬롯마다 글꼴 크기가 달라
    /// CoreText가 쪼갠 run을 run 크기로 곱하면 한 글자 모양 안에서 취소선이 계단이 진다 (PR
    /// 리뷰).
    ///
    /// 한글 2007 호환 문서(#210)에서는 중심이 한글 문서와 같은 0.35 × 기준 크기이고
    /// 두께만 고정 0.36pt다 — 갈래 판정은 `strikethroughLine`에 있다.
    func drawStrikethroughIfNeeded(
        _ run: CTRun,
        lineOrigin: CGPoint,
        msWordFont: CTFont?,
        shapeSpan: CGRect?,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.strikethroughStyle] != nil else { return }
        let color = attributes[HwpAttributedStringKey.strikethroughColor]
            ?? attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        let font = runFont(attributes)
        let size = font.map(CTFontGetSize) ?? 10
        // 한글 문서에서는 글꼴 지표가 아니라 글자 크기에 비례해 그린다 (#136 실측) —
        // 폰트의 x-height 절반은 라틴 취소선 위치라 한글 글리프에서 낮게 보였다.
        // MS 워드 호환 문서(#187)에서는 run 자신의 글꼴 지표(`ascent` × 0.273)다 —
        // 밑줄과 달리 줄 단위가 아니라 run 단위이고, 두께는 두 갈래 모두 글자 크기의
        // 0.04배다 (#176 실측: 5~100pt에서 밑줄·취소선이 같은 폭). 변경 추적 삭제선도
        // 같은 경로다 (`track-changes` 실물의 +0.29em = 함초롬돋움의 호환 문서 값).
        let line = strikethroughLine(attributes, msWordFont: msWordFont, fontSize: size)
        fillLine(
            run,
            lineOrigin: CGPoint(x: lineOrigin.x, y: lineOrigin.y + scriptBaselineShift(attributes)),
            line: line, color: color,
            shaped: ShapedLine(
                shape: lineShape(attributes[HwpAttributedStringKey.strikethroughShape]),
                placement: .strikethrough, fontSize: strikethroughShapeScale(attributes),
                span: shapeSpan
            ),
            in: ctx
        )
    }

    /// CTRunDraw 경로에서 밑줄 '글자 아래'를 직접 그린다 (CTLineDraw만 밑줄을 지원).
    ///
    /// **줄 단위다** (#226): 선의 위 가장자리가 그 줄 상자의 바닥(베이스라인 아래 0.15 × 줄
    /// 상자 높이)에 붙고, 두께는 줄 글자의 기본 크기 최댓값의 0.04배다 — 한 크기만 있는
    /// 줄이면 중심 −0.17em(#176 실측 — 네 글꼴·13개 크기에서 같은 비율). 폰트
    /// `underlinePosition`(−0.075em)은 한글 글리프 잉크를 관통하므로 쓰지 않는다. 같은
    /// 줄의 40pt 무장식 글자·문단 끝 글자·한 줄 끝·책갈피·글자처럼 취급 개체가 줄 상자를
    /// 키우면 10pt 밑줄도 그 상자 바닥으로 내려간다 (한글 12.30 실측: −6.12~−6.84pt). 키 큰
    /// 개체 줄에서 밑줄이 개체 하단에 남는 것(공공누리 실물)도 이 규칙이다 — 개체가 상자를
    /// 정한 줄의 상자 바닥이 곧 개체 바깥 상자(개체 + 바깥 여백)의 아랫변이라 종전의 원점
    /// 되돌림이 따로 필요 없다 (그
    /// 되돌림은 상자 바닥 몫을 run 크기 × 0.17에 한 번 더 더해 10pt 글자에서 1.5pt 낮았다).
    ///
    /// 크기는 **첨자로 줄기 전 기본 크기**이고 첨자 이동은 따라가지 않는다 — 위쪽 밑줄과
    /// 같은 규칙이다 (2026-09-15 실측 #179: 10pt 위/아래 첨자 run의 밑줄이 둘 다 원래
    /// 베이스라인 아래 1.68pt = 10pt의 0.17배, 두께 0.36pt에 남는다; 글자 위치 50을 함께
    /// 줘도 같은 자리. #226: 기본 40pt 위 첨자 run이 든 줄은 40pt 상자·두께).
    ///
    /// MS 워드 호환 문서(#187)에서는 줄 상자(`reference.msWordLineBox`)로 줄 전체가 한 자리·한
    /// 두께이고, 한글 2007 호환 문서(#210)에서는 같은 상자 바닥에 위 가장자리를 맞춘 고정
    /// 0.36pt 선이다 — `HwpDecorationLineGeometry`·`underlineBelowLine` 참조.
    func drawUnderlineIfNeeded(
        _ run: CTRun,
        lineOrigin: CGPoint,
        reference: HwpDecorationLineGeometry.UnderlineReference,
        shapeSpan: CGRect?,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.underlineStyle] != nil else { return }
        fillUnderline(
            run, lineOrigin: lineOrigin, placement: .underlineBelow, reference: reference,
            span: shapeSpan, in: ctx
        )
    }

    /// 밑줄 '글자 위'(표 33 값 3) — 선의 아래 가장자리가 줄 상자의 **상단**(베이스라인 위
    /// 0.85 × 줄 상자 높이)에 붙는다. 한 크기만 있는 줄이면 중심 +0.87em (#136 실측).
    /// 아래 밑줄과 같은 줄 단위 규칙이다 (#226 실측: 10pt 위 밑줄이 40pt 문단 끝 글자·한 줄
    /// 끝·책갈피·그림·표와 한 줄이면 +34.20pt·0.36pt, 40pt 무장식 글자와 한 줄이면 두께 기준도
    /// 40pt라 +34.68pt·1.56pt, 바깥 여백 위 7pt를 준 20pt 그림(상자 30pt) 줄은 +25.68pt — 개체가
    /// 상자를 정한 줄에서는 개체 바깥 상자(개체 + 바깥 여백)의 윗변에 붙는다).
    ///
    /// 크기는 **첨자로 줄기 전 기본 크기**이고 첨자 이동도 따라가지 않는다. 한글은 첨자
    /// run에서 이 선을 기본 크기·원래 베이스라인에 그린다 (2026-09-09 실측: 9.96 → 6.36pt로
    /// 줄어든 첨자 글리프에서도 선이 원래 베이스라인 위 8.76pt = 10pt의 0.87배 자리에
    /// 그대로 남는다; 2026-09-15 #179 실측에서 아래 첨자·글자 위치 동반도 같다). 같은 줄의
    /// 취소선만 첨자로 옮겨진 베이스라인 + 줄어든 크기를 따르므로
    /// (`drawStrikethroughIfNeeded`) 기준이 다르다.
    ///
    /// MS 워드 호환 문서(#187)에서는 아래쪽 밑줄과 같은 줄 상자의 `ascent` 위에 같은
    /// 두께로 놓인다 (한글 실측: 함초롬 무장식 run 뒤 Apple SD 위 밑줄 run이 함초롬
    /// 자리 +1.0991em). 한글 2007 호환 문서(#210)에서는 같은 상자 상단에 아래 가장자리를
    /// 맞춘 고정 0.36pt 선이다.
    func drawAboveUnderlineIfNeeded(
        _ run: CTRun,
        lineOrigin: CGPoint,
        reference: HwpDecorationLineGeometry.UnderlineReference,
        shapeSpan: CGRect?,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        guard attributes[HwpAttributedStringKey.underlineAboveStyle] != nil else { return }
        fillUnderline(
            run, lineOrigin: lineOrigin, placement: .underlineAbove, reference: reference,
            span: shapeSpan, in: ctx
        )
    }

    /// 첨자 축소 전 글자 크기 (pt). 조판이 모든 run에 싣는 `spaceTargetSize`가
    /// 그 값이고, 없으면 run 글꼴 크기로 떨어진다.
    func preScriptFontSize(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        if let size = attributes[HwpAttributedStringKey.spaceTargetSize] as? NSNumber {
            return CGFloat(size.doubleValue)
        }
        return runFont(attributes).map(CTFontGetSize) ?? 10
    }

    /// 첨자로 옮겨진 베이스라인의 이동량 (pt, 양수 = 위, #179). 글자 위치 몫은 들어
    /// 있지 않다 — 그 몫까지 합한 `glyphBaselineOffset`을 쓰면 글자 위치만 준 run의
    /// 선까지 따라 움직여 한글과 갈린다.
    private func scriptBaselineShift(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (attributes[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber)
            .map { CGFloat($0.doubleValue) } ?? 0
    }

    /// 밑줄 한 줄 — 자리·두께는 `placement`(글자 아래·위)와 줄의 기준 `reference`에서 푼다
    /// (`underlineBelowLine`·`underlineAboveLine`). 색은 글자 모양의 밑줄 색, 없으면 글자 색.
    /// 모양은 `underlineShape`(글자 아래·위 공용, 없으면 실선)이고 축척은
    /// `underlineShapeScale`이다.
    private func fillUnderline(
        _ run: CTRun,
        lineOrigin: CGPoint,
        placement: HwpLineShapeGeometry.Placement,
        reference: HwpDecorationLineGeometry.UnderlineReference,
        span: CGRect?,
        in ctx: CGContext
    ) {
        let attributes = runAttributes(run)
        let line = placement == .underlineAbove
            ? underlineAboveLine(attributes, reference: reference)
            : underlineBelowLine(attributes, reference: reference)
        let color = attributes[HwpAttributedStringKey.underlineColor]
            ?? attributes[kCTForegroundColorAttributeName as NSAttributedString.Key]
        fillLine(
            run, lineOrigin: lineOrigin, line: line, color: color,
            shaped: ShapedLine(
                shape: lineShape(attributes[HwpAttributedStringKey.underlineShape]),
                placement: placement,
                fontSize: underlineShapeScale(attributes, reference: reference), span: span
            ),
            in: ctx
        )
    }

    /// 장식선 한 줄 — `line.center`는 `lineOrigin` 기준 세로 위치 (양수 = 위),
    /// `line.thickness`는 두께 (pt). 실선은 run 폭의 사각형을 중심 기준으로 위아래 반씩
    /// 나눠 채우고, 그 밖의 모양(#191)은 `fillShapedLine`이 글자 모양 run의 폭에 경로를 편다.
    func fillLine(
        _ run: CTRun,
        lineOrigin: CGPoint,
        line: HwpDecorationLineGeometry.Line,
        color: Any?,
        shaped: ShapedLine,
        in ctx: CGContext
    ) {
        setDecorationFillColor(color, in: ctx)
        guard shaped.shape != .line else {
            let bounds = runBounds(of: run, lineOrigin: lineOrigin)
            ctx.fill(CGRect(
                x: bounds.minX,
                y: lineOrigin.y + line.center - line.thickness / 2,
                width: bounds.width,
                height: line.thickness
            ))
            return
        }
        fillShapedLine(line: line, lineOrigin: lineOrigin, shaped: shaped, in: ctx)
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
