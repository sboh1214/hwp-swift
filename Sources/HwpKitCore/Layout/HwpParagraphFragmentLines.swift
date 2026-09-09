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
    /// 첫 줄의 `baseline`(그 줄 ascent)은 그대로다 — 조각의 첫 줄이 되므로 렌더
    /// (`HwpDrawnTextLayout`)가 조각 블록 상단에서 그 ascent만큼 내려 첫 baseline을
    /// 놓는 것과 같다.
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
