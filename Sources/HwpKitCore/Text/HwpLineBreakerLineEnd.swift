import CoreGraphics
import CoreText
import Foundation

// MARK: - 줄 끝 자간 (#260)

extension HwpLineBreaker {
    /// 음수 자간의 줄 끝 (#260) — 한글은 줄의 마지막 글자에 자간을 주지 않고 줄을 맞춘다
    /// (`HwpLetterSpacing.lineEndExcess`). CoreText는 양수 자간(tracking)은 줄 끝에서 빼고 재지만
    /// 음수 자간(kern·tracking)은 넣고 재므로, 음수 자간 줄은 마지막 글자의 자간만큼 **더 담긴다** (실측: Menlo
    /// 20pt 라틴 자간 −20% `aaaaa` × 8의 첫 줄이 한글은 줄 폭 388.0pt부터 7단어, 우리는 385.5pt부터).
    ///
    /// 커밋할 줄 중 마지막 글자의 자간을 빼고 재면 가용 폭을 넘는 줄을 그 자간을 뺀 폭으로 다시
    /// 나누고, 그 뒤는 새 프레임으로 다시 조판해 **한 청크로** 잇는다 — 청크를 쪼개면 정상 문단이
    /// 한 번의 호출로 덮인다는 전제(`HwpLayoutRenderParitySweepTests`의 3-way 대조, 측정·렌더 루프의
    /// "단일 청크" 주석)가 깨진다. 이어 붙인 줄의 origin은 각 프레임의 것이다 — 문단 중간에서
    /// 시작하는 프레임도 CoreText가 이어지는 줄 들여쓰기를 준다. 더 짧게 나눌 수 없는 줄(나눌 자리
    /// 없는 낱말)은 CoreText의 줄을 그대로 둔다.
    ///
    /// **뒤는 창(window) 단위로 다시 조판한다** (#260 리뷰). 다시 나눈 줄마다 문단의 나머지를 통째로
    /// 조판하면 고칠 줄 수 × 문단 길이라 이차다 (실측: 한글 음절 4만 자 −10% 문단 3.2초 대 0.38초 —
    /// 음수 자간이 클수록 고칠 줄이 많아 −50%면 거의 모든 줄). 다시 나눈 줄 뒤에서는 줄 몇 개 분량의
    /// 창만 조판해 마지막(창 끝에서 잘렸을 수 있는) 줄을 빼고 잇고, 그 뒤 다음 창으로 넘어간다 — CoreText의
    /// 줄 나눔은 줄 시작부터 탐욕적이라 창 안의 앞 줄들은 나머지 전체를 조판했을 때와 같다. 창은 고친
    /// 줄 길이의 8배(256…4,096자)이고 줄이 둘도 안 들어가면 넓힌다. 예산 절단·미완 줄 이월 계약은 청크
    /// 끝에 닿는 창에 같은 규칙으로 건다.
    static func lineEndSpacingRefit(
        chunk: (lines: [CTLine], origins: [CGPoint]),
        keepCount: Int,
        context: RefitContext,
        frame: (Int, Int) -> (lines: [CTLine], origins: [CGPoint])?
    ) -> FrameChunk? {
        guard let firstViolation = firstLineEndOverflow(
            in: chunk.lines, keepCount: keepCount, context: context
        ) else { return nil }
        var lines: [CTLine] = []
        var origins: [CGPoint] = []
        var current = chunk
        var currentKeep = keepCount
        var nextStart: Int?
        var window = 256
        var knownViolation: (index: Int, length: Int)? = firstViolation
        while lines.count < context.lineBudget {
            var cursor: Int
            let found = knownViolation
                ?? firstLineEndOverflow(in: current.lines, keepCount: currentKeep, context: context)
            knownViolation = nil
            if let violation = found {
                lines += current.lines[0 ..< violation.index]
                origins += current.origins[0 ..< violation.index]
                let violating = CTLineGetStringRange(current.lines[violation.index])
                guard lines.count < context.lineBudget else {
                    nextStart = violating.location
                    break
                }
                if let single = frame(violating.location, violation.length),
                   let line = single.lines.first
                {
                    lines.append(line)
                    origins.append(single.origins[0])
                    cursor = violating.location + CTLineGetStringRange(line).length
                } else {
                    lines.append(current.lines[violation.index])
                    origins.append(current.origins[violation.index])
                    cursor = violating.location + violating.length
                }
                window = min(max(violation.length * 8, 256), 4096)
            } else {
                lines += current.lines[0 ..< currentKeep]
                origins += current.origins[0 ..< currentKeep]
                let last = CTLineGetStringRange(current.lines[currentKeep - 1])
                cursor = last.location + last.length
            }
            guard cursor < context.chunkEnd, lines.count < context.lineBudget else {
                nextStart = cursor
                break
            }
            guard let next = nextWindow(
                from: cursor, window: &window, context: context, frame: frame
            ) else {
                // 예산이 자른 청크의 마지막 줄은 덜 찬 줄일 수 있다 — 남은 줄이 그것뿐이면 커밋하지 않고
                // 다음 호출로 넘긴다 (첫 프레임의 `proposedKeepCount`는 확장 재프레이밍이 그 줄을 채운다).
                nextStart = cursor
                break
            }
            current = (next.lines, next.origins)
            currentKeep = next.keepCount
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

    /// `cursor`에서 시작하는 다음 창의 조판과 커밋할 줄 수 — 청크 끝 전에 끝나는 창은 마지막 줄을
    /// 뺀다(창 끝에서 잘렸을 수 있다). 줄이 하나뿐이라 뺄 수 없으면 창을 넓혀 다시 잰다. 청크 끝에
    /// 닿는 창은 예산 절단 규칙(`cutBeforeEnd`)을 따르고, 커밋할 줄이 없으면 nil.
    private static func nextWindow(
        from cursor: Int, window: inout Int, context: RefitContext,
        frame: (Int, Int) -> (lines: [CTLine], origins: [CGPoint])?
    ) -> (lines: [CTLine], origins: [CGPoint], keepCount: Int)? {
        while true {
            let length = min(context.chunkEnd - cursor, window)
            let reachesEnd = cursor + length >= context.chunkEnd
            guard let framed = frame(cursor, length), !framed.lines.isEmpty else { return nil }
            let keep = reachesEnd && !context.cutBeforeEnd
                ? framed.lines.count : framed.lines.count - 1
            if keep > 0 {
                return (framed.lines, framed.origins, keep)
            }
            guard !reachesEnd else { return nil }
            window *= 2
        }
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
            let excess = HwpLetterSpacing.lineEndExcess(
                in: context.attributedString,
                range: NSRange(location: range.location, length: range.length)
            )
            guard excess < 0 else { continue }
            let head = lineHeadIndent(at: range.location, in: context.attributedString)
            let available = lineAvailableWidth(
                at: range.location, containerWidth: context.lineWidth, in: context.attributedString
            )
            guard contentWidth(of: line) - excess > available + lineEndTolerance,
                  let length = lineEndSpacingBreak(
                      start: range.location, length: range.length,
                      measure: LineMeasure(available: available, offset: head, excess: excess),
                      context: context
                  )
            else { continue }
            return (index, length)
        }
        return nil
    }

    /// 줄 하나를 다시 나눌 때의 잣대 — 가용 폭, 줄 머리 들여쓰기(탭 자리의 기준), 마지막 글자 자간.
    private struct LineMeasure {
        let available: CGFloat
        let offset: CGFloat
        let excess: CGFloat
    }

    /// 마지막 글자의 자간을 빼고 재도 가용 폭 안에 드는 줄 길이 — CoreText의 줄(`length`)보다
    /// 짧은 것만 준다. 마지막 글자가 바뀌면 그 자간도 바뀌므로 몇 번 다시 잰다. 그래도 넘치면 줄 나눔
    /// 자리를 하나씩 앞으로 옮겨 들어가는 줄을 찾고, 어느 자리도 들지 않으면 첫 묶음만 둔다(`fittingBreak`) —
    /// 들어가는 자리가 있는데 넘치는 줄을 확정하지 않고, 결과가 반복 상한에 좌우되지 않는다.
    ///
    /// 줄은 **실제 줄 머리 자리**(`measure.offset` — 첫 줄·이어지는 줄 들여쓰기)에서 잰다 (#260 리뷰).
    /// CoreText는 탭 자리를 프레임 왼쪽 끝 기준으로 잡으므로, 들여쓴 문단의 탭 있는 줄을 0에서 재면
    /// 프레임이 커밋하는 줄과 폭이 탭 간격만큼 갈려 한 낱말 일찍 나누거나 다시 나누지 못한다 (실측:
    /// 왼쪽 여백 20pt 문단의 `description sentence\tend value `가 0에서 191.04pt, 20에서 171.04pt).
    private static func lineEndSpacingBreak(
        start: Int, length: Int, measure: LineMeasure, context: RefitContext
    ) -> Int? {
        var lastExcess = measure.excess
        var best: Int?
        for _ in 0 ..< 4 {
            let candidate = CTTypesetterSuggestLineBreakWithOffset(
                context.typesetter, start, Double(measure.available + lastExcess),
                Double(measure.offset)
            )
            guard candidate > 0, candidate < (best ?? length) else { break }
            best = candidate
            let fit = lineEndFit(
                start: start, length: candidate, measure: measure, context: context
            )
            if fit.fits {
                return candidate
            }
            lastExcess = fit.excess
        }
        // 고정점 반복은 줄 나눔 자리를 한 번에 하나씩 당기는데, 크기가 급격히 줄어드는 글자열은 작은 끝 글자를
        // 떼면 그 앞 큰 글자의 음수 자간이 되살아나 마지막 글자 자간을 뺀 폭이 오히려 늘어서 들어가는 자리가 네
        // 자리보다 멀리 있다 — 상한(4번) 안에 닿지 못한다 (#260 PR 리뷰 실측: Apple SD 산돌고딕 Neo
        // `가나다라마바` 80·40.5·20.5·10.5·5.5·3pt 자간 −50%, 줄 폭 69.21pt에서 두 글자 줄 69.6325pt가 확정됐다 —
        // 한 글자는 69.2pt로 들어간다. 한글 12.30도 69.42pt에서 `가` 한 글자다). 반복이 끝나도 넘치면 줄 나눔
        // 자리를 하나씩 앞으로 옮겨 들어가는 가장 가까운 자리를, 없으면 첫 묶음을 고른다. CoreText 줄 그대로
        // 들어가면(`best == nil`) 다시 잴 것이 없다 — 이 검사가 그 줄을 걸러야 한다(프레임 줄이 typesetter 줄보다
        // 넓게 재지는 실문서 줄이 대부분 이 갈래다).
        let reached = best ?? length
        if lineEndFit(start: start, length: reached, measure: measure, context: context).fits {
            return best
        }
        return fittingBreak(
            below: reached, start: start, measure: measure, context: context
        ) ?? best
    }

    /// `[start, start + length)` 줄이 마지막 글자의 음수 자간을 빼고 재도 가용 폭 안에 드는지와 그 자간.
    private static func lineEndFit(
        start: Int, length: Int, measure: LineMeasure, context: RefitContext
    ) -> (fits: Bool, excess: CGFloat) {
        let line = CTTypesetterCreateLineWithOffset(
            context.typesetter, CFRange(location: start, length: length), Double(measure.offset)
        )
        let excess = min(0, HwpLetterSpacing.lineEndExcess(
            in: context.attributedString, range: NSRange(location: start, length: length)
        ))
        return (contentWidth(of: line) - excess <= measure.available + lineEndTolerance, excess)
    }

    /// `length`보다 앞의 줄 나눔 자리를 가까운 것부터 하나씩 짚어, 마지막 글자 자간을 빼고 재도 가용 폭에
    /// 드는 첫 자리. 어느 자리도 들지 않으면 짚은 가장 짧은 자리(첫 묶음)다 — 한글은 줄을 앞에서부터 채워
    /// 둘째 글자가 들지 않으면 첫 글자만 둔다 (한글 12.30 실측, 2026-10-09: Apple SD 산돌고딕 Neo `가…차`
    /// 96·45·21·10·4.7·2.2·1·1·1·1pt 자간 −50% 뒤 20pt `하`를 이은 문단 — 첫 글자만으로도 넘치는 76.5–78.0pt에서
    /// 첫 줄이 `가`). 앞으로 옮길 자리가 없으면 nil. 다음 자리는 지금 줄의 CoreText 폭보다 조금 좁은 폭으로
    /// CoreText에 묻는다(그 폭에 드는 가장 긴 줄 나눔이 바로 앞 자리다 — 첫 묶음보다 좁으면 첫 묶음을 준다).
    /// 자리가 매번 앞으로만 가므로 끝난다.
    private static func fittingBreak(
        below length: Int, start: Int, measure: LineMeasure, context: RefitContext
    ) -> Int? {
        var current = length
        while current > 1 {
            let line = CTTypesetterCreateLineWithOffset(
                context.typesetter, CFRange(location: start, length: current),
                Double(measure.offset)
            )
            let previous = CTTypesetterSuggestLineBreakWithOffset(
                context.typesetter, start, Double(contentWidth(of: line) - lineEndTolerance),
                Double(measure.offset)
            )
            guard previous > 0, previous < current else { break }
            current = previous
            if lineEndFit(start: start, length: current, measure: measure, context: context).fits {
                return current
            }
        }
        return current < length ? current : nil
    }

    /// 줄 끝 자간의 오른쪽·가운데 정렬 줄 — 한글은 마지막 글자의 자간을 뺀 폭으로 정렬한다
    /// (실측: Menlo 20pt `abcd` 라틴 자간 −20% 오른쪽 정렬에서 `d`가 오른쪽 끝 − 12.00pt, 우리는
    /// − 9.63pt). CoreText는 줄 폭에 넣고 잰 그 자간(`HwpLetterSpacing.lineEndExcess` — 음수, 그리고
    /// 뒤에 폭 0 컨트롤 표식이 있어 매달지 못한 양수)으로 정렬하므로 origin을 그만큼(가운데는 절반)
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
            let excess = HwpLetterSpacing.lineEndExcess(
                in: attributedString, range: NSRange(location: range.location, length: range.length)
            )
            guard excess != 0,
                  let alignment = textAlignment(
                      of: paragraphStyle(in: attributedString, at: range.location)
                  ),
                  alignment == .center || alignment == .right
            else { continue }
            let available = lineAvailableWidth(
                at: range.location, containerWidth: containerWidth, in: attributedString
            )
            guard contentWidth(of: lines[index]) - excess <= available + lineEndTolerance
            else { continue }
            adjusted[index].x += alignment == .right ? excess : excess / 2
        }
        return adjusted
    }

    /// 줄 끝 자간 비교의 여유 — CoreText 폭의 부동소수 잔차만 흡수한다.
    static let lineEndTolerance: CGFloat = 0.001

    /// 줄의 내용 폭 — 줄 끝 공백(과 CoreText가 공백처럼 매다는 양수 자간 tracking)을 뺀 폭. CoreText의
    /// 줄 나눔·정렬이 재는 폭이라 한 줄 허용의 정렬(`HwpDrawnTextLayout.slightOverflowAlignmentOffset`)도
    /// 이 폭을 쓴다.
    static func contentWidth(of line: CTLine) -> CGFloat {
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        return CGFloat(width - CTLineGetTrailingWhitespaceWidth(line))
    }

    /// `location`에서 시작하는 줄의 머리 들여쓰기 — 문단 첫 줄이면 첫 줄 들여쓰기, 아니면 이어지는 줄
    /// 들여쓰기 (없으면 0).
    static func lineHeadIndent(
        at location: Int, in attributedString: NSAttributedString
    ) -> CGFloat {
        let style = paragraphStyle(in: attributedString, at: location)
        let string = attributedString.string as NSString
        let startsParagraph = location == 0
            || (location <= string.length
                && HwpLineAdvance.isParagraphSeparator(string.character(at: location - 1)))
        let indent: CTParagraphStyleSpecifier = startsParagraph ? .firstLineHeadIndent : .headIndent
        return paragraphCGFloat(indent, in: style) ?? 0
    }

    /// `location`에서 시작하는 줄의 가용 폭 — 줄 머리 들여쓰기(`lineHeadIndent`)에서 오른쪽
    /// 여백(`availableLineWidth`)까지.
    private static func lineAvailableWidth(
        at location: Int, containerWidth: CGFloat, in attributedString: NSAttributedString
    ) -> CGFloat {
        availableLineWidth(
            containerWidth: containerWidth,
            lineOriginX: lineHeadIndent(at: location, in: attributedString),
            paragraphStyle: paragraphStyle(in: attributedString, at: location)
        )
    }
}
