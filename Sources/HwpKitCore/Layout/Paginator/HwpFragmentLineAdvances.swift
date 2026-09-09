import CoreGraphics
import Foundation

/// 흐름 분할(`HwpPaginator.appendParagraphAcrossColumns`)이 조각을 자를 때 쓰는 줄별
/// 전진량과 조각 첫 줄의 ascent 초과분 — 순수 계산이라 paginator 본문에서 뺐다.
struct HwpFragmentLineAdvances {
    let lines: [HwpLineFrame]
    /// 문단 텍스트 몫 높이 (문단 위 간격 제외) — 마지막 줄이 잔여(간격 포함)를 흡수한다.
    let textHeight: CGFloat
    /// 줄 원점이 단조 증가하는지 — 아니면 (캐시 열화) 평균 전진량으로 폴백한다.
    let strictlyIncreasing: Bool

    init(lines: [HwpLineFrame], textHeight: CGFloat) {
        self.lines = lines
        self.textHeight = textHeight
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
        guard strictlyIncreasing, index > 0, index < lines.count else { return 0 }
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
}
