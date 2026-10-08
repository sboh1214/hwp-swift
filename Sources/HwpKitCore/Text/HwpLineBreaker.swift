import CoreGraphics
import CoreText
import Foundation

/// 측정과 렌더가 **공유하는** 줄바꿈 코어.
///
/// `HwpParagraphLayout.layout`(측정)과 `HwpDrawnTextLayout.lines`(렌더)가 둘 다
/// `nextFrameChunk`를 불러 같은 `CTFramesetterSuggestFrameSizeWithConstraints`
/// 상자에서 같은 `CTLine` 경계를 얻는다 — 줄바꿈 사실(문자 분할·origin)이
/// 정의상 일치한다. 줄바꿈 뒤의 **세로 전진량**도 공유한다 — 둘 다
/// `HwpLineAdvance.advanceParts(of:in:)`로 줄별 상자 높이 × 줄 간격 규칙을 쌓는다 (#180).
///
/// 계약 네 가지는 `Sources/HwpKitCore/AGENTS.md`("측정·렌더 공유 줄바꿈 코어")가
/// 소유한다 — 줄 예산 절단, 미완 마지막 줄 이월, 한 시각 줄 재프레이밍,
/// `keepCount` 하드 상한.
///
/// **한쪽만 쓰는 헬퍼를 여기 넣지 말 것.** 한쪽만 쓰는 멤버가 들어오면 이 타입 이름이
/// 다시 거짓말을 한다.
enum HwpLineBreaker {
    /// 한 프레임 청크의 조판 결과 — 두 루프(lines/layout)가 공유하는 경계 결정.
    struct FrameChunk {
        let lines: [CTLine]
        /// CT가 준 줄 origin — **x만** 쓴다 (문단 들여쓰기·정렬). y는 CT 슬롯 기준이라
        /// 세로 배치에 쓰지 않는다 (`HwpLineAdvance`).
        let origins: [CGPoint]
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

        func frame(from start: Int, length: Int) -> (lines: [CTLine], origins: [CGPoint])? {
            let range = CFRange(location: start, length: length)
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
            let aligned = overflowStartAligned(origins, lines: lines, in: attributedString)
            return (lines, lineEndSpacingAligned(
                aligned, lines: lines, in: attributedString, containerWidth: lineWidth
            ))
        }

        guard var chunk = frame(from: startLocation, length: probeLength) else { return nil }
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
            if extended > probeLength, let remade = frame(from: startLocation, length: extended) {
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
        if let refit = lineEndSpacingRefit(
            chunk: chunk, keepCount: keepCount,
            context: RefitContext(
                typesetter: typesetter, attributedString: attributedString, lineWidth: lineWidth,
                chunkEnd: startLocation + length, cutBeforeEnd: cutBeforeEnd,
                lineBudget: remainingLineBudget
            ),
            frame: frame(from:length:)
        ) {
            return refit
        }
        let lastRange = CTLineGetStringRange(chunk.lines[keepCount - 1])
        let nextStart = lastRange.location + lastRange.length
        guard nextStart > startLocation else { return nil }
        return FrameChunk(
            lines: chunk.lines, origins: chunk.origins, keepCount: keepCount, nextStart: nextStart
        )
    }

    /// 가용 폭보다 넓은 줄을 **줄 시작**에 둔 origin (#254).
    ///
    /// CT는 가운데·오른쪽 정렬 줄의 origin을 남는 폭(가용 폭 − 줄 폭)으로 밀므로, 줄보다 넓은
    /// 줄은 줄 시작보다 왼쪽(문단 여백·본문 밖)에서 시작한다. 한글은 그런 줄을 정렬과 무관하게
    /// 줄 시작(문단 왼쪽 여백 + 첫 줄이면 들여쓰기)에 두고 오른쪽으로만 넘긴다 — 한컴오피스 한글
    /// 12.30(build 6523) PDF 실측(2026-10-05, `probes/254`): 본문 425.2pt에 450pt 표·사각형을
    /// 실은 가운데·오른쪽·양쪽·배분 정렬 줄이 모두 본문 왼쪽 85.08pt, 문단 왼쪽 여백 20pt면
    /// 105.12pt, 첫 줄 들여쓰기 20pt면 105.12pt, 문단 폭 385pt의 400pt 표(가운데 정렬)도
    /// 105.12pt에서 시작했다(우리는 72.64·60.24·97.64pt).
    ///
    /// **개체 줄에 한정한 규칙이 아니다** — 개체가 없는 글줄도 나눌 수 없는 글자 하나가 줄보다
    /// 넓으면 같다 (#254 PR 리뷰 실측, `probes/254/review`): 좌우 여백 150pt(문단 폭 125.2pt)
    /// 문단의 150pt '가'(145.5pt)는 왼쪽·가운데·오른쪽 정렬 모두 235.08pt(줄 시작), 칸 폭 40pt
    /// 셀의 60pt '다'(58.2pt)도 셋 다 85.08pt(셀 왼쪽)에서 시작했다 — CT 정렬 오프셋대로면 가운데
    /// 224.89·75.94pt, 오른쪽 214.74·66.84pt다. 넘치지 않는 100pt '나'는 정렬대로 놓였다. 그래서
    /// 줄에 개체가 있는지를 보지 않는다. 넘치지 않는 줄은 origin이 줄 시작 이상이라 그대로다.
    /// 개행 없는 한 줄 문단이 컨테이너 폭을 6% 이내로 넘으면 이 코어가 아니라 slight-overflow
    /// 허용(`HwpDrawnTextLayout.slightOverflowLineMetrics`)이 맡아 글자 하나가 넓은 글줄도 CT 정렬
    /// 오프셋을 받는다 — 한글은 그 띠도 줄 시작이라 남은 차이다 (AGENTS.md "넓은 표·흐름 표의 가로 자리").
    /// 왼쪽·양쪽·자연 정렬은
    /// CT가 이미 줄 시작에 두므로 보지 않는다 (자연 정렬의 오른쪽→왼쪽 문단을 건드리지 않는다).
    /// 측정(`HwpParagraphLayout`)과 렌더(`HwpDrawnTextLayout`)가 이 코어의 origin을 함께 쓰므로
    /// 줄 앵커·글리프·선택 영역이 한 자리를 본다.
    static func overflowStartAligned(
        _ origins: [CGPoint],
        lines: [CTLine],
        in attributedString: NSAttributedString
    ) -> [CGPoint] {
        var adjusted = origins
        let string = attributedString.string as NSString
        for index in origins.indices where index < lines.count {
            let location = CTLineGetStringRange(lines[index]).location
            let style = paragraphStyle(in: attributedString, at: location)
            guard let alignment = textAlignment(of: style),
                  alignment == .center || alignment == .right
            else { continue }
            let firstLine = paragraphCGFloat(.firstLineHeadIndent, in: style) ?? 0
            let head = paragraphCGFloat(.headIndent, in: style) ?? 0
            // 어느 들여쓰기보다도 오른쪽이면 넘친 줄일 수 없다 — 문단 경계 조회를 건너뛴다.
            guard origins[index].x < max(firstLine, head) else { continue }
            // CT 문단의 첫 줄인가 — 직전 글자가 문단 구분자(LF·CR·U+2029)면 그렇다. 원문을 앞으로
            // 훑는 `paragraphRange`는 줄마다 O(문단 길이)라 긴 문단 조판이 이차가 된다.
            let startsParagraph = location == 0
                || (location <= string.length
                    && HwpLineAdvance.isParagraphSeparator(string.character(at: location - 1)))
            let lineStart = startsParagraph ? firstLine : head
            if origins[index].x < lineStart {
                adjusted[index].x = lineStart
            }
        }
        return adjusted
    }

    /// 음수 자간의 줄 끝 (#260) — 한글은 줄의 마지막 글자에 자간을 주지 않고 줄을 맞춘다
    /// (`HwpLetterSpacing.lineEndSpacing`). CoreText는 양수 자간(tracking)은 줄 끝에서 빼고 재지만
    /// 음수 자간(kern·tracking)은 넣고 재므로, 음수 자간 줄은 마지막 글자의 자간만큼 **더 담긴다** (실측: Menlo
    /// 20pt 라틴 자간 −20% `aaaaa` × 8의 첫 줄이 한글은 줄 폭 388.0pt부터 7단어, 우리는 385.5pt부터).
    ///
    /// 커밋할 줄 중 마지막 글자의 자간을 빼고 재면 가용 폭을 넘는 줄을 그 자간을 뺀 폭으로 다시
    /// 나누고, 그 뒤는 새 프레임으로 다시 조판해 **한 청크로** 잇는다 — 청크를 쪼개면 정상 문단이
    /// 한 번의 호출로 덮인다는 전제(`HwpLayoutRenderParitySweepTests`의 3-way 대조, 측정·렌더 루프의
    /// "단일 청크" 주석)가 깨진다. 이어 붙인 줄의 origin은 각 프레임의 것이다 — 문단 중간에서
    /// 시작하는 프레임도 CoreText가 이어지는 줄 들여쓰기를 준다. 더 짧게 나눌 수 없는 줄(나눌 자리
    /// 없는 낱말)은 CoreText의 줄을 그대로 둔다. 예산 절단·미완 줄 이월 계약은 마지막 프레임에 같은
    /// 규칙으로 건다.
    private static func lineEndSpacingRefit(
        chunk: (lines: [CTLine], origins: [CGPoint]),
        keepCount: Int,
        context: RefitContext,
        frame: (Int, Int) -> (lines: [CTLine], origins: [CGPoint])?
    ) -> FrameChunk? {
        guard var violation = firstLineEndOverflow(
            in: chunk.lines, keepCount: keepCount, context: context
        ) else { return nil }
        var lines: [CTLine] = []
        var origins: [CGPoint] = []
        var current = chunk
        var currentKeep = keepCount
        var nextStart: Int?
        while true {
            lines += current.lines[0 ..< violation.index]
            origins += current.origins[0 ..< violation.index]
            let start = CTLineGetStringRange(current.lines[violation.index]).location
            guard lines.count < context.lineBudget,
                  let single = frame(start, violation.length), let line = single.lines.first
            else {
                lines += current.lines[violation.index ..< currentKeep]
                origins += current.origins[violation.index ..< currentKeep]
                break
            }
            lines.append(line)
            origins.append(single.origins[0])
            let restStart = start + CTLineGetStringRange(line).length
            guard restStart < context.chunkEnd, lines.count < context.lineBudget,
                  let rest = frame(restStart, context.chunkEnd - restStart)
            else {
                nextStart = restStart
                break
            }
            // 예산이 자른 청크의 마지막 줄은 덜 찬 줄일 수 있다 — 남은 줄이 그것뿐이면 커밋하지 않고
            // 다음 호출로 넘긴다 (첫 프레임의 `proposedKeepCount`는 확장 재프레이밍이 그 줄을 채운다).
            let restKeep = context.cutBeforeEnd ? rest.lines.count - 1 : rest.lines.count
            guard restKeep > 0 else {
                nextStart = restStart
                break
            }
            current = rest
            currentKeep = restKeep
            guard let next = firstLineEndOverflow(
                in: rest.lines, keepCount: currentKeep, context: context
            ) else {
                lines += rest.lines[0 ..< currentKeep]
                origins += rest.origins[0 ..< currentKeep]
                break
            }
            violation = next
        }
        let keep = min(lines.count, context.lineBudget)
        guard keep > 0 else { return nil }
        let last = CTLineGetStringRange(lines[keep - 1])
        return FrameChunk(
            lines: Array(lines[0 ..< keep]), origins: Array(origins[0 ..< keep]), keepCount: keep,
            nextStart: keep == lines.count ? nextStart ?? last.location + last.length
                : last.location + last.length
        )
    }

    /// 줄 끝 자간 재조판이 나르는 값.
    struct RefitContext {
        let typesetter: CTTypesetter
        let attributedString: NSAttributedString
        let lineWidth: CGFloat
        /// 이 청크가 덮는 문자열의 끝 (예산이 자른 청크면 문단 끝 전).
        let chunkEnd: Int
        let cutBeforeEnd: Bool
        let lineBudget: Int
    }

    /// 커밋할 줄(`0 ..< keepCount`) 중 마지막 글자의 음수 자간을 빼면 가용 폭을 넘고, 더 짧게
    /// 나눌 수 있는 첫 줄과 그 새 길이.
    private static func firstLineEndOverflow(
        in lines: [CTLine], keepCount: Int, context: RefitContext
    ) -> (index: Int, length: Int)? {
        for index in 0 ..< min(keepCount, lines.count) {
            let line = lines[index]
            let range = CTLineGetStringRange(line)
            let spacing = HwpLetterSpacing.lineEndSpacing(
                in: context.attributedString,
                range: NSRange(location: range.location, length: range.length)
            )
            guard spacing < 0 else { continue }
            let available = lineAvailableWidth(
                at: range.location, containerWidth: context.lineWidth, in: context.attributedString
            )
            guard contentWidth(of: line) - spacing > available + lineEndTolerance,
                  let length = lineEndSpacingBreak(
                      start: range.location, length: range.length, available: available,
                      spacing: spacing, typesetter: context.typesetter,
                      attributedString: context.attributedString
                  )
            else { continue }
            return (index, length)
        }
        return nil
    }

    /// 마지막 글자의 자간을 빼고 재도 가용 폭 안에 드는 줄 길이 — CoreText의 줄(`length`)보다
    /// 짧은 것만 준다. 마지막 글자가 바뀌면 그 자간도 바뀌므로 몇 번 다시 잰다.
    private static func lineEndSpacingBreak(
        start: Int, length: Int, available: CGFloat, spacing: CGFloat,
        typesetter: CTTypesetter, attributedString: NSAttributedString
    ) -> Int? {
        var lastSpacing = spacing
        var best: Int?
        for _ in 0 ..< 4 {
            let candidate = CTTypesetterSuggestLineBreak(
                typesetter, start, Double(available + lastSpacing)
            )
            guard candidate > 0, candidate < (best ?? length) else { break }
            best = candidate
            let range = CFRange(location: start, length: candidate)
            let line = CTTypesetterCreateLine(typesetter, range)
            lastSpacing = min(0, HwpLetterSpacing.lineEndSpacing(
                in: attributedString, range: NSRange(location: start, length: candidate)
            ))
            if contentWidth(of: line) - lastSpacing <= available + lineEndTolerance {
                break
            }
        }
        return best
    }

    /// 음수 자간의 오른쪽·가운데 정렬 줄 — 한글은 마지막 글자의 자간을 뺀 폭으로 정렬한다
    /// (실측: Menlo 20pt `abcd` 라틴 자간 −20% 오른쪽 정렬에서 `d`가 오른쪽 끝 − 12.00pt, 우리는
    /// − 9.63pt). CoreText는 그 자간을 넣은 폭으로 정렬하므로 origin을 자간만큼(가운데는 절반)
    /// 옮긴다. 가용 폭을 넘는 줄은 줄 시작에 두는 규칙(`overflowStartAligned`)이 이미 정했다.
    static func lineEndSpacingAligned(
        _ origins: [CGPoint],
        lines: [CTLine],
        in attributedString: NSAttributedString,
        containerWidth: CGFloat
    ) -> [CGPoint] {
        var adjusted = origins
        for index in origins.indices where index < lines.count {
            let range = CTLineGetStringRange(lines[index])
            let spacing = HwpLetterSpacing.lineEndSpacing(
                in: attributedString, range: NSRange(location: range.location, length: range.length)
            )
            guard spacing < 0,
                  let alignment = textAlignment(
                      of: paragraphStyle(in: attributedString, at: range.location)
                  ),
                  alignment == .center || alignment == .right
            else { continue }
            let available = lineAvailableWidth(
                at: range.location, containerWidth: containerWidth, in: attributedString
            )
            guard contentWidth(of: lines[index]) - spacing <= available + lineEndTolerance
            else { continue }
            adjusted[index].x += alignment == .right ? spacing : spacing / 2
        }
        return adjusted
    }

    /// 줄 끝 자간 비교의 여유 — CoreText 폭의 부동소수 잔차만 흡수한다.
    private static let lineEndTolerance: CGFloat = 0.001

    /// 줄의 내용 폭 — 줄 끝 공백(과 CoreText가 공백처럼 매다는 양수 자간 tracking)을 뺀 폭. CoreText의
    /// 줄 나눔·정렬이 재는 폭이라 한 줄 허용의 정렬(`HwpDrawnTextLayout.slightOverflowAlignmentOffset`)도
    /// 이 폭을 쓴다.
    static func contentWidth(of line: CTLine) -> CGFloat {
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        return CGFloat(width - CTLineGetTrailingWhitespaceWidth(line))
    }

    /// `location`에서 시작하는 줄의 가용 폭 — 문단 첫 줄이면 첫 줄 들여쓰기, 아니면 이어지는 줄
    /// 들여쓰기에서 오른쪽 여백(`availableLineWidth`)까지.
    private static func lineAvailableWidth(
        at location: Int, containerWidth: CGFloat, in attributedString: NSAttributedString
    ) -> CGFloat {
        let style = paragraphStyle(in: attributedString, at: location)
        let string = attributedString.string as NSString
        let startsParagraph = location == 0
            || (location <= string.length
                && HwpLineAdvance.isParagraphSeparator(string.character(at: location - 1)))
        let indent: CTParagraphStyleSpecifier = startsParagraph ? .firstLineHeadIndent : .headIndent
        let leading = paragraphCGFloat(indent, in: style)
        return availableLineWidth(
            containerWidth: containerWidth, lineOriginX: leading ?? 0, paragraphStyle: style
        )
    }

    /// CTParagraphStyle의 정렬. 없으면 nil.
    private static func textAlignment(of style: CTParagraphStyle?) -> CTTextAlignment? {
        guard let style else { return nil }
        var value = CTTextAlignment.natural
        guard CTParagraphStyleGetValueForSpecifier(
            style, .alignment, MemoryLayout<CTTextAlignment>.size, &value
        ) else { return nil }
        return value
    }

    /// startLocation의 CTParagraphStyle. 없으면 nil.
    static func paragraphStyle(
        in attributedString: NSAttributedString, at location: Int
    ) -> CTParagraphStyle? {
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
    static func paragraphCGFloat(
        _ spec: CTParagraphStyleSpecifier, in style: CTParagraphStyle?
    ) -> CGFloat? {
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
}
