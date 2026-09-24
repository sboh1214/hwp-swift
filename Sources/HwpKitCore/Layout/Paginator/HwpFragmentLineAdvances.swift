import CoreGraphics
import CoreHwp
import Foundation

/// 흐름 분할(`HwpPaginator.appendParagraphAcrossColumns`)이 조각을 자를 때 쓰는 줄별
/// 전진량 — 순수 계산이라 paginator 본문에서 뺐다.
///
/// 줄 프레임의 `origin.y`는 **줄 상자 상단**(문단 첫 줄 상자 상단 기준)이고 전진량은 그
/// 델타다 (#180 — 종전에는 CT baseline 델타라 조각 첫 줄의 ascent 초과분을 앞 조각에서
/// 빼고 뒤 조각에 더하는 보정(#164)이 필요했다. 상자 상단 기준에서는 조각 상단이 곧 첫 줄
/// 상자 상단이라 그 보정이 없다).
struct HwpFragmentLineAdvances {
    let lines: [HwpLineFrame]
    /// 문단 텍스트 몫 높이 (문단 위 간격 제외) — 마지막 줄이 잔여(간격 포함)를 흡수한다.
    let textHeight: CGFloat
    /// 줄 원점이 단조 증가하는지 — 아니면 (캐시 열화) 평균 전진량으로 폴백한다.
    let strictlyIncreasing: Bool
    /// 텍스트 몫이 저장본 줄 캐시 높이일 때 그 캐시의 줄 상자 바닥 (첫 줄 상자 상단 기준, pt,
    /// `HwpPaginator.cachedLineBoxExtent`) — 마지막 줄의 적합 높이를 이것으로 잰다 (#222). 캐시
    /// 높이 문단의 마지막 줄 전진량은 캐시 잔여(`advance`)라 CT 상자와 출처가 갈리므로, 판정도
    /// 높이와 **같은 출처**여야 한다 (#166의 높이 출처 원칙). CT 측정 높이면 nil.
    let cachedLastLineBoxBottom: CGFloat?

    init(lines: [HwpLineFrame], textHeight: CGFloat, cachedLastLineBoxBottom: CGFloat? = nil) {
        self.lines = lines
        self.textHeight = textHeight
        self.cachedLastLineBoxBottom = cachedLastLineBoxBottom
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

    /// 줄 `index`를 쪽·단 끝에 남길지 판정할 때 그 줄이 줄 상자 상단부터 차지하는 높이 — **줄
    /// 상자** 높이다 (#222). 한글 12.30 실측: 줄 상자 하단이 본문 하단보다 위면 그 줄을 남기고,
    /// 줄 간격 여분(비율 여분·여백만 간격)과 문단 아래 간격은 쪽·단 아래로 넘쳐도 된다 — 남은
    /// 17.62pt에 16pt·160% 줄(상자 16, 전진량 25.6)을 남기고, 고정 줄 간격이 상자보다 작은 줄
    /// (상자 10, 전진량 8)은 남은 9pt에서 넘긴다. 전진량(`advance`)과 갈리는 것은 이 판정뿐이고
    /// 조각 높이·커서 전진은 그대로 전진량 합이다.
    ///
    /// 원점이 비단조라 평균 전진량으로 폴백한 문단(캐시 열화)은 줄 상단을 알 수 없으므로 전진량
    /// 그대로 잰다. 상자 높이가 0인 줄(합성 줄 프레임)도 전진량이다. 텍스트 몫이 줄 캐시 높이인
    /// 문단의 마지막 줄은 캐시의 줄 상자 바닥까지다 (`cachedLastLineBoxBottom`) — CT 줄이 캐시보다
    /// 많으면 그 줄 상단이 이미 캐시 상자 바닥 아래라 음수일 수 있고, 조각 판정은 앞 줄들의 상자가
    /// 정한다.
    func fitHeight(_ index: Int) -> CGFloat {
        guard strictlyIncreasing else { return advance(index) }
        if index == lines.count - 1, let cachedLastLineBoxBottom {
            return cachedLastLineBoxBottom - lines[index].origin.y
        }
        guard lines[index].boxHeight > 0 else { return advance(index) }
        return lines[index].boxHeight
    }

    /// 줄 `start`부터 `end`까지를 한 조각으로 남길 때 조각 상단(줄 `start`의 상자 상단)에서 잰
    /// 적합 높이 — 줄마다 (그 줄 상자 상단 + `fitHeight`)의 최댓값이다. 고정 줄 간격이 상자보다
    /// 작으면 앞 줄 상자가 뒤 줄 상자보다 아래로 내려갈 수 있어 마지막 줄만 보면 안 된다.
    func fitHeight(from start: Int, through end: Int) -> CGFloat {
        var top: CGFloat = 0
        var required: CGFloat = 0
        for index in start ... end {
            required = max(required, top + fitHeight(index))
            top += advance(index)
        }
        return required
    }

    /// 줄 `boundary` 앞에서 끊긴 조각의 높이가 **측정 줄 전진량만으로** 났는지 (#166). 마지막
    /// 줄의 전진량은 `textHeight`의 잔여라 그 줄을 담은 조각은 `textHeight`가 측정값일 때만
    /// 그렇고, 원점이 비단조라 평균으로 폴백한 문단은 모든 조각이 `textHeight`의 몫이다.
    func heightIsMeasured(endingBefore boundary: Int, textHeightIsMeasured: Bool) -> Bool {
        guard strictlyIncreasing else { return textHeightIsMeasured }
        return boundary < lines.count || textHeightIsMeasured
    }
}

/// 쪽·단 끝 적합 판정 (#222) — 줄(또는 문단)이 요구하는 높이가 남은 높이에 들어가는가.
///
/// 한글 12.30 실측(2026-09-24, `probes/222`): 줄 상자 하단이 본문 하단과 **같으면 넘긴다** —
/// 17.62pt 줄을 남은 17.62pt에 두지 않고(줄 간격 100%로 전진량까지 같아도) 17.61pt 줄은
/// 남긴다. 고정 줄 간격 줄·세 줄 문단의 마지막 줄도 같다. 그래서 판정은 엄격 부등호이고,
/// 부동소수 누적 오차는 HWPUNIT(0.01pt)의 절반으로 흡수해 한 HWPUNIT 차이는 그대로 가른다.
enum HwpPageEndFit {
    /// HWPUNIT(0.01pt)의 절반.
    static let tolerance: CGFloat = 0.005

    /// `required`가 `available` 안에 들어가는가 — 하단이 경계에 닿으면 안 들어간다.
    static func fits(_ required: CGFloat, in available: CGFloat) -> Bool {
        required < available - tolerance
    }
}

/// 쪽·단 경계에서 문단의 줄을 어디까지 남길 수 있는지의 규칙 (#207) — 문단 모양 표 44의
/// 쪽 나눔 보호 비트에서 온다. 한글 12.30 실측(2026-09-21, `probes/207`, 전부 1단 **쪽**
/// 경계 — 다단의 단 경계는 미실측이고 같은 규칙을 적용한다):
///
/// - **외톨이줄 보호**(bit 16): 경계 **양쪽**에 줄이 최소 두 줄씩 남아야 나뉜다 — 들어가는
///   줄 k, 남은 줄 n이면 남기는 줄은 min(k, n − 2)이고 그 값이 2 미만이면 하나도 남기지
///   않는다 (5줄 문단 k=2 → 2+3, k=3 → 3+2, k=4 → 3+2; 4줄 k=3 → 2+2; 3줄·2줄은 k가 몇이든
///   통째; 74줄 문단도 k=1이면 통째로 다음 쪽; 빈 쪽에서 시작하는 42줄 문단(41줄 들어감)은
///   40 + 2, 43줄은 41 + 2).
/// - **문단 보호**(bit 18): 부분 채운 단에서는 나누지 않는다(통째 이동). 빈 단보다 긴
///   문단은 그 빈 단에서부터 나뉜다 (74줄 문단이 새 쪽에서 41 + 33, 빈 쪽 42줄은 41 + 1).
struct HwpParagraphSplitPolicy: Equatable {
    var protectsWidowOrphan = false
    var keepsLinesTogether = false

    /// 외톨이줄 보호가 경계 양쪽에 요구하는 최소 줄 수.
    static let minimumLinesAtBoundary = 2

    /// 보호 없음 — 들어가는 줄을 그대로 남긴다.
    static let none = HwpParagraphSplitPolicy()

    init(protectsWidowOrphan: Bool = false, keepsLinesTogether: Bool = false) {
        self.protectsWidowOrphan = protectsWidowOrphan
        self.keepsLinesTogether = keepsLinesTogether
    }

    init(paraShape: CoreHwp.HwpParaShape) {
        self.init(
            protectsWidowOrphan: paraShape.property1Info.protectsWidowOrphan,
            keepsLinesTogether: paraShape.property1Info.keepsLinesTogether
        )
    }

    /// 탐욕 적합 줄 수 `count`(남은 `remaining` 줄 가운데)를 규칙으로 깎은 값. 남은 줄이 다
    /// 들어가면 깎을 것이 없다. `columnIsEmpty`인 단에서는 문단 보호를 적용하지 않는다 —
    /// 빈 단에도 안 들어가는 문단은 어차피 나뉘어야 하고, 안 그러면 진행이 없다.
    func allowedCount(fitting count: Int, remaining: Int, columnIsEmpty: Bool) -> Int {
        guard count < remaining else { return count }
        var allowed = count
        if protectsWidowOrphan {
            allowed = min(allowed, remaining - Self.minimumLinesAtBoundary)
            if allowed < Self.minimumLinesAtBoundary {
                allowed = 0
            }
        }
        if keepsLinesTogether, !columnIsEmpty {
            allowed = 0
        }
        return max(0, allowed)
    }
}

/// 쪽 끝 적합 판정(#222)에 쓸, 줄 프레임만으로는 알 수 없는 줄 상자 — 흐름 분할의 진입 판정
/// (`HwpPaginator.entryFragmentLineCount`)과 조각 루프(`appendParagraphAcrossColumns`)가 **같은
/// 값**으로 나머지(`HwpFragmentRemainder`)를 만들어야 첫 조각의 줄 수가 갈리지 않는다.
struct HwpFragmentFitSource {
    /// 줄 프레임이 빈 문단(빈 문단 앵커)의 줄 상자 높이 — 페이지네이터의 `layout`이 그 줄을
    /// 비우므로 따로 잰다.
    var emptyLineBoxHeight: CGFloat?
    /// 문단 높이를 저장본 줄 캐시로 잡았을 때 그 캐시의 줄 상자 바닥 (첫 줄 상자 상단 기준, pt).
    var cachedLastLineBoxBottom: CGFloat?

    static let none = HwpFragmentFitSource()
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
    /// 문단 높이를 저장본 줄 캐시로 잡았을 때 그 마지막 줄의 줄 간격 (pt) — 문단을 끝내는
    /// 조각 블록에 `hwp.cachedTrailingLineSpacing`으로 실려 단 구분선 바닥(#191)이 뺀다. CT
    /// 측정 높이면 nil. `heightIsMeasured`(수치 일치)와 별개로 **실제 선택**을 나른다 (PR 리뷰:
    /// 캐시 1줄 20+12과 CT 2줄 16×2처럼 총높이가 같아도 마지막 줄 간격은 다르다).
    let cachedTrailingSpacing: CGFloat?
    let paragraphId: UInt32?
    /// 문단 전체 블록의 URL과 조각 블록의 URL (필드 스팬 문단은 조각에 전파하지 않는다).
    let hyperlinkURL: String?
    let fragmentURL: String?
    /// 문단 위 간격 — 첫 조각 앞에서 커서로 소비하고, 통째로 옮기면 무르고 새 단 머리에 다시
    /// 적용한다.
    var beforeGap: CGFloat = 0
    /// 조각마다 남은 자리에서 상수로 빼는 문단 전체 각주 예약 — 조각별 귀속 문맥
    /// (`fragmentFootnotes`)이 있으면 0이고 예약은 줄마다 그 조각 범위로 잰다 (#207).
    var reservedFootnoteHeight: CGFloat = 0
    /// 쪽·단 경계의 분할 규칙 (#207).
    var splitPolicy: HwpParagraphSplitPolicy = .none
    /// 조각별 각주 귀속 문맥 (#207) — nil이면 문단 단위 수집.
    var fragmentFootnotes: HwpFlowFragmentFootnotes?
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

    /// 줄 프레임이 없는 문단(빈 문단 앵커 — `HwpPaginator.layout`이 줄을 비운다)의 적합 높이
    /// — 그 한 줄의 상자 높이다 (#222). nil이면 텍스트 몫 전체(`advances.textHeight`).
    private let fitHeightWithoutLines: CGFloat?

    /// `fitSource`는 줄 프레임만으로 알 수 없는 줄 상자 (#222) — 캐시의 마지막 줄 상자 바닥은
    /// 호출자가 문단 높이로 캐시를 **골랐을 때만** 싣는다(`FlowSplitInput.cachedLineBoxBottom` —
    /// 수치 일치 `heightIsMeasured`로 가르면 캐시와 CT 총높이가 우연히 같은 문단에서 문단 전체
    /// 판정과 갈린다). 다시 재면(`replace`) 버린다.
    init(
        lines: [HwpLineFrame], textHeight: CGFloat, measuredWidth: CGFloat, heightIsMeasured: Bool,
        fitSource: HwpFragmentFitSource = .none
    ) {
        self.lines = lines
        advances = HwpFragmentLineAdvances(
            lines: lines, textHeight: textHeight,
            cachedLastLineBoxBottom: fitSource.cachedLastLineBoxBottom
        )
        self.measuredWidth = measuredWidth
        self.heightIsMeasured = heightIsMeasured
        fitHeightWithoutLines = fitSource.emptyLineBoxHeight
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

    /// 이 나머지의 조각 블록에 실을 캐시 마지막 줄 줄 간격 — 한 번이라도 목적 단 폭으로 다시
    /// 쟀으면(`remeasureCount > 0`) 높이가 더는 캐시가 아니라 nil이다 (PR 리뷰: 최초
    /// `placement.cachedTrailingSpacing`을 그대로 넘기면 다시 잰 문단 끝 조각의 단 구분선이
    /// 캐시 간격을 뺀다).
    func cachedTrailingSpacing(from placement: HwpFragmentPlacement) -> CGFloat? {
        remeasureCount > 0 ? nil : placement.cachedTrailingSpacing
    }

    /// 다음 줄부터 `available`에 들어가는 줄 수와 그 누적 전진량. 줄을 하나 더할 때마다 지금까지
    /// 놓은 줄들의 **상자 하단 최댓값**(각 줄: 앞 줄들의 전진량 합 + `HwpFragmentLineAdvances.fitHeight`)
    /// 에 그 줄까지의 각주 예약을 더해 들어가는지 보고 (#222 — 마지막으로 남기는 줄의 줄 간격 여분은
    /// 쪽·단 아래로 넘쳐도 된다), 방출 높이는 그 줄들의 전진량 합이다. 판정은 엄격 부등호다
    /// (`HwpPageEndFit`).
    ///
    /// `extra`는 줄 `i`(문단 줄 색인)까지 놓을 때 그 줄들이 요구하는 **추가** 높이 — 그 줄에
    /// 참조가 놓인 각주의 예약(#207, `HwpFlowFragmentFootnotes.reservation(through:)`)이다.
    /// 줄이 늘수록 줄지 않는 단조 함수라 첫 실패에서 멈춘다. 반환 높이는 전진량 합뿐이다
    /// (예약은 각주 영역이 차지한다). 예약은 그 줄 상자가 아니라 **최댓값**에 더한다 (#222 PR
    /// 리뷰): 고정 줄 간격이 앞 줄 상자보다 작으면 앞 줄이 더 아래로 내려가는데, 뒤 줄의 각주가
    /// 영역을 넓히는 순간 그 앞 줄 상자가 각주 영역과 겹친다(50pt·10pt 두 줄·고정 16pt, 둘째 줄
    /// 각주 24.17 — 둘째 줄 상자 26만 보면 두 줄이 남는다). 각주가 없으면 앞 줄들은 이미 통과했으므로
    /// 결과가 같다.
    func fit(
        in available: CGFloat, extra: (Int) -> CGFloat = { _ in 0 }
    ) -> (count: Int, height: CGFloat) {
        var count = 0
        var height: CGFloat = 0
        var lowestBoxBottom: CGFloat = 0
        while lineIndex + count < lines.count {
            let index = lineIndex + count
            let boxBottom = max(lowestBoxBottom, height + advances.fitHeight(index))
            guard HwpPageEndFit.fits(boxBottom + extra(index), in: available) else { break }
            lowestBoxBottom = boxBottom
            height += advances.advance(index)
            count += 1
        }
        return (count, height)
    }

    /// `fit`에 쪽 나눔 보호 규칙(#207)을 씌운 것 — 규칙이 줄 수를 깎으면 높이도 그 줄까지의
    /// 전진량 합으로 다시 잰다. 진입 판정(`HwpPaginator.placeFlowParagraph`)과 조각 루프
    /// (`appendParagraphAcrossColumns`)가 **같은 함수**로 첫 조각의 줄 수를 정해야 갈리지 않는다.
    func fit(
        in available: CGFloat,
        policy: HwpParagraphSplitPolicy,
        columnIsEmpty: Bool,
        extra: (Int) -> CGFloat = { _ in 0 }
    ) -> (count: Int, height: CGFloat) {
        let greedy = fit(in: available, extra: extra)
        let allowed = policy.allowedCount(
            fitting: greedy.count, remaining: lines.count - lineIndex, columnIsEmpty: columnIsEmpty
        )
        guard allowed < greedy.count else { return greedy }
        var height: CGFloat = 0
        for offset in 0 ..< allowed {
            height += advances.advance(lineIndex + offset)
        }
        return (allowed, height)
    }

    /// 다음 줄 하나만 놓을 때의 전진량 — 빈 단에 안 들어가도 진행 보장으로 싣는 몫.
    ///
    /// 줄이 없는 문단(빈 문단 앵커 — `HwpPaginator.layout`이 줄을 비운다)은 텍스트 몫 전체다 —
    /// 그런 문단도 다단에서 통째로 옮겨진다(`moveWholeParagraphToNextColumn`)(#222 리뷰: 빈 줄 배열을
    /// 인덱싱해 멈췄다).
    var firstLineHeight: CGFloat {
        guard lineIndex < lines.count else { return advances.textHeight }
        return advances.advance(lineIndex)
    }

    /// 다음 줄 하나를 남길지 판정할 때의 높이 — 그 줄의 상자 높이다 (#222,
    /// `HwpFragmentLineAdvances.fitHeight`). 통째로 옮긴 새 단 머리에 문단 위 간격을 다시 실을지
    /// (`HwpPaginator.advancePastUnplacedFragment`)도 이 값으로 가른다. 줄이 없는 문단은
    /// `remainingFitHeight`와 같은 값(빈 문단 앵커 줄의 상자)이다.
    var firstLineFitHeight: CGFloat {
        guard lineIndex < lines.count else { return remainingFitHeight }
        return advances.fitHeight(lineIndex)
    }

    /// 남은 줄을 모두 한 조각으로 남길 때의 적합 높이 (#222) — 줄이 없으면 빈 문단 앵커 줄의
    /// 상자(`fitHeightWithoutLines`), 그것도 없으면 텍스트 몫 전체다.
    var remainingFitHeight: CGFloat {
        guard lineIndex < lines.count else {
            return lines.isEmpty ? fitHeightWithoutLines ?? advances.textHeight : 0
        }
        return advances.fitHeight(from: lineIndex, through: lines.count - 1)
    }

    /// 아직 놓지 않은 줄들의 문자열 범위 (문단 조판 문자열 기준).
    func remainingRange(in attributedString: NSAttributedString) -> NSRange? {
        guard lineIndex < lines.count else { return nil }
        let location = lines[lineIndex].attributedRange.location
        return NSRange(location: location, length: max(0, attributedString.length - location))
    }

    /// 다시 잰 줄로 나머지를 바꾼다. `frame`은 `remainingRange`의 조각을 `width` 폭으로 잰
    /// 것이고 `textHeight`는 그 텍스트 몫(문단 위 간격 제외)이다.
    mutating func replace(
        with frame: HwpParagraphFrame, textHeight: CGFloat, width: CGFloat, range: NSRange
    ) {
        lines = frame.lines.map { line in
            HwpLineFrame(
                origin: line.origin,
                width: line.width,
                baseline: line.baseline,
                attributedRange: NSRange(
                    location: line.attributedRange.location + range.location,
                    length: line.attributedRange.length
                ),
                inlineAnchors: line.inlineAnchors,
                boxHeight: line.boxHeight,
                objectBaselineRatio: line.objectBaselineRatio
            )
        }
        advances = HwpFragmentLineAdvances(lines: lines, textHeight: textHeight)
        measuredWidth = width
        heightIsMeasured = true
        start = range.location
        lineIndex = 0
        remeasureCount += 1
    }
}
