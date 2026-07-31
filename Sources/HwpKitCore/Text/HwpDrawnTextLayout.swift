import CoreGraphics
import CoreText
import Foundation

/// `.drawText` 명령 하나의 렌더-정합 줄 하나.
///
/// `line`은 양쪽 정렬 재조판 (`HwpWordJustification`)이 반영된 최종 CTLine이라
/// 글리프 x 오프셋 질의 (`CTLineGetOffsetForStringIndex` 등)가 화면과 일치한다.
public struct HwpDrawnLine {
    /// 실제로 그려지는 CTLine (재조판본이면 단위 문자열의 부분 복사본)
    public let line: CTLine
    /// 단위 attributedString 기준 문자 범위 (재조판과 무관하게 원본 범위)
    public let stringRange: NSRange
    /// 페이지 로컬 top-down 좌표의 베이스라인 시작점 (배분 정렬 xOffset 포함)
    public let baselineOrigin: CGPoint
    public let ascent: CGFloat
    public let descent: CGFloat

    /// 줄의 선택 하이라이트 영역 (top-down 페이지 좌표)
    public var selectionRect: CGRect {
        let width =
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        return CGRect(
            x: baselineOrigin.x,
            y: baselineOrigin.y - ascent,
            width: width,
            height: ascent + descent
        )
    }
}

/// `.drawText(attributedString:origin:lineWidth:)`의 줄 배치를 렌더러와 동일한
/// 규칙 (slight-overflow 단일 줄, 양쪽 정렬 재조판, baselineLift)으로 계산한다.
/// 렌더러 (`HwpPageLayer`)와 텍스트 선택이 이 함수를 공유해 지오메트리가
/// 정의상 일치한다. 좌표는 top-down 페이지 로컬 — 렌더러가 자신의 y-up
/// 공간으로 변환해 그린다.
public enum HwpDrawnTextLayout {
    public static func lines(
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat,
        maxLineFrames: Int = HwpParagraphLayout.maximumLineFrames
    ) -> [HwpDrawnLine] {
        if let single = slightOverflowSingleLine(
            attributedString: attributedString, origin: origin, lineWidth: lineWidth
        ) {
            return [single]
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let fullLength = attributedString.length
        let lineBudget = max(0, maxLineFrames)
        // 측정(HwpParagraphLayout.layout)과 nextFrameChunk를 공유해 청크 경계를
        // 실제 CTLine 시작에 맞춘다 — 미완 줄은 버려 다음 청크에서 온전히 재조판,
        // 넓은 단일 줄은 안 쪼갠다. 단일 청크(모든 정상 블록)는 문단 전체가 한
        // 프레임이라 렌더 불변 (R48·R50).
        var result: [HwpDrawnLine] = []
        var startLocation = 0
        // 이월 시 다음 청크 첫 줄이 놓일 top-down baseline. nil이면 첫 청크.
        var resumeBaseline: CGFloat?
        while startLocation < fullLength, result.count < lineBudget {
            guard let chunk = nextFrameChunk(
                framesetter: framesetter, typesetter: typesetter,
                attributedString: attributedString,
                startLocation: startLocation, fullLength: fullLength,
                remainingLineBudget: lineBudget - result.count, lineWidth: lineWidth
            ) else { break }
            let framePageTop = resumeBaseline.map {
                $0 + chunk.origins[0].y + baselineLift(of: chunk.lines[0])
            } ?? origin.y + chunk.height
            for index in 0 ..< chunk.keepCount {
                result.append(drawnLine(
                    frameLine: chunk.lines[index],
                    ctOrigin: chunk.origins[index],
                    attributedString: attributedString,
                    origin: CGPoint(x: origin.x, y: framePageTop),
                    lineWidth: lineWidth
                ))
            }
            resumeBaseline = Self.resumeBaseline(
                after: chunk, framePageTop: framePageTop,
                attributedString: attributedString,
                continuesAfterChunk: chunk.nextStart < fullLength
            )
            guard chunk.nextStart > startLocation else { break }
            startLocation = chunk.nextStart
        }
        return result
    }

    /// `origin.y`는 이 줄이 속한 프레임 상자 상단의 top-down 페이지 y다 —
    /// baseline = origin.y − ctOrigin.y − lift (박스 높이가 소거된 상단 침투량).
    private static func drawnLine(
        frameLine: CTLine,
        ctOrigin: CGPoint,
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> HwpDrawnLine {
        let lift = baselineLift(of: frameLine)
        let replacement = HwpWordJustification.justifiedLine(
            frameLine: frameLine,
            attributedString: attributedString,
            availableWidth: lineWidth - ctOrigin.x
        )
        let range = CTLineGetStringRange(frameLine)
        let finalLine = replacement?.line ?? frameLine
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(finalLine, &ascent, &descent, nil)
        return HwpDrawnLine(
            line: finalLine,
            stringRange: NSRange(location: range.location, length: range.length),
            baselineOrigin: CGPoint(
                x: origin.x + ctOrigin.x + (replacement?.xOffset ?? 0),
                y: origin.y - ctOrigin.y - lift
            ),
            ascent: ascent,
            descent: descent
        )
    }

    /// 한 프레임 청크의 조판 결과 — 두 루프(lines/layout)가 공유하는 경계 결정.
    struct FrameChunk {
        let lines: [CTLine]
        let origins: [CGPoint]
        /// 이 청크의 SuggestFrameSize 박스 높이.
        let height: CGFloat
        /// 커밋할 줄 수 — 문자 예산으로 잘린 미완 마지막 줄은 제외한다.
        let keepCount: Int
        /// 다음 청크가 재개할 문자열 위치.
        let nextStart: Int
        /// 버려진(다음 청크로 이월되는) 줄 인덱스 — 없으면 nil.
        var droppedLineIndex: Int? {
            keepCount < lines.count ? keepCount : nil
        }
    }

    /// 측정·렌더가 공유하는 다음 프레임 청크. 남은 줄 예산만큼 문자를 잘라
    /// 조판하되, 문자열 끝 전에 잘린 청크의 마지막(미완) 줄은 커밋하지 않고 그
    /// 줄 시작을 nextStart로 돌려 두 경로가 같은 CTLine 경계에서 재개하게 한다.
    /// 잘린 청크가 한 줄뿐이면(예산보다 긴 한 시각 줄) CTTypesetter로 그 줄의
    /// 실제 끝을 찾아 재프레이밍해 쪼개지 않는다 (R50 #2·#4).
    static func nextFrameChunk(
        framesetter: CTFramesetter,
        typesetter: CTTypesetter,
        attributedString: NSAttributedString,
        startLocation: Int,
        fullLength: Int,
        remainingLineBudget: Int,
        lineWidth: CGFloat
    ) -> FrameChunk? {
        let probeLength = min(fullLength - startLocation, remainingLineBudget)
        guard probeLength > 0 else { return nil }

        func frame(length: Int) -> (lines: [CTLine], origins: [CGPoint], height: CGFloat)? {
            let range = CFRange(location: startLocation, length: length)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, range, nil,
                CGSize(width: lineWidth, height: .greatestFiniteMagnitude), nil
            )
            let height = max(ceil(suggested.height), 1)
            let path = CGPath(
                rect: CGRect(x: 0, y: 0, width: lineWidth, height: height), transform: nil
            )
            let created = CTFramesetterCreateFrame(framesetter, range, path, nil)
            guard let lines = CTFrameGetLines(created) as? [CTLine], !lines.isEmpty
            else { return nil }
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(created, CFRange(location: 0, length: 0), &origins)
            return (lines, origins, height)
        }

        guard var chunk = frame(length: probeLength) else { return nil }
        var length = probeLength

        // 예산이 문자열 끝 전에 잘랐는데 한 시각 줄뿐이면 그 줄을 쪼개지 않게
        // CTTypesetter로 실제 줄 끝을 찾아 확장 재프레이밍한다. break 폭은 문단
        // 오른쪽 여백(tailIndent)까지 반영해야 여러 줄로 벌어지지 않는다 (R50 #2·R51 #1).
        if probeLength < fullLength - startLocation, chunk.lines.count == 1 {
            let style = paragraphStyle(in: attributedString, at: startLocation)
            let breakWidth = availableLineWidth(
                containerWidth: lineWidth, lineOriginX: chunk.origins[0].x, paragraphStyle: style
            )
            let breakLength = CTTypesetterSuggestLineBreak(
                typesetter, startLocation, Double(breakWidth)
            )
            let extended = min(max(1, breakLength), fullLength - startLocation)
            if extended > probeLength, let remade = frame(length: extended) {
                chunk = remade
                length = extended
            }
        }

        // 하드 예산 불변: rescue remade가 tailIndent 등으로 여러 줄이 돼도 남은 줄
        // 예산을 넘겨 커밋하지 않는다 — maxLineFrames 우회 방지 (R51 #1). nextStart는
        // 마지막 커밋 줄 끝(잘린 경우 버린 줄 시작과 동일한 CTLine 경계).
        let cutBeforeEnd = length < fullLength - startLocation
        let proposedKeepCount = cutBeforeEnd && chunk.lines.count >= 2
            ? chunk.lines.count - 1
            : chunk.lines.count
        let keepCount = min(proposedKeepCount, remainingLineBudget)
        guard keepCount > 0 else { return nil }
        let lastRange = CTLineGetStringRange(chunk.lines[keepCount - 1])
        let nextStart = lastRange.location + lastRange.length
        guard nextStart > startLocation else { return nil }
        return FrameChunk(
            lines: chunk.lines, origins: chunk.origins, height: chunk.height,
            keepCount: keepCount, nextStart: nextStart
        )
    }

    /// 이월 후 다음 청크 첫 줄이 놓일 top-down baseline. 미완 줄을 버렸으면 CT가
    /// 준 그 줄 origin으로 정확 정렬(R50 #3), 없으면(한 줄 rescue 등) 문단 스타일의
    /// 줄 간격까지 포함한 advance만큼 내린다 (R51 #2).
    private static func resumeBaseline(
        after chunk: FrameChunk,
        framePageTop: CGFloat,
        attributedString: NSAttributedString,
        continuesAfterChunk: Bool
    ) -> CGFloat? {
        if let dropped = chunk.droppedLineIndex {
            return framePageTop - chunk.origins[dropped].y - baselineLift(of: chunk.lines[dropped])
        }
        let last = chunk.keepCount - 1
        guard last >= 0 else { return nil }
        let lastBaseline = framePageTop - chunk.origins[last].y - baselineLift(of: chunk.lines[last])
        return lastBaseline + fallbackLineAdvance(
            after: chunk.lines[last],
            attributedString: attributedString,
            continuesAfterChunk: continuesAfterChunk
        )
    }

    /// startLocation의 CTParagraphStyle. 없으면 nil.
    static func paragraphStyle(in attributedString: NSAttributedString, at location: Int) -> CTParagraphStyle? {
        guard attributedString.length > 0 else { return nil }
        let index = min(max(location, 0), attributedString.length - 1)
        guard let value = attributedString.attribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key, at: index, effectiveRange: nil
        ), CFGetTypeID(value as CFTypeRef) == CTParagraphStyleGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! CTParagraphStyle)
    }

    /// CTParagraphStyle의 CGFloat spec 값. 없으면 nil.
    static func paragraphCGFloat(_ spec: CTParagraphStyleSpecifier, in style: CTParagraphStyle?) -> CGFloat? {
        guard let style else { return nil }
        var value: CGFloat = 0
        guard CTParagraphStyleGetValueForSpecifier(style, spec, MemoryLayout<CGFloat>.size, &value)
        else { return nil }
        return value
    }

    /// rescue 단일 줄의 실제 가용 폭 — CT의 tailIndent 규약(≤0이면 컨테이너 trailing
    /// 기준, >0이면 leading 기준 절대 위치)을 반영해 오른쪽 여백을 뺀다. lineOriginX는
    /// CT가 이미 고른 leading origin(첫 줄/이어지는 줄 들여쓰기 포함).
    private static func availableLineWidth(
        containerWidth lineWidth: CGFloat,
        lineOriginX: CGFloat,
        paragraphStyle: CTParagraphStyle?
    ) -> CGFloat {
        let tailIndent = paragraphCGFloat(.tailIndent, in: paragraphStyle) ?? 0
        let trailingEdge = tailIndent > 0 ? tailIndent : lineWidth + tailIndent
        return max(1, trailingEdge - lineOriginX)
    }

    /// 다음 청크에 조사할 origin이 없을 때 세로 advance — typographic 높이에 문단
    /// 스타일의 min/max 줄 높이를 적용하고, 이어지는 청크면 lineSpacingAdjustment도
    /// 더해 uncapped 조판과 같은 줄 간격을 낸다 (R51 #2).
    private static func fallbackLineAdvance(
        after line: CTLine,
        attributedString: NSAttributedString,
        continuesAfterChunk: Bool
    ) -> CGFloat {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        var advance = ascent + descent + leading
        let style = paragraphStyle(in: attributedString, at: CTLineGetStringRange(line).location)
        if let maximum = paragraphCGFloat(.maximumLineHeight, in: style), maximum > 0 {
            advance = min(advance, maximum)
        }
        if let minimum = paragraphCGFloat(.minimumLineHeight, in: style), minimum > 0 {
            advance = max(advance, minimum)
        }
        if continuesAfterChunk {
            advance += paragraphCGFloat(.lineSpacingAdjustment, in: style) ?? 0
        }
        return max(1, advance)
    }

    /// attributedString 안 `hyperlink` 속성 범위마다 줄별 글리프 rect와 URL을
    /// 돌려준다 (페이지 로컬 top-down). 블록 전체가 아니라 링크 텍스트에만
    /// 히트/오버레이를 스코프하는 데 쓴다 (#2). 재조판된 CTLine은 자체 범위가
    /// 0-기준 sub-copy라, attributedString index를 CTLine index로 옮겨 오프셋을 낸다.
    public static func hyperlinkRegions(
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> [(rect: CGRect, url: String)] {
        let length = attributedString.length
        guard length > 0 else { return [] }
        var regions: [(rect: CGRect, url: String)] = []
        // 하이퍼링크 속성이 있는 블록만 CT 재조판한다 (블록마다 framesetting 방지)
        var cachedLines: [HwpDrawnLine]?
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.hyperlink, in: NSRange(location: 0, length: length)
        ) { value, range, _ in
            guard let url = value as? String else { return }
            let drawnLines = cachedLines ?? lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            cachedLines = drawnLines
            for drawn in drawnLines {
                let lineRange = drawn.stringRange
                let lower = max(range.location, lineRange.location)
                let upper = min(range.location + range.length, lineRange.location + lineRange.length)
                guard upper > lower else { continue }
                let ctRange = CTLineGetStringRange(drawn.line)
                func offsetX(atAttributedIndex index: Int) -> CGFloat {
                    let ctIndex = ctRange.location + (index - lineRange.location)
                    return CTLineGetOffsetForStringIndex(drawn.line, ctIndex, nil)
                }
                // RTL 줄은 CT가 하위 논리 인덱스에 더 큰 x 오프셋을 줘 lower>upper가
                // 된다 — min/max로 정규화해 링크 rect를 낸다 (#1).
                let lowerX = drawn.baselineOrigin.x + offsetX(atAttributedIndex: lower)
                let upperX = drawn.baselineOrigin.x + offsetX(atAttributedIndex: upper)
                let minX = min(lowerX, upperX)
                let maxX = max(lowerX, upperX)
                guard maxX > minX else { continue }
                regions.append((
                    rect: CGRect(
                        x: minX, y: drawn.baselineOrigin.y - drawn.ascent,
                        width: maxX - minX, height: drawn.ascent + drawn.descent
                    ),
                    url: url
                ))
            }
        }
        return regions
    }

    /// 이 컨트롤을 감싼 `%hlk` 의 URL — 링크가 붙은 run 중 `controlIndex` 가
    /// 일치하는 것만 본다 (R50 #1). 개체의 링크는 개체가 아니라 부모 문단의
    /// U+FFFC run에 살지만, 지점 포함만으로 고르면 그 개체가 **덮고 있을 뿐인**
    /// 다른 링크까지 살아난다.
    static func wrapperHyperlinkURL(
        in paragraphs: [HwpLaidOutParagraph], paragraphId: UInt32, controlIndex: Int
    ) -> String? {
        guard controlIndex >= 0 else { return nil }
        // 서수는 문단마다 0부터 다시 시작하므로 **그 개체를 낸 문단에서만** 찾는다
        // (R51 #1) — 컨테이너 전체를 훑으면 앞 문단의 같은 서수 링크가 열린다.
        for paragraph in paragraphs where paragraph.paragraphId == paragraphId {
            let attributed = paragraph.attributedString
            var url: String?
            attributed.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, range, stop in
                guard value as? Int == controlIndex else { return }
                url = attributed.attribute(
                    HwpAttributedStringKey.hyperlink, at: range.location, effectiveRange: nil
                ) as? String
                stop.pointee = true
            }
            if let url {
                return url
            }
        }
        return nil
    }

    /// 그려진 텍스트의 줄 상자들 — "이 지점에 글자가 칠해졌는가" 판정용 (R54).
    ///
    /// 선택 하이라이트와 **같은 정의** (`HwpDrawnLine.selectionRect`) 를 쓴다:
    /// 문단 rect는 줄 사이 여백과 짧은 줄의 빈 오른쪽까지 품어, 그것으로 claim하면
    /// 아무것도 안 그린 자리에서 아래 블록의 보이는 링크를 막는다.
    public static func textLineRegions(
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> [CGRect] {
        guard attributedString.length > 0 else { return [] }
        return lines(
            attributedString: attributedString, origin: origin, lineWidth: lineWidth
        ).map(\.selectionRect)
    }

    /// slight-overflow 한 줄의 CTLine과 타이포그래피 메트릭.
    public struct SlightOverflowLine {
        public let line: CTLine
        public let ascent: CGFloat
        public let descent: CGFloat
        public let leading: CGFloat
    }

    /// 개행 없는 문단이 허용 배율 (`HwpRenderTuning.Text.slightOverflowWidthRatio`)
    /// 이내로 폭을 넘는 한 줄인지 — 렌더 (slightOverflowSingleLine)와 측정
    /// (`HwpParagraphLayout.layout`)이 이 술어를 공유해 "측정은 2줄 ↔ 렌더는
    /// 1줄" 어긋남 (문단 높이·페이지 절단 vs 실제 잉크)을 구조적으로 막는다.
    public static func slightOverflowLineMetrics(
        attributedString: NSAttributedString,
        lineWidth: CGFloat
    ) -> SlightOverflowLine? {
        // 큰 개행 없는 문단이 청크 캡보다 먼저 전체를 shaping(CTLineCreate)하지
        // 않게 길이로 먼저 거른다 — 한 줄 slight-overflow는 한 줄 폭에 들어가므로
        // maximumLineFrames 문자를 넘으면 단일 줄일 수 없다. 길이 체크를
        // contains("\n")(전체 스캔) 앞에 둬 거대 문자열 materialize도 피한다 (R50 #1).
        guard attributedString.length > 0,
              attributedString.length <= HwpParagraphLayout.maximumLineFrames,
              !attributedString.string.contains("\n")
        else { return nil }
        let line = CTLineCreateWithAttributedString(attributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let naturalWidth = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        )
        guard naturalWidth > lineWidth,
              naturalWidth <= lineWidth * HwpRenderTuning.Text.slightOverflowWidthRatio
        else { return nil }
        return SlightOverflowLine(line: line, ascent: ascent, descent: descent, leading: leading)
    }

    /// 폭을 허용 배율 이내로 넘는 개행 없는 한 줄 문단이면 줄바꿈 없이
    /// 한 줄로 배치한다. 가운데 정렬이면 초과분을 좌우로 반씩 넘긴다.
    private static func slightOverflowSingleLine(
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> HwpDrawnLine? {
        guard
            let overflow = slightOverflowLineMetrics(
                attributedString: attributedString, lineWidth: lineWidth
            )
        else { return nil }
        let line = overflow.line
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ascent = overflow.ascent
        let descent = overflow.descent
        var offsetX: CGFloat = 0
        if let style = attributedString.attribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            at: 0, effectiveRange: nil
        ), CFGetTypeID(style as CFTypeRef) == CTParagraphStyleGetTypeID() {
            var alignment = CTTextAlignment.natural
            let paragraphStyle = style as! CTParagraphStyle // swiftlint:disable:this force_cast
            CTParagraphStyleGetValueForSpecifier(
                paragraphStyle, .alignment,
                MemoryLayout<CTTextAlignment>.size, &alignment
            )
            if alignment == .center {
                offsetX = (lineWidth - naturalWidth) / 2
            } else if alignment == .right {
                // 우측 정렬 overflow 줄은 오른쪽 끝을 맞추기 위해 음수 오프셋 —
                // x=0 시작이면 잉크가 왼쪽으로 밀린다 (#3).
                offsetX = lineWidth - naturalWidth
            }
        }
        return HwpDrawnLine(
            line: line,
            stringRange: NSRange(location: 0, length: attributedString.length),
            baselineOrigin: CGPoint(
                x: origin.x + offsetX,
                y: origin.y + ascent - baselineLift(of: line)
            ),
            ascent: ascent,
            descent: descent
        )
    }

    /// 한글 줄 모델은 텍스트든 개체든 베이스라인을 칸 높이의 앵커 비율
    /// (`HwpRenderTuning.Text.baselineAnchorRatio`) 지점에 둔다. 키 큰
    /// 인라인 개체 (run delegate)가 있으면 개체 ascent 기준
    /// (`HwpRenderTuning.Text.baselineLiftRatio`), 아니면 폰트 ascent 기준.
    public static func baselineLift(of line: CTLine) -> CGFloat {
        let metrics = lineMetrics(of: line)
        guard metrics.maxSize > 0 else { return 0 }
        let fontLift = max(
            0, metrics.maxAscent - metrics.maxSize * HwpRenderTuning.Text.baselineAnchorRatio
        )
        guard metrics.delegateAscent > metrics.maxAscent else { return fontLift }
        return max(fontLift, metrics.delegateAscent * HwpRenderTuning.Text.baselineLiftRatio)
    }

    /// 인라인 개체 줄에서 밑줄이 되돌아갈 양 — 실물은 밑줄을 개체 하단
    /// (lift 전 베이스라인) 근처에 남긴다 (공공누리 실물 실측)
    public static func underlineReturnDrop(of line: CTLine) -> CGFloat {
        guard baselineLift(of: line) > 0 else { return 0 }
        let metrics = lineMetrics(of: line)
        guard metrics.delegateAscent > metrics.maxAscent, metrics.maxSize > 0
        else { return 0 }
        return metrics.delegateAscent * HwpRenderTuning.Text.baselineLiftRatio
    }

    private struct LineMetrics {
        var maxSize: CGFloat = 0
        var maxAscent: CGFloat = 0
        var delegateAscent: CGFloat = 0
    }

    private static func lineMetrics(of line: CTLine) -> LineMetrics {
        var metrics = LineMetrics()
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return metrics }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
            guard attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] == nil
            else {
                var ascent: CGFloat = 0
                _ = CTRunGetTypographicBounds(
                    run, CFRange(location: 0, length: 0), &ascent, nil, nil
                )
                metrics.delegateAscent = max(metrics.delegateAscent, ascent)
                continue
            }
            guard let value = attributes?[kCTFontAttributeName as NSAttributedString.Key],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
            else { continue }
            // swiftlint:disable:next force_cast
            let font = value as! CTFont
            metrics.maxSize = max(metrics.maxSize, CTFontGetSize(font))
            metrics.maxAscent = max(metrics.maxAscent, CTFontGetAscent(font))
        }
        return metrics
    }
}
