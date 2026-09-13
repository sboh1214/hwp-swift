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
        // 이월 시 다음 청크 첫 줄의 **줄 상자 상단** top-down y. nil이면 첫 청크.
        var resumeBoxTop: CGFloat?
        // 이월 시 그 줄의 **배치 ascent와 슬롯 지표** — 새 프레임의 첫 슬롯 특례를 타지 않게
        // 넘기고, 재조판된 줄이 같은 슬롯인지 지표로 가른다.
        var resumeSlot: (ascent: CGFloat, metrics: LineMetrics)?
        while startLocation < fullLength, result.count < lineBudget {
            guard let chunk = HwpLineBreaker.nextFrameChunk(
                framesetter: framesetter, typesetter: typesetter,
                attributedString: attributedString,
                startLocation: startLocation, fullLength: fullLength,
                remainingLineBudget: lineBudget - result.count, lineWidth: lineWidth
            ) else { break }
            // 줄 상자 상단과 baseline — 첫 줄 상자 상단은 블록 상단 (이월이면 재개 상자
            // 상단) 에 핀하고, 나머지는 CT 슬롯을 따른다 (`lineGeometries`).
            let geometries = Self.lineGeometries(
                of: chunk, in: attributedString, base: resumeBoxTop ?? origin.y,
                resume: resumeSlot
            )
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
            let resume = Self.resume(
                after: chunk, geometries: geometries,
                attributedString: attributedString,
                continuesAfterChunk: chunk.nextStart < fullLength
            )
            resumeBoxTop = resume?.boxTop
            resumeSlot = resume.map { (ascent: $0.ascent, metrics: $0.metrics) }
            guard chunk.nextStart > startLocation else { break }
            startLocation = chunk.nextStart
        }
        return result
    }

    /// 한 줄이 놓일 자리 — `baseline`은 `lines`가 `lineGeometries`로 구한 top-down
    /// baseline이다. CT·글꼴의 ascent는 줄 상자 상단을 찾는 데만 쓰이고 **baseline 자체는
    /// 앵커가 정한다** (#178).
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
            descent: descent
        )
    }

    /// 이월 후 다음 청크 첫 줄이 놓일 **줄 상자 상단과 배치 ascent**. 미완 줄을 버렸으면 CT가
    /// 준 그 줄 origin으로 정확 정렬(R50 #3), 없으면(한 줄 rescue 등) 그 줄 슬롯만큼 내린다.
    ///
    /// **baseline이 아니라 상자 상단을 넘긴다** — 버린 줄은 미완이라 다음 청크에서
    /// 온전히 재조판된 줄과 앵커가 다를 수 있고 (기본 크기가 그 경계에 걸리면 갈린다),
    /// baseline을 넘기면 그 앵커가 다음 청크에서 소거되지 않아 뒤 줄 전체가 밀린다.
    ///
    /// **배치 ascent도 함께 넘긴다** — 다음 청크는 새 프레임이고 CT는 프레임 첫 슬롯을 뒤 슬롯
    /// 보다 크게 잡으므로 (leading 0 글꼴 0.3pt, Hiragino Sans 5.0pt), 그 값을 기준으로
    /// 복원하면 특례가 경계마다 되풀이돼 뒤 줄이 밀린다 (실측: Hiragino 하한 10pt 문단이 예산
    /// 20에서 33.6pt, Helvetica 12.0pt). 버린 줄은 다음 청크에서 같은 슬롯 자리에 다시
    /// 놓이므로 이 청크에서 구한 그 줄의 배치 ascent가 그 자리의 값이다. 미완 줄이 없는
    /// (rescue·경계 일치) 이월은 이 청크 **마지막 줄**의 값을 넘긴다 — 다음 청크 첫 줄은 이
    /// 청크에 없던 줄이지만, 같은 문단이 이어지는 흔한 경우에 그 값이 그 자리의 값이고 새
    /// 프레임의 첫 슬롯 특례를 타는 것보다 가깝다 (실측: Helvetica 하한 10pt 문단 예산 13의
    /// 드리프트가 1.50 → 0.00pt).
    private static func resume(
        after chunk: HwpLineBreaker.FrameChunk,
        geometries: [LineGeometry],
        attributedString: NSAttributedString,
        continuesAfterChunk: Bool
    ) -> Resume? {
        if let dropped = chunk.droppedLineIndex, dropped < geometries.count {
            return Resume(geometry: geometries[dropped])
        }
        let last = chunk.keepCount - 1
        guard last >= 0, last < geometries.count else { return nil }
        // 미완 줄이 없으면 다음 청크 첫 줄은 이 청크에 없던 줄이다 — 그래도 **이 줄의** 배치
        // ascent를 넘긴다. 같은 문단이 이어지는 흔한 경우에 그 값이 곧 그 자리의 값이고, 새
        // 프레임의 첫 슬롯 특례를 타는 것보다 가깝다 (실측: Helvetica 하한 10pt 문단 예산 13의
        // 드리프트가 1.50 → 0.00pt).
        let advance = fallbackLineAdvance(
            after: geometries[last],
            line: chunk.lines[last],
            attributedString: attributedString,
            continuesAfterChunk: continuesAfterChunk
        )
        return Resume(
            boxTop: geometries[last].boxTop + advance,
            ascent: geometries[last].ascent,
            metrics: geometries[last].metrics
        )
    }

    /// 청크 이월이 다음 청크에 넘기는 것 — 첫 줄 상자 상단과, 그 자리의 배치 ascent를 쓸 수
    /// 있는지 가릴 슬롯 지표.
    private struct Resume {
        let boxTop: CGFloat
        let ascent: CGFloat
        let metrics: LineMetrics

        init(boxTop: CGFloat, ascent: CGFloat, metrics: LineMetrics) {
            self.boxTop = boxTop
            self.ascent = ascent
            self.metrics = metrics
        }

        /// 버린 줄의 기하를 그대로 넘긴다 — 그 줄은 다음 청크에서 같은 슬롯 자리에 다시 놓인다.
        init(geometry: LineGeometry) {
            boxTop = geometry.boxTop
            ascent = geometry.ascent
            metrics = geometry.metrics
        }
    }

    /// 다음 청크에 조사할 origin이 없을 때 세로 advance — 그 줄의 **슬롯**
    /// (`배치 ascent + baseline 아래 몫`) 이고, 이어지는 청크면 줄 뒤 간격도 더한다 (R51 #2).
    ///
    /// 종전에는 `CTLineGetTypographicBounds`의 ascent + descent + leading에 min/max 줄 높이를
    /// 적용했는데, 보고 ascent는 배치값이 아니어서 (#178) 전진량이 CT 슬롯과 달랐다 — Helvetica
    /// 10pt·하한 10pt 문단에서 10.0pt를 내 실제 12.0pt보다 좁았다. 슬롯은 `lineGeometries`가
    /// 이미 정확히 구해 두므로 그 값을 쓴다.
    private static func fallbackLineAdvance(
        after geometry: LineGeometry,
        line: CTLine,
        attributedString: NSAttributedString,
        continuesAfterChunk: Bool
    ) -> CGFloat {
        var advance = geometry.ascent + geometry.below
        if continuesAfterChunk {
            let style = HwpLineBreaker.paragraphStyle(
                in: attributedString, at: CTLineGetStringRange(line).location
            )
            let spacing = HwpLineBreaker.paragraphCGFloat(.lineSpacingAdjustment, in: style)
            advance += max(0, spacing ?? 0)
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
            descent: descent
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
