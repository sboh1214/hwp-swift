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
        // 렌더/선택 경로도 측정(HwpParagraphLayout.layout)과 같은 줄 상한을 따른다 —
        // CTFramesetterCreateFrame이 입력 범위의 CTLine을 즉시 만들므로, 각 줄이
        // 최소 1 UTF-16 유닛을 소비함을 이용해 길이를 상한해 스트림 한도 크기의
        // 좁은 문단이 자원을 고갈시키지 못하게 한다. 상한 이하(모든 정상 블록)는
        // 전 범위 그대로라 렌더가 불변이다 (R47 #1).
        let length = min(attributedString.length, max(0, maxLineFrames))
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: length),
            nil,
            CGSize(width: lineWidth, height: .greatestFiniteMagnitude),
            nil
        )
        let textHeight = max(ceil(suggestedSize.height), 1)
        // CT 프레임은 y-up 로컬 상자에서 조판된다. top-down 페이지 좌표의
        // 베이스라인 y = origin.y + textHeight − (상자 내 y-up 원점) —
        // 페이지 높이는 소거되므로 필요 없다.
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: lineWidth, height: textHeight),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: length), path, nil
        )
        guard let frameLines = CTFrameGetLines(frame) as? [CTLine], !frameLines.isEmpty
        else { return [] }
        var ctOrigins = [CGPoint](repeating: .zero, count: frameLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &ctOrigins)

        return frameLines.enumerated().map { index, frameLine in
            let lift = baselineLift(of: frameLine)
            let replacement = HwpWordJustification.justifiedLine(
                frameLine: frameLine,
                attributedString: attributedString,
                availableWidth: lineWidth - ctOrigins[index].x
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
                    x: origin.x + ctOrigins[index].x + (replacement?.xOffset ?? 0),
                    y: origin.y + textHeight - ctOrigins[index].y - lift
                ),
                ascent: ascent,
                descent: descent
            )
        }
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
        guard attributedString.length > 0,
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
