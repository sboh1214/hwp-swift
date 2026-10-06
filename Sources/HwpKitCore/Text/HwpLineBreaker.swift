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

        func frame(length: Int) -> (lines: [CTLine], origins: [CGPoint])? {
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
            return (lines, overflowStartAligned(origins, lines: lines, in: attributedString))
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
