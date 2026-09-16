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
    /// 이 줄이 **문단의 마지막 줄**인지 — 단위 문자열의 끝에 닿고, 그 문자열이 다음 단·
    /// 쪽으로 이어지는 조각(`hwp.continuedParagraphFragment`)이 아닐 때 (양쪽 정렬의
    /// 마지막 줄 판정과 같은 규약). 렌더러는 MS 워드 호환 문단 끝 상자
    /// (`hwp.msWordParagraphEndBox`, #187)를 이 줄의 줄 상자에만 합친다 — 상자는 문단
    /// 전체에 실리므로 줄 판정은 키가 아니라 이 값이다. 이어짐 표식은 쪽 흐름·절대 캐시
    /// run·다단 균형·표 행·각주의 모든 분할 경로가 단다 (PR 리뷰).
    public let endsParagraph: Bool

    /// 줄의 선택 하이라이트 영역 (top-down 페이지 좌표)
    ///
    /// **글자 위치(`hwp.glyphBaselineOffset`)로 옮겨진 글리프를 따라가지 않는다** — 한글도
    /// 그렇다 (2026-09-14 실측: `CharShape` 픽스처의 '글자위치 30' 줄만 선택하면 하이라이트
    /// 상단이 이웃 줄들과 **같은 격자**(81px 간격)에 있고 글리프만 그 안에서 7px 내려간다).
    /// 잉크가 닿는 범위가 필요한 쪽은 `paintedRect`다.
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
/// 규칙 (slight-overflow 단일 줄, 양쪽 정렬 재조판, 베이스라인 앵커)으로 계산한다.
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
        // 측정(HwpParagraphLayout.layout)과 HwpLineBreaker.nextFrameChunk를 공유해
        // 청크 경계를 실제 CTLine 시작에 맞춘다 — 미완 줄은 버려 다음 청크에서 온전히
        // 재조판, 넓은 단일 줄은 안 쪼갠다. 단일 청크(모든 정상 블록)는 문단 전체가
        // 한 프레임이라 렌더 불변 (R48·R50).
        var result: [HwpDrawnLine] = []
        var startLocation = 0
        // 다음 청크 첫 줄의 **줄 상자 상단** top-down y — 첫 청크는 블록 상단이고, 이월은
        // 앞 청크 마지막 줄 상자 상단 + 그 줄 전진량이다. baseline이 아니라 상자 상단을
        // 넘긴다: 버린 미완 줄은 다음 청크에서 온전히 재조판되며 앵커(상자 높이)가 달라질 수
        // 있어, baseline을 넘기면 그 앵커가 소거되지 않아 뒤 줄 전체가 밀린다 (#178).
        var boxTop = origin.y
        while startLocation < fullLength, result.count < lineBudget {
            guard let chunk = HwpLineBreaker.nextFrameChunk(
                framesetter: framesetter, typesetter: typesetter,
                attributedString: attributedString,
                startLocation: startLocation, fullLength: fullLength,
                remainingLineBudget: lineBudget - result.count, lineWidth: lineWidth
            ) else { break }
            // 줄 상자 상단과 baseline — 첫 줄 상자 상단은 블록 상단(이월이면 재개 상자
            // 상단)에 핀하고, 나머지는 줄별 전진량으로 타일한다 (`lineGeometries`).
            let geometries = Self.lineGeometries(of: chunk, in: attributedString, base: boxTop)
            for index in 0 ..< chunk.keepCount {
                result.append(drawnLine(
                    frameLine: chunk.lines[index],
                    attributedString: attributedString,
                    placement: Placement(
                        baseline: geometries[index].baseline,
                        originX: origin.x,
                        ctOriginX: chunk.origins[index].x
                    ),
                    lineWidth: lineWidth
                ))
            }
            if let last = geometries.last {
                boxTop = last.boxTop + last.advance
            }
            guard chunk.nextStart > startLocation else { break }
            startLocation = chunk.nextStart
        }
        return result
    }

    /// 한 줄이 놓일 자리 — `baseline`은 `lines`가 `lineGeometries`로 구한 top-down
    /// baseline이다. **baseline은 앵커가 정한다** (#178) — CT·글꼴의 ascent는 세로 배치에
    /// 쓰이지 않는다.
    private struct Placement {
        let baseline: CGFloat
        /// 블록 원점 x
        let originX: CGFloat
        /// CT가 준 이 줄의 프레임 내 x (문단 들여쓰기·정렬)
        let ctOriginX: CGFloat
    }

    private static func drawnLine(
        frameLine: CTLine,
        attributedString: NSAttributedString,
        placement: Placement,
        lineWidth: CGFloat
    ) -> HwpDrawnLine {
        let replacement = HwpWordJustification.justifiedLine(
            frameLine: frameLine,
            attributedString: attributedString,
            availableWidth: lineWidth - placement.ctOriginX
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
                x: placement.originX + placement.ctOriginX + (replacement?.xOffset ?? 0),
                y: placement.baseline
            ),
            ascent: ascent,
            descent: descent,
            endsParagraph: endsParagraph(range, in: attributedString)
        )
    }

    /// `range`로 끝나는 줄이 문단의 마지막 줄인지 (`HwpDrawnLine.endsParagraph`).
    static func endsParagraph(_ range: CFRange, in attributedString: NSAttributedString) -> Bool {
        let length = attributedString.length
        guard length > 0, range.location + range.length >= length else { return false }
        return attributedString.attribute(
            HwpAttributedStringKey.continuedParagraphFragment, at: length - 1, effectiveRange: nil
        ) == nil
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
        // 밴드도 줄 캐시 옆에 같이 둔다: `glyphOffsetBands`는 줄의 CTRun을 전수로 돌며
        // CTRunGetAttributes를 브리징하는데, 스팬마다 다시 부르면 (스팬 × 줄)만큼 값을
        // 치른다 — 옮겨진 run이 하나도 없어도 그렇다 (실측 median: 40스팬 ~13줄
        // 1.16 → 0.74ms, 120스팬 ~40줄 4.02 → 2.91ms).
        var cachedBands: [[GlyphOffsetBand]]?
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.hyperlink, in: NSRange(location: 0, length: length)
        ) { value, range, _ in
            guard let url = value as? String else { return }
            let drawnLines = cachedLines ?? lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            )
            cachedLines = drawnLines
            let bandsByLine = cachedBands ?? glyphOffsetBands(
                ofLines: drawnLines, in: attributedString
            )
            cachedBands = bandsByLine
            for (lineIndex, drawn) in drawnLines.enumerated() {
                appendHyperlinkRects(
                    of: drawn, spanRange: range, bands: bandsByLine[lineIndex],
                    url: url, into: &regions
                )
            }
        }
        return regions
    }

    /// 그려진 텍스트의 줄 상자들 — "이 지점에 글자가 칠해졌는가" 판정용 (R54).
    ///
    /// 선택 하이라이트(`HwpDrawnLine.selectionRect`)에 **글자 위치로 옮겨진 run마다 그
    /// run의 잉크 가로 범위만** 더한 `paintedRects`를 쓴다 — 줄 전체 폭에 최대 오프셋을
    /// 걸면 안 옮겨진 run 아래의 빈 띠까지 claim해 그 자리의 탭이 뒤 층의 보이는 링크를
    /// 막는다. 문단 rect를 쓰지 않는 이유는 종전과 같다 — 줄 사이 여백과 짧은 줄의 빈
    /// 오른쪽까지 품어, 그것으로 claim하면 아무것도 안 그린 자리에서 아래 블록의 보이는
    /// 링크를 막는다. 반대로 줄 상자만 쓰면 **그려진** 글자가 claim 밖으로 나가 그 위의
    /// 탭이 뒤 층으로 내려간다(한글은 선택 상자를 안 옮기지만 칠은 옮긴다 —
    /// `selectionRect`의 실측 주석).
    public static func textLineRegions(
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> [CGRect] {
        guard attributedString.length > 0 else { return [] }
        let drawnLines = lines(
            attributedString: attributedString, origin: origin, lineWidth: lineWidth
        )
        let bandsByLine = glyphOffsetBands(ofLines: drawnLines, in: attributedString)
        return zip(drawnLines, bandsByLine).flatMap { $0.paintedRects(bands: $1) }
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
    ///
    /// **문단 전체**의 규칙이다 — 문단을 잰 줄에서 잘라낸 조각
    /// (`HwpAttributedStringKey.measuredLineFragment`)에는 적용하지 않는다 (#166). 조각
    /// 블록의 높이는 문단 전체 측정의 줄바꿈에서 왔는데, 문단 전체로는 접히지 않던 두
    /// 줄이 조각만으로는 허용 배율 안에 들 수 있어 여기서 접으면 측정은 2줄 ↔ 렌더는
    /// 1줄이 되고 조각 아래가 빈다. 측정(`layout`)도 같은 술어를 쓰므로 조각을 다시
    /// 재는 경로(비등폭 단 이월의 `HwpPaginator.fragmentAnchorLines`)와 렌더가 같이 간다.
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
              !isMeasuredLineFragment(attributedString),
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

    /// 문단 전체를 잰 줄에서 잘라낸 조각인지 (#166). 표식은 조각 문자열 전체에
    /// 붙으므로(`HwpParagraphLayout.measuredLineFragment`) 첫 글자만 본다 — 조각을
    /// 다시 자르거나(표 다중 쪽 분할) 마커를 번호로 바꾸는(`renumberingNoteMarkers`,
    /// 바뀐 글자의 속성을 물려받는다) 뒤 가공도 첫 글자의 표식을 보존한다.
    static func isMeasuredLineFragment(_ attributedString: NSAttributedString) -> Bool {
        guard attributedString.length > 0 else { return false }
        return attributedString.attribute(
            HwpAttributedStringKey.measuredLineFragment, at: 0, effectiveRange: nil
        ) != nil
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
        let ascent = overflow.ascent
        let descent = overflow.descent
        let offsetX = slightOverflowAlignmentOffset(
            attributedString: attributedString, lineWidth: lineWidth, line: line
        )
        return HwpDrawnLine(
            line: line,
            stringRange: NSRange(location: 0, length: attributedString.length),
            baselineOrigin: CGPoint(
                x: origin.x + offsetX,
                y: origin.y + baselineAnchor(of: line)
            ),
            ascent: ascent,
            descent: descent,
            endsParagraph: endsParagraph(
                CFRange(location: 0, length: attributedString.length), in: attributedString
            )
        )
    }

    /// slight-overflow 한 줄의 가로 오프셋 — 가운데 정렬은 초과분을 좌우로 반씩,
    /// 오른쪽 정렬은 오른쪽 끝을 맞추기 위해 음수 오프셋(x=0 시작이면 잉크가 왼쪽으로
    /// 밀린다, #3). 렌더(`slightOverflowSingleLine`)와 접힌 조각의 한 줄 앵커
    /// (`HwpParagraphLayout.fragmentLineFramesAsDrawn`)가 같은 산식을 써야 개체 앵커
    /// x가 그려진 글자와 맞는다.
    static func slightOverflowAlignmentOffset(
        attributedString: NSAttributedString,
        lineWidth: CGFloat,
        line: CTLine
    ) -> CGFloat {
        guard let style = attributedString.attribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            at: 0, effectiveRange: nil
        ), CFGetTypeID(style as CFTypeRef) == CTParagraphStyleGetTypeID() else { return 0 }
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var alignment = CTTextAlignment.natural
        let paragraphStyle = style as! CTParagraphStyle // swiftlint:disable:this force_cast
        CTParagraphStyleGetValueForSpecifier(
            paragraphStyle, .alignment,
            MemoryLayout<CTTextAlignment>.size, &alignment
        )
        switch alignment {
        case .center: return (lineWidth - naturalWidth) / 2
        case .right: return lineWidth - naturalWidth
        default: return 0
        }
    }
}
