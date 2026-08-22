import CoreGraphics
import CoreText
import Foundation

/// 측정과 렌더가 **공유하는** 줄바꿈 코어.
///
/// `HwpParagraphLayout.layout`(측정)과 `HwpDrawnTextLayout.lines`(렌더)가 둘 다
/// `nextFrameChunk`를 불러 같은 `CTFramesetterSuggestFrameSizeWithConstraints`
/// 상자에서 같은 `CTLine` 경계를 얻는다 — 줄바꿈 사실(문자 분할·origin)이
/// 정의상 일치한다. 그 뒤의 높이 후처리는 목적이 달라 양쪽이 각자 유지한다:
/// 측정의 `trailingSpacing`·`clampedLineHeight`는 전진량·절단 모델이고, 렌더의
/// raw height는 잉크 모델이다.
///
/// 계약 네 가지는 `Sources/HwpKitCore/AGENTS.md`("측정·렌더 공유 줄바꿈 코어")가
/// 소유한다 — 줄 예산 절단, 미완 마지막 줄 이월, 한 시각 줄 재프레이밍,
/// `keepCount` 하드 상한.
///
/// **렌더 전용 헬퍼를 여기 넣지 말 것.** `HwpDrawnTextLayout.resumeBaseline`·
/// `fallbackLineAdvance`는 호출자가 `lines()`뿐이고 측정은 같은 일을
/// `HwpParagraphLayout.makeLineFrames`가 origin 델타로 자체 처리한다. 한쪽만
/// 쓰는 멤버가 들어오면 이 타입 이름이 다시 거짓말을 한다.
enum HwpLineBreaker {
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
