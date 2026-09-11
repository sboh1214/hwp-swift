import CoreGraphics
import CoreHwp
import Foundation

/// 흐름 분할(`HwpPaginator.appendParagraphAcrossColumns`)이 조각을 자를 때 쓰는 줄별
/// 전진량과 조각 첫 줄의 ascent 초과분 — 순수 계산이라 paginator 본문에서 뺐다.
struct HwpFragmentLineAdvances {
    let lines: [HwpLineFrame]
    /// 문단 텍스트 몫 높이 (문단 위 간격 제외) — 마지막 줄이 잔여(간격 포함)를 흡수한다.
    let textHeight: CGFloat
    /// 줄 원점이 단조 증가하는지 — 아니면 (캐시 열화) 평균 전진량으로 폴백한다.
    let strictlyIncreasing: Bool
    /// 목적 단 폭으로 다시 잰 나머지(`HwpFragmentRemainder`)의 첫 줄 ascent 초과분을 낼
    /// 기준 ascent — 앞 조각의 마지막 줄과 나머지의 마지막 줄 가운데 **작은** 것이다. 조각
    /// 상자는 첫 줄 ascent를 빼고 마지막 줄 높이를 더한 것이라(`makeLineFrames`), 첫 줄이
    /// 마지막 줄보다 키 크면(다시 재며 개체 줄이 첫 줄로 올라온 경우) 그 차이만큼 짧다.
    /// 앞 조각의 마지막 줄만 기준으로 삼으면 그 줄도 개체 줄일 때 초과분이 0이 되어 상자가
    /// 첫 줄 개체를 못 담고, 나머지의 마지막 줄만 기준으로 삼으면 그 줄이 개체 줄일 때
    /// 같은 일이 난다 — 둘 가운데 작은 쪽을 기준으로 하면 어느 쪽 개체든 상자에 담긴다
    /// (PR 리뷰). 문단 머리면 nil.
    let precedingBaseline: CGFloat?

    init(lines: [HwpLineFrame], textHeight: CGFloat, precedingBaseline: CGFloat? = nil) {
        self.lines = lines
        self.textHeight = textHeight
        self.precedingBaseline = precedingBaseline
        strictlyIncreasing = zip(lines, lines.dropFirst())
            .allSatisfy { $0.origin.y < $1.origin.y }
    }

    /// 라인별 실제 전진량(origin.y 델타). 평균(textHeight/개수)은 문단 간격까지 라인에
    /// 배분해 혼합 높이/간격 문단을 잘못된 라인에서 절단한다 (#3). 마지막 라인이
    /// 잔여(간격 포함)를 흡수해 조각 높이 총합 = textHeight를 보존한다.
    func advance(_ index: Int) -> CGFloat {
        guard strictlyIncreasing else { return max(1, textHeight / CGFloat(lines.count)) }
        if index + 1 < lines.count {
            return max(1, lines[index + 1].origin.y - lines[index].origin.y)
        }
        return max(1, textHeight - lines[index].origin.y)
    }

    /// 조각 첫 줄의 ascent 초과분 (#164 리뷰): 전진량은 baseline 간격이라 줄 k의 ascent는
    /// 줄 k−1의 전진량에 실려 앞 조각이 가져가는데, 조각은 독립 프레임으로 그려져 첫 줄
    /// ascent를 자기 상단에서 내린다. 줄 안 개체(run delegate ascent = 개체 높이)로 첫
    /// 줄이 큰 조각은 그만큼 짧게 재어 뒤 문단이 그 위에 놓이므로, 그 몫을 앞 조각에서
    /// 빼고 이 조각에 더한다 — 조각 높이 합은 그대로다. 균등 줄은 0이라 불변.
    func ascentExcess(startingAt index: Int) -> CGFloat {
        guard strictlyIncreasing, index >= 0, index < lines.count else { return 0 }
        // 다시 잰 나머지의 첫 줄은 `precedingBaseline` 기준 — 문단 머리(nil)면 0이다.
        guard index > 0 else {
            guard let precedingBaseline else { return 0 }
            return max(0, lines[0].baseline - precedingBaseline)
        }
        return max(0, lines[index].baseline - lines[index - 1].baseline)
    }

    /// 줄 `boundary` 앞에서 끊긴 조각이 단에서 **실제로 차지하는** 높이 — 누적 전진량
    /// (조각 첫 줄 초과분 포함)에서 마지막 전진량에 실린 다음 조각 첫 줄의 몫을 뺀다.
    ///
    /// 적합 판정과 방출 높이가 반드시 이 한 식을 써야 한다 (PR 리뷰): 판정만 보정 없는
    /// 전진량으로 재면 키 큰 개체 줄 **앞**의 평범한 줄이 실제로는 들어가는데도 거절돼
    /// 단이 그 줄만큼 빈다 — 전진량은 baseline 간격이라 다음 줄의 ascent를 통째로
    /// 싣는데(100pt 표 줄이면 약 90pt), 그 몫은 경계에서 뒤 조각으로 넘어간다.
    func chargedHeight(_ takenHeight: CGFloat, endingBefore boundary: Int) -> CGFloat {
        takenHeight - ascentExcess(startingAt: boundary)
    }

    /// 줄 `boundary` 앞에서 끊긴 조각의 높이가 **측정 줄 전진량만으로** 났는지 (#166). 마지막
    /// 줄의 전진량은 `textHeight`의 잔여라 그 줄을 담은 조각은 `textHeight`가 측정값일 때만
    /// 그렇고, 원점이 비단조라 평균으로 폴백한 문단은 모든 조각이 `textHeight`의 몫이다.
    func heightIsMeasured(endingBefore boundary: Int, textHeightIsMeasured: Bool) -> Bool {
        guard strictlyIncreasing else { return textHeightIsMeasured }
        return boundary < lines.count || textHeightIsMeasured
    }
}

/// 흐름 분할이 조각마다 같은 값으로 쓰는 문단 단위 문맥 — 루프 밖에서 한 번 만든다.
struct HwpFragmentPlacement {
    let paraShape: CoreHwp.HwpParaShape
    /// 문단 조판 문자열의 개체 예약 폭이 묶인 단 폭 — 문단이 처음 놓인(진입 시 현재) 단이다.
    /// 조각이 놓이는 단이 이와 다르면 예약을 그 단으로 다시 푼다 (`placedFragment`).
    let reservedWidth: CGFloat
    /// 문단 높이가 측정값(`HwpParagraphFrame.totalHeight`)인지 — 아니면 저장본 줄 캐시
    /// (`HwpPaginator.height(for:fallback:)`)라 마지막 줄의 전진량이 그 잔여를 흡수한다 (#166).
    let heightIsMeasured: Bool
    let paragraphId: UInt32?
    /// 문단 전체 블록의 URL과 조각 블록의 URL (필드 스팬 문단은 조각에 전파하지 않는다).
    let hyperlinkURL: String?
    let fragmentURL: String?
}

/// 흐름 분할이 아직 놓지 않은 문단의 **나머지** — 줄·전진량과 그 줄을 잰 단 폭 (#166 PR 리뷰).
///
/// 줄은 문단이 처음 놓인 단의 폭으로 잰 것이라, 나머지가 폭이 다른 단(비등폭 단)으로 넘어가면
/// 렌더러의 줄바꿈이 달라진다 — 넓은 단에서는 줄이 합쳐져 잰 높이의 상자 아래가 비고, 좁은
/// 단에서는 줄이 늘어 상자를 넘친다. 측정 줄 조각 표식은 접힘만 막을 뿐 이 차이를 메우지
/// 못하므로, 높이가 측정값인 문단의 나머지는 `HwpPaginator.remeasureRemainderIfNeeded`가
/// 목적 단 폭으로 **다시 재어** 조각 높이와 줄 수를 그 줄바꿈으로 잡는다 (한글도 옮겨진 단
/// 폭으로 다시 줄바꿈한다). 다시 잰 줄의 문자열 범위는 문단 조판 문자열 기준으로 되돌려
/// (`start`만큼 밀어) 조각 자르기가 종전 산식을 그대로 쓴다. 저장본 줄 캐시 높이를 따르는
/// 문단은 다시 재지 않는다 — 그 높이는 한글의 것이라 우리가 다시 잰 값으로 바꾸지 않는다.
struct HwpFragmentRemainder {
    private(set) var lines: [HwpLineFrame]
    private(set) var advances: HwpFragmentLineAdvances
    /// `lines`를 잰 단 폭.
    private(set) var measuredWidth: CGFloat
    /// 나머지 높이(`advances.textHeight`)가 측정값인지 — 다시 재면 참이다.
    private(set) var heightIsMeasured: Bool
    /// 문단 조판 문자열에서 나머지가 시작하는 위치 — 0이면 문단 머리부터다.
    private(set) var start: Int
    /// `lines` 가운데 다음에 놓을 줄.
    private(set) var lineIndex = 0
    /// 이 문단에서 지금까지 놓은 줄 수 — 다시 재도 문단당 줄 상한
    /// (`HwpParagraphLayout.maximumLineFrames`)은 그대로다.
    private(set) var placedLineCount = 0
    /// 다시 잰 횟수 — `maximumRemeasures`에 닿으면 잰 폭의 줄로 둔다.
    private(set) var remeasureCount = 0

    /// 문단 하나가 다시 재는 횟수의 상한. 다시 재기는 나머지 전체를 복사·조판하므로
    /// (`continuationFragment`는 조각 길이 비례) 단이 바뀔 때마다 하면 비용이 (단 수 × 나머지
    /// 길이)로 이차다 — 비등폭 단이 번갈아 오는 병적 문서(1pt 폭 단 + 수백만 자 문단)에서
    /// 쪽 상한까지 매 단마다 재게 된다. 실물 문단이 걸치는 비등폭 단은 몇 개 안 되므로 64면
    /// 넉넉하고, 넘으면 잰 폭의 줄로 두어(표식 판정이 좁은 단을 실제 줄바꿈으로 가린다)
    /// 총비용을 선형으로 묶는다.
    static let maximumRemeasures = 64

    init(
        lines: [HwpLineFrame], textHeight: CGFloat, measuredWidth: CGFloat, heightIsMeasured: Bool
    ) {
        self.lines = lines
        advances = HwpFragmentLineAdvances(lines: lines, textHeight: textHeight)
        self.measuredWidth = measuredWidth
        self.heightIsMeasured = heightIsMeasured
        start = 0
    }

    var isExhausted: Bool {
        lineIndex >= lines.count
    }

    /// 다시 잴 수 있는지 — 횟수 상한과 줄 상한 안일 때.
    var canRemeasure: Bool {
        remeasureCount < Self.maximumRemeasures && lineBudget > 0
    }

    /// 다시 잴 때 만들 수 있는 줄 수 — 문단당 줄 상한에서 이미 놓은 줄을 뺀 것.
    var lineBudget: Int {
        HwpParagraphLayout.maximumLineFrames - placedLineCount
    }

    /// 줄 `count`개를 놓았다.
    mutating func place(_ count: Int) {
        lineIndex += count
        placedLineCount += count
    }

    /// 아직 아무 줄도 놓지 않았는지 — 문단 머리(`start == 0`)의 첫 줄이 다음 줄이다.
    var isAtParagraphStart: Bool {
        start == 0 && lineIndex == 0
    }

    /// 다음 줄부터 `available`에 들어가는 줄 수와 그 누적 전진량(조각 첫 줄 ascent 초과분
    /// 포함). 적합 판정은 방출 높이와 **같은 식**(`chargedHeight`)을 쓴다 — 보정 없는
    /// 전진량으로 재면 개체 줄 앞의 평범한 줄이 들어가는데도 거절된다 (PR 리뷰).
    func fit(in available: CGFloat) -> (count: Int, height: CGFloat) {
        var count = 0
        var height = advances.ascentExcess(startingAt: lineIndex)
        while lineIndex + count < lines.count,
              advances.chargedHeight(
                  height + advances.advance(lineIndex + count),
                  endingBefore: lineIndex + count + 1
              ) <= available
        {
            height += advances.advance(lineIndex + count)
            count += 1
        }
        return (count, height)
    }

    /// 다음 줄 하나만 놓을 때의 누적 전진량 — 빈 단에 안 들어가도 진행 보장으로 싣는 몫.
    var firstLineHeight: CGFloat {
        advances.ascentExcess(startingAt: lineIndex) + advances.advance(lineIndex)
    }

    /// 문단 첫 줄이 단에서 실제로 차지하는 높이 — 다음 줄로 넘어가는 ascent 초과분을 뺀
    /// `chargedHeight`. 문단 위 간격을 새 단에 다시 둘지 판정할 때 쓴다.
    var firstLineChargedHeight: CGFloat {
        advances.chargedHeight(advances.advance(0), endingBefore: 1)
    }

    /// 아직 놓지 않은 줄들의 문자열 범위 (문단 조판 문자열 기준).
    func remainingRange(in attributedString: NSAttributedString) -> NSRange? {
        guard lineIndex < lines.count else { return nil }
        let location = lines[lineIndex].attributedRange.location
        return NSRange(location: location, length: max(0, attributedString.length - location))
    }

    /// 다시 잰 줄로 나머지를 바꾼다. `frame`은 `remainingRange`의 조각을 `width` 폭으로 잰
    /// 것이고 `textHeight`는 그 텍스트 몫(문단 위 간격 제외)이다 — 첫 줄 ascent 초과분(#164)의
    /// 기준은 앞 조각의 마지막 줄과 다시 잰 마지막 줄 가운데 작은 ascent다
    /// (`HwpFragmentLineAdvances.precedingBaseline`).
    mutating func replace(
        with frame: HwpParagraphFrame, textHeight: CGFloat, width: CGFloat, range: NSRange
    ) {
        let precedingBaseline: CGFloat? = lineIndex > 0
            ? min(lines[lineIndex - 1].baseline, frame.lines.last?.baseline ?? .infinity)
            : nil
        lines = frame.lines.map { line in
            HwpLineFrame(
                origin: line.origin,
                width: line.width,
                baseline: line.baseline,
                attributedRange: NSRange(
                    location: line.attributedRange.location + range.location,
                    length: line.attributedRange.length
                ),
                inlineAnchors: line.inlineAnchors
            )
        }
        advances = HwpFragmentLineAdvances(
            lines: lines, textHeight: textHeight, precedingBaseline: precedingBaseline
        )
        measuredWidth = width
        heightIsMeasured = true
        start = range.location
        lineIndex = 0
        remeasureCount += 1
    }
}
