import CoreGraphics
import CoreText
import Foundation

// 쪽·단 경계로 나뉜 문단 조각의 줄 프레임 (#164)

extension HwpParagraphLayout {
    /// 문단 줄 프레임 가운데 `lines`만 담은 조각의 줄 프레임 — 문자열 범위는 조각 문자열
    /// (`range`가 0) 기준으로, 원점 y는 조각 **첫 줄** 기준 델타로 되돌린다.
    ///
    /// 조각 블록은 독립 프레임으로 다시 그려지므로 줄 앵커 좌표
    /// (`HwpObjectAnchorGeometry.inlineAnchorOrigin`: 블록 상단 + 첫 줄 baseline + 줄
    /// 델타 − ascent)가 조각 블록을 기준으로 성립하려면 조각 첫 줄의 델타가 0이어야
    /// 한다. 문단 전체 기준 델타를 그대로 두면 뒤 조각의 앵커가 앞 조각 높이만큼
    /// 아래로 밀린다. 문자열 범위도 같은 이유로 조각 기준이어야 한다 — 조각 문자열의
    /// `controlIndex` 마커와 줄의 대응이 그 범위로 이어진다.
    ///
    /// `HwpTableSplitter.paragraphFragment`는 범위만 되돌리고 원점은 두는데, 그쪽 소비자
    /// (`lineAdvances`)는 델타 차이만 읽어 원점이 어디서 시작하든 같다. 여기 소비자는
    /// 절댓값을 쓰는 앵커 산식이라 되돌려야 한다.
    ///
    /// 첫 줄의 `baseline`(그 줄 ascent)은 그대로다 — 조각의 첫 줄이 되므로 개체 앵커의
    /// 기준점이 조각 블록 상단에서 그 ascent만큼 내려간 자리가 된다. **렌더의 글자
    /// baseline과 같은 값이 아니다** (#178: 렌더는 블록 상단에서 줄 상자 앵커만큼
    /// 내려간다) — 개체 앵커 축이 그 모델로 따라오지 못한 격차는 #195다.
    static func fragmentLineFrames(
        _ lines: ArraySlice<HwpLineFrame>,
        range: NSRange
    ) -> [HwpLineFrame] {
        guard let first = lines.first else { return [] }
        return lines.map { line in
            HwpLineFrame(
                origin: CGPoint(x: line.origin.x, y: line.origin.y - first.origin.y),
                width: line.width,
                baseline: line.baseline,
                attributedRange: NSRange(
                    location: max(0, line.attributedRange.location - range.location),
                    length: line.attributedRange.length
                ),
                inlineAnchors: line.inlineAnchors
            )
        }
    }

    /// 조각의 앵커 줄을 **렌더러가 그리는 대로** 맞춘다 (#164 리뷰). 조각 줄은 문단 전체
    /// 측정에서 왔는데, 렌더러(`HwpDrawnTextLayout.lines`)는 조각 문자열에 slight-overflow
    /// 한 줄 술어를 따로 적용하므로 — 문단에서는 다음 줄로 넘어간 좁은 개체 마커가 조각
    /// 혼자서는 한 줄에 들어갈 수 있다 — 둘이 갈리면 개체가 그려지지 않는 둘째 줄 자리에
    /// 놓인다. 접히면 측정의 한 줄 분기(`layout`)와 같은 줄 프레임 하나를 만든다.
    ///
    /// 접힘은 이제 **한글이 저장한 높이로 놓인 조각**(절대 캐시 run·다단 캐시 run)에만
    /// 남는다 — 측정한 줄 높이로 놓인 조각은 `measuredLineFragment` 표식으로 렌더러가
    /// 접지 않으므로(#166) 이 술어가 nil이라 원본 줄을 그대로 돌려준다.
    ///
    /// 줄이 **이미 하나**여도 지나쳐선 안 된다 (PR 리뷰): 목적 단 폭으로 다시 조판한 조각
    /// (`HwpPaginator.fragmentAnchorLines`)이 한 줄이면 그 줄은 측정의 한 줄 분기가 낸
    /// 것이라 원점 x가 0인데, 렌더러는 같은 줄에 정렬 오프셋을 준다 — 오른쪽 정렬 조각의
    /// 앵커가 초과분만큼 오른쪽으로 밀려 표가 단 경계를 넘었다. 접기 술어가 nil이면
    /// (넉넉한 줄) 어차피 원본을 돌려주므로, 한 줄 조각도 같은 술어에 태우면 된다.
    static func fragmentLineFramesAsDrawn(
        _ frames: [HwpLineFrame],
        fragment: NSAttributedString,
        columnWidth: CGFloat
    ) -> [HwpLineFrame] {
        guard !frames.isEmpty,
              let overflow = HwpDrawnTextLayout.slightOverflowLineMetrics(
                  attributedString: fragment, lineWidth: max(1, columnWidth)
              )
        else { return frames }
        return [slightOverflowLineFrame(
            overflow, attributedString: fragment, columnWidth: max(1, columnWidth)
        )]
    }

    /// 접힌 조각의 slight-overflow 한 줄 프레임. 원점 x는 렌더러
    /// (`HwpDrawnTextLayout.slightOverflowSingleLine`)가 가운데·오른쪽 정렬에 주는 가로
    /// 오프셋이다 — 0으로 두면 오른쪽 정렬 조각의 개체 앵커가 그려진 글자보다 초과분만큼
    /// 오른쪽에 놓여 단 경계를 넘는다 (PR 리뷰). 측정의 한 줄 분기(`layout`)는 원점 0을
    /// 유지한다 — 단 폭과 같은 글자처럼 취급 표의 마커가 단 폭을 살짝 넘어 가운데
    /// 정렬 오프셋으로 단 밖에 밀리는 실물(noori 1쪽)이 있어서다.
    static func slightOverflowLineFrame(
        _ overflow: HwpDrawnTextLayout.SlightOverflowLine,
        attributedString: NSAttributedString,
        columnWidth: CGFloat
    ) -> HwpLineFrame {
        HwpLineFrame(
            origin: CGPoint(
                x: HwpDrawnTextLayout.slightOverflowAlignmentOffset(
                    attributedString: attributedString, lineWidth: columnWidth, line: overflow.line
                ),
                y: 0
            ),
            width: CGFloat(CTLineGetTypographicBounds(overflow.line, nil, nil, nil)),
            baseline: overflow.ascent,
            attributedRange: NSRange(location: 0, length: attributedString.length),
            inlineAnchors: HwpParagraphLayout().inlineAnchors(in: overflow.line)
        )
    }
}

// MARK: - 측정한 줄로 놓이는 조각 문자열 (#166)

extension HwpParagraphLayout {
    /// 조각 문자열(`continuationFragment`와 개체 예약 재해석까지 마친 것)에 **측정 줄 조각 표식**
    /// (`HwpAttributedStringKey.measuredLineFragment`)을 달지 판정해 조각 전체에 단다. 표식이
    /// 이미 있던 문자열은 먼저 벗긴다 — 표식을 단 블록을 다시 나누는 경로(다단 균형 재배치·
    /// 표의 다중 쪽 분할)가 있어 조각마다 새로 판정해야 한다.
    ///
    /// 이 조각을 놓는 블록의 높이가 `measuredWidth` 폭에서 잰 줄 `measuredLineCount`개의
    /// 전진량 합(쪽·단 경계 흐름 분할 `HwpPaginator.appendLineSliceBlock`·표 행 분할
    /// `HwpTableSplitter.paragraphFragment`·다단 균형 재배치
    /// `HwpColumnBandController.balancedBlocks`)일 때만(`heightIsMeasured`) 표식이 뜻을 갖는다 —
    /// 렌더러가 조각 혼자 한 줄 넘침 허용 배율 안에 든다고 한 줄로 접으면 측정 줄 수와 갈려
    /// 블록 아래가 빈다. 표식을 단 조각은 렌더러(`HwpDrawnTextLayout.lines`)와 조각 재측정
    /// (`layout`)이 모두 문단 단위 한 줄 규칙을 건너뛴다. 저장본 줄 캐시 높이의 잔여를 담은
    /// 조각은 캐시 줄 수가 오라클이라 달지 않는다(호출부가 `heightIsMeasured`로 가른다).
    ///
    /// **한 줄 조각(`measuredLineCount ≤ 1`)에는 달지 않는다.** 문단 전체 블록의 한 줄은 그
    /// 규칙으로 접혀 잰 것일 수 있어 표식이 두 줄로 되돌리고, 문단에서 잘라낸 한 줄은 잰 폭에
    /// 들어가므로 좁지 않은 단에서는 표식이 렌더를 바꾸지 못한다.
    ///
    /// 측정 높이 조각은 폭이 다른 단으로 옮겨지면 호출부(흐름 분할 `HwpFragmentRemainder`·
    /// 균형 재배치 `rebalancedFragment`)가 그 단 폭으로 다시 재어 오므로 `columnWidth`가 잰
    /// 폭과 같다 — 표식은 접힘만 막을 뿐 CT가 넓은 폭에서 줄을 합치는 것은 막지 못해, 다시
    /// 재지 않으면 잰 높이의 상자 아래가 빈다 (PR 리뷰). 잰 폭과 다른 단에 오는 것은 캐시
    /// 높이 문단의 조각뿐이다: **놓이는 단 폭이 잰 폭보다 좁지 않으면 그대로 단다** — CT
    /// 줄바꿈은 폭이 넓어져도 줄이 늘지 않아 그려지는 줄 수가 측정 줄 수를 넘지 않는다(합쳐져
    /// 아래가 빌 수는 있다 — 한글이 잰 높이를 따르는 축). **좁아진 단이면 폭 비교에 허용
    /// 오차를 두지 않고 실제로 줄바꿈해 본다** (PR 리뷰): 단 폭은 HWPUNIT 단위로 저작돼 0.5pt
    /// 안에서도 잰 폭에 꼭 맞던 줄이 다시 나뉜다. 렌더러가 이 폭에서 조각을 한 줄로 접을 때만
    /// 표식이 뜻이 있고, 표식을 단 조각이 접지 않고 그려지는 줄 수가 측정 줄 수를 넘지 않을
    /// 때만 단다 — 넘으면 종전 접힘(가로 6% 이내 넘침)이 상자를 세로로 넘치는 것보다 낫다.
    /// 이 확인은 좁아진 단의 접힘 대상 조각(자연 폭이 그 폭의 1.06배 안)에서만 조판 한 번이다.
    static func measuredLineFragment(
        _ fragment: NSAttributedString,
        heightIsMeasured: Bool,
        measuredLineCount: Int,
        measuredWidth: CGFloat,
        columnWidth: CGFloat
    ) -> NSAttributedString {
        let base = strippingMeasuredLineMarker(fragment)
        guard heightIsMeasured, measuredLineCount > 1, base.length > 0 else { return base }
        let marked = markedAsMeasuredLineFragment(base)
        guard columnWidth < measuredWidth else { return marked }
        let width = max(1, columnWidth)
        guard HwpDrawnTextLayout.slightOverflowLineMetrics(
            attributedString: base, lineWidth: width
        ) != nil else { return base }
        let drawnLineCount = HwpDrawnTextLayout.lines(
            attributedString: marked, origin: .zero, lineWidth: width
        ).count
        return drawnLineCount <= measuredLineCount ? marked : base
    }

    /// 표식을 **무조건** 단 사본 — 판정 없이 문단 단위 한 줄 규칙만 끈다. 문단 머리가 아닌
    /// 조각을 목적 단 폭으로 다시 잴 때(`HwpPaginator.remeasureRemainderIfNeeded`·
    /// `HwpColumnBandController.rebalancedFragment`) 쓴다 — 조각을 문단처럼 재면 한 줄 넘침
    /// 규칙이 조각을 접어 한글의 줄바꿈(그 폭에서 두 줄)과 갈린다. 문단 머리부터 통째로 옮긴
    /// 나머지는 문단이므로 표식 없이 재어 그 규칙을 따른다.
    static func markedAsMeasuredLineFragment(_ fragment: NSAttributedString) -> NSAttributedString {
        guard fragment.length > 0 else { return fragment }
        let marked = NSMutableAttributedString(attributedString: fragment)
        marked.addAttribute(
            HwpAttributedStringKey.measuredLineFragment,
            value: NSNumber(value: true),
            range: NSRange(location: 0, length: marked.length)
        )
        return marked
    }

    /// 측정 줄 조각 표식을 벗긴 문자열 — 표식은 조각 전체에 붙으므로 첫 글자로 판정한다.
    static func strippingMeasuredLineMarker(
        _ attributedString: NSAttributedString
    ) -> NSAttributedString {
        guard HwpDrawnTextLayout.isMeasuredLineFragment(attributedString) else {
            return attributedString
        }
        let stripped = NSMutableAttributedString(attributedString: attributedString)
        stripped.removeAttribute(
            HwpAttributedStringKey.measuredLineFragment,
            range: NSRange(location: 0, length: stripped.length)
        )
        return stripped
    }
}

// MARK: - 줄 앵커 추출 (측정과 조각 접기가 공유)

extension HwpParagraphLayout {
    /// 라인의 run에서 컨트롤 마커 (hwp.controlIndex attribute) 위치를 추출한다.
    /// 조각의 slight-overflow 한 줄 앵커(`fragmentLineFramesAsDrawn`)도 같은 추출을 쓴다.
    func inlineAnchors(in line: CTLine) -> [HwpInlineAnchor] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var anchors: [HwpInlineAnchor] = []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let number = attributes[HwpAttributedStringKey.controlIndex] as? NSNumber
            else { continue }
            let range = CTRunGetStringRange(run)
            let xOffset = CTLineGetOffsetForStringIndex(line, range.location, nil)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(
                run,
                CFRange(location: 0, length: 0),
                &ascent,
                &descent,
                nil
            ))
            anchors.append(HwpInlineAnchor(
                controlIndex: number.intValue,
                xOffset: xOffset,
                ascent: ascent,
                width: width
            ))
        }
        return anchors
    }
}
