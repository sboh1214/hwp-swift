import CoreGraphics
import CoreHwp
import Foundation

// 각주 이어짐 (#165) — 절대 캐시 모드의 각주 스택 규칙과 줄 캐시 기반 분할.
//
// 한글.app 12.30 실측 (헌법주석 1,030쪽을 PDF로 내보내 쪽마다 각주 번호·이어짐·줄 수를
// 전수 대조 — 1,026쪽 일치, 나머지 4쪽은 조각 귀속 차이·빈 각주·빈 문단):
// 1. 각주 스택은 본문 하단에 **바닥 정렬**된다. 마지막 줄의 줄 **상자** 아래가 본문
//    하단 경계에 닿고, 그 줄의 줄 간격은 세지 않는다.
// 2. 들어갈 자리 = 본문 하단 − 본문 마지막 줄 상자 아래(줄 간격 제외) − 구분선 위 여백
//    − 구분선 아래 여백. 구분선 굵기는 자리에 세지 않는다 — 선은 위 여백 끝에
//    **가운데** 맞춰 그려지고 아래 여백은 선 가운데부터 잰다.
// 3. 각주 사이 여백은 앞 각주 마지막 줄 상자 아래에서 다음 각주 첫 줄 위까지다
//    (마지막 줄의 줄 간격을 대체한다 — 사이 피치 11.83pt = 줄 높이 9 + 여백 2.83).
// 4. 한 각주가 통째로 안 들어가면: 줄 캐시에 분할 지점(세로 위치 리셋)이 있으면 그
//    앞 몫만 싣고 나머지를 다음 쪽 **첫** 각주로 잇는다 — 구분선은 다시 그리고 번호는
//    반복하지 않으며 이어지는 줄은 내어쓰기 자리에서 시작한다. 분할 지점이 없으면 각주
//    전체를 다음 쪽으로 옮긴다. 뒤에 오는 각주도 모두 함께 넘어간다 (순서 보존).
//    한글은 한 줄만 들어가도 나눈다 (`0, 0, 1172, …` 캐시 = 첫 줄만 앞 쪽).

/// 각주 문단 줄 캐시의 줄 하나 (HWPUNIT). 여러 세그먼트로 된 줄은 첫 세그먼트만 센다.
struct HwpFootnoteCacheLine: Equatable {
    let location: Int
    let height: Int
    let spacing: Int

    var advance: Int {
        height + spacing
    }

    var spacedBottom: Int {
        location + advance
    }
}

enum HwpFootnoteCacheLines {
    /// 줄 캐시를 줄 목록으로 편다 — 비어 있거나 손상(음수 높이·간격)이면 nil.
    ///
    /// 세그먼트의 bit 17(줄의 첫 세그먼트)이 꺼진 채 앞 줄과 같은 세로 위치면 같은 줄의
    /// 이어지는 세그먼트다. 켜진 채 같은 위치면 새 줄이다 — 한글이 첫 줄만 앞 쪽에
    /// 두고 나머지를 다음 쪽 0에서 다시 시작한 `0, 0` 분할이 그 형태다.
    static func lines(of paragraph: CoreHwp.HwpParagraph) -> [HwpFootnoteCacheLine]? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !segments.isEmpty else { return nil }
        var lines: [HwpFootnoteCacheLine] = []
        for (index, segment) in segments.enumerated() {
            guard segment.lineHeight >= 0, segment.lineSpacing >= 0 else { return nil }
            let location = Int(segment.lineLocation)
            let startsLine = index == 0 || segment.property & (1 << 17) != 0
            if !startsLine, let last = lines.last, last.location == location {
                continue
            }
            lines.append(HwpFootnoteCacheLine(
                location: location,
                height: Int(segment.lineHeight),
                spacing: Int(segment.lineSpacing)
            ))
        }
        return lines
    }

    /// 쪽 분할 지점 — 앞 줄보다 세로 위치가 작거나 같은 줄의 인덱스 (한글이 다음 쪽으로
    /// 넘긴 첫 줄). 줄 위치는 각주 시작 기준이라 새 쪽에서 0으로 되돌아간다.
    static func pageBreaks(in lines: [HwpFootnoteCacheLine]) -> [Int] {
        guard lines.count > 1 else { return [] }
        return (1 ..< lines.count).filter { lines[$0].location <= lines[$0 - 1].location }
    }

    /// `start` 뒤의 **첫** 분할 지점 (문단 전체 기준 인덱스) — 없으면 nil. 남은 줄을 복사하거나
    /// 분할 지점을 전부 모으지 않고 이 쪽 몫만 훑으므로 (#165 리뷰) 이월이 쪽마다 반복돼도
    /// 전체 일이 줄 수에 비례한다 — 남은 줄을 배열로 떠서 훑으면 쪽 수 × 남은 줄 수다.
    static func firstPageBreak(in lines: [HwpFootnoteCacheLine], after start: Int) -> Int? {
        var index = start + 1
        while index < lines.count {
            if lines[index].location <= lines[index - 1].location {
                return index
            }
            index += 1
        }
        return nil
    }

    /// 줄 범위의 높이 (pt) — 같은 쪽 안은 첫 줄 위부터 전진량 끝의 **최댓값**까지
    /// (`HwpParagraphLayout.CachedLineExtent.advanceHeight`와 같은 정의 — 그 정본도 모든
    /// 세그먼트의 최댓값을 잡는다), 범위가 쪽을 넘으면 쪽 몫의 합.
    ///
    /// 마지막 줄의 전진량 끝만 보면 안 된다 (#165 리뷰): 줄 간격이 고정값이라 피치가 글자
    /// 상자보다 짧거나 줄 높이가 섞이면 앞의 큰 줄이 마지막 줄 아래까지 내려오는데, 그
    /// 몫을 빼고 재면 스택 계획이 실제로 안 들어가는 각주·앞 조각을 들여 본문 위에 놓는다.
    static func height(of lines: [HwpFootnoteCacheLine], in range: Range<Int>) -> CGFloat {
        let clamped = range.clamped(to: lines.indices)
        guard !clamped.isEmpty else { return 0 }
        var total = 0
        var runStart = clamped.lowerBound
        var runBottom = Int.min
        for index in clamped {
            if index > clamped.lowerBound, lines[index].location <= lines[index - 1].location {
                total += runBottom - lines[runStart].location
                runStart = index
                runBottom = Int.min
            }
            runBottom = max(runBottom, lines[index].spacedBottom)
        }
        total += runBottom - lines[runStart].location
        return HwpUnits.points(fromHwpUnit: Int32(clamping: max(0, total)))
    }

    /// 범위 마지막 줄의 줄 간격 (pt) — 각주 끝·쪽 끝에서 세지 않는 몫.
    static func trailingSpacing(of lines: [HwpFootnoteCacheLine], in range: Range<Int>) -> CGFloat {
        let clamped = range.clamped(to: lines.indices)
        guard let last = clamped.last else { return 0 }
        // 범위 마지막 쪽 몫의 전진량 끝 최댓값과 줄 **상자** 아래 최댓값의 차 — 줄이 고르면
        // 마지막 줄의 줄 간격이고, 앞의 큰 줄이 몫의 아래를 정하면 (#165 리뷰) 그 줄의 몫이다.
        // `height(of:in:)`가 그 최댓값까지 재므로 둘을 합치면 상자 아래가 나온다.
        var spacedBottom = Int.min
        var boxBottom = Int.min
        var index = last
        while index >= clamped.lowerBound {
            spacedBottom = max(spacedBottom, lines[index].spacedBottom)
            boxBottom = max(boxBottom, lines[index].location + lines[index].height)
            if index > clamped.lowerBound, lines[index].location <= lines[index - 1].location {
                break
            }
            index -= 1
        }
        return HwpUnits.points(fromHwpUnit: Int32(clamping: max(0, spacedBottom - boxBottom)))
    }

    /// 각 줄부터 문단 끝까지의 높이 (HWPUNIT) — `height(of:in:)`를 뒤에서부터 한 번에 누적한
    /// 표라 `i`번째 값은 `height(of: lines, in: i ..< lines.count)`의 정수 합과 같다 (#165
    /// 리뷰). 이월이 쪽마다 남은 줄을 다 더하면 쪽 수 × 줄 수의 일이라 원본 조판에 실어 나른다.
    static func remainingHeights(of lines: [HwpFootnoteCacheLine]) -> [Int] {
        var heights = [Int](repeating: 0, count: lines.count)
        // 이 줄이 속한 쪽 몫 뒤의 몫들의 합, 그 몫 안에서 이 줄부터 끝까지의 전진량 끝 최댓값
        var afterRun = 0
        var runBottom = Int.min
        var index = lines.count - 1
        while index >= 0 {
            let line = lines[index]
            let next = index + 1
            if next == lines.count || lines[next].location <= line.location {
                // 쪽 몫의 마지막 줄 — 뒤 몫의 합을 확정하고 새 몫을 시작한다
                afterRun = next < lines.count ? heights[next] : 0
                runBottom = line.spacedBottom
            } else {
                runBottom = max(runBottom, line.spacedBottom)
            }
            heights[index] = runBottom - line.location + afterRun
            index -= 1
        }
        return heights
    }
}

// MARK: - 원본 조판 이월

extension HwpFootnoteLayout {
    /// 이월 입력이 나르는 문단 **전체**의 조판 (#165 리뷰) — 이어지는 조각은 원본에서 잘라
    /// 내므로 원본이 있으면 CT 조판을 건너뛴다. 쪽마다 문단 전체를 다시 조판하면 이월이 길게
    /// 이어지는 문단에서 쪽 수 × 줄 수의 일이 된다 (실측, 디버그 빌드: 2,000줄·99쪽 합성
    /// 각주 29.9s → 0.7s, 32,000줄·1,599쪽 10.6s — 쪽 수에 비례). 폭이 다르면 (구역이 바뀐
    /// 쪽) 줄 나눔이 달라지므로 다시 조판한다 — 줄 캐시는 문단의 것이라 폭과 무관하게 그대로
    /// 쓴다. 남은 줄의 높이 누적표(`remainingHeights`)도 같이 나른다.
    struct SourceLayout {
        /// 이 조판을 만든 각주 영역 폭
        let width: CGFloat
        let attributed: NSAttributedString
        let lines: [HwpLineFrame]
        let cacheLines: [HwpFootnoteCacheLine]
        /// 각 캐시 줄부터 문단 끝까지의 높이 (HWPUNIT, `HwpFootnoteCacheLines.remainingHeights`)
        /// — 남은 줄의 높이를 쪽마다 남은 줄을 다 더하지 않고 한 번에 읽는다.
        let remainingHeights: [Int]

        init(
            width: CGFloat, attributed: NSAttributedString, lines: [HwpLineFrame],
            cacheLines: [HwpFootnoteCacheLine]
        ) {
            self.width = width
            self.attributed = attributed
            self.lines = lines
            self.cacheLines = cacheLines
            remainingHeights = HwpFootnoteCacheLines.remainingHeights(of: cacheLines)
        }

        /// `start`부터 끝까지 남은 줄의 높이 (pt) —
        /// `HwpFootnoteCacheLines.height(of: cacheLines, in: start ..< cacheLines.count)`와 같은 값.
        func remainingHeight(from start: Int) -> CGFloat {
            guard start >= 0, start < remainingHeights.count else { return 0 }
            return HwpUnits.points(fromHwpUnit: Int32(clamping: max(0, remainingHeights[start])))
        }
    }
}

// MARK: - 조각 문자열

extension HwpFootnoteLayout {
    /// 각주 문단 조각의 조판 문자열과 줄 프레임.
    struct Fragment {
        let attributed: NSAttributedString
        let lines: [HwpLineFrame]
        /// 이 조각이 **원본 조판 문자열**에서 차지한 범위 — 그 끝이 다음 쪽 조각의 시작
        /// 문자 위치다 (#165 리뷰, `Input.placedLength`).
        let sourceRange: NSRange
    }

    /// 캐시 줄 범위에 해당하는 CT 줄 조각 — 캐시 줄 수와 CT 줄 수가 다르면 (폰트 대체)
    /// 비례로 대응시킨다 (`HwpAbsoluteCachePlacer.runAttributedSlice`와 같은 근사).
    /// 이어지는 조각은 첫 줄 들여쓰기를 둘째 줄에 맞춘다 (한글 실측: 이어지는 줄은
    /// 내어쓰기 자리에서 시작).
    ///
    /// `placedLength`: 앞 쪽이 **실제로 그린** 문자 길이 (#165 리뷰). 구역이 바뀌어 폭이
    /// 달라지면 줄 나눔이 달라 비례 환산이 앞 쪽의 마지막 글자와 다른 자리를 가리키므로,
    /// 이어지는 조각은 이 문자 위치를 경계로 삼는다. 폭이 그대로면 비례 환산 결과가 곧
    /// 그 위치라 값이 같다 (코퍼스 불변).
    static func fragment(
        of attributed: NSAttributedString,
        lines: [HwpLineFrame],
        cacheLineCount: Int,
        cacheRange: Range<Int>,
        startingAt placedLength: Int = 0
    ) -> Fragment {
        let empty = Fragment(
            attributed: NSAttributedString(string: ""), lines: [],
            sourceRange: NSRange(location: placedLength, length: 0)
        )
        guard !lines.isEmpty, cacheLineCount > 0, !cacheRange.isEmpty else { return empty }
        func ctIndex(_ cacheIndex: Int) -> Int {
            guard cacheIndex < cacheLineCount else { return lines.count }
            let proportional = Double(cacheIndex) / Double(cacheLineCount) * Double(lines.count)
            return min(lines.count, Int(proportional.rounded()))
        }
        let isContinuation = cacheRange.lowerBound > 0
        let end = max(ctIndex(cacheRange.lowerBound), ctIndex(cacheRange.upperBound))
        // 이어지는 조각은 경계 문자를 **담은** 줄부터 시작한다 (폭이 그대로면 그 줄이 곧
        // 비례 환산 결과다). 그 줄이 경계보다 앞에서 시작하면 앞부분은 이미 그려졌으므로
        // 문자 범위에서 잘라 낸다.
        let start = isContinuation && placedLength > 0
            ? min(end, firstLineIndex(in: lines, endingAfter: placedLength))
            : ctIndex(cacheRange.lowerBound)
        guard start < end else { return empty }
        let slice = lines[start ..< end]
        let lineRange = slice.dropFirst().reduce(slice[start].attributedRange) {
            NSUnionRange($0, $1.attributedRange)
        }
        let clipped = max(lineRange.location, min(placedLength, NSMaxRange(lineRange)))
        let range = isContinuation
            ? NSRange(location: clipped, length: NSMaxRange(lineRange) - clipped)
            : lineRange
        let text = isContinuation
            ? HwpParagraphLayout.continuationFragment(of: attributed, range: range)
            : attributed.attributedSubstring(from: range)
        // 뒤에 이월분이 남는 조각은 **이어짐 표식**을 단다 (PR 리뷰) — 다른 쪽 분할 경로
        // (`HwpTableSplitter`·다단 run)와 같은 마커다. 컨테이너 문단은 위치 열쇠가 없어
        // 복사(`HwpSelectionGeometry.joinsWithPrevious`)가 이 표식으로 조각을 잇고, 양쪽
        // 정렬(`HwpWordJustification`)은 이 표식으로 조각 끝 줄이 문단의 마지막 줄이 아님을
        // 안다. 없으면 복사에 헛 문단 부호가 끼고 조각 끝 줄이 벌려지지 않는다.
        let continues = cacheRange.upperBound < cacheLineCount
        return Fragment(
            attributed: continues ? HwpTableSplitter.markedAsContinuedFragment(text) : text,
            lines: fragmentLines(slice, range: range, dropping: range.location - lineRange.location),
            sourceRange: range
        )
    }

    /// 문자 위치 `length`를 넘어 끝나는 첫 줄의 인덱스 (없으면 `lines.count`). 줄의 문자
    /// 범위는 단조 증가하므로 이분 탐색한다 (#165 리뷰) — 앞에서부터 훑으면 이월이 길게
    /// 이어지는 문단에서 쪽마다 이미 실린 줄을 다시 세어 쪽 수 × 줄 수가 된다.
    private static func firstLineIndex(
        in lines: [HwpLineFrame], endingAfter length: Int
    ) -> Int {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(lines[middle].attributedRange) > length {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    /// 조각 줄 프레임 — 첫 줄이 경계보다 앞에서 시작하면 (폭이 바뀐 이월) 그 몫을 잘라
    /// 문자 범위를 조각 기준으로 맞춘다. 잘린 줄의 기하와 앵커는 **앞 쪽 폭 기준**이라
    /// 근사다 — 개체를 담은 각주는 나누지 않으므로 (`carriesObjects`) 앵커는 버린다.
    private static func fragmentLines(
        _ slice: ArraySlice<HwpLineFrame>, range: NSRange, dropping drop: Int
    ) -> [HwpLineFrame] {
        var frames = HwpParagraphLayout.fragmentLineFrames(slice, range: range)
        guard drop > 0, let first = frames.first else { return frames }
        frames[0] = HwpLineFrame(
            origin: first.origin,
            width: first.width,
            baseline: first.baseline,
            attributedRange: NSRange(
                location: 0, length: max(0, first.attributedRange.length - drop)
            ),
            inlineAnchors: []
        )
        return frames
    }
}

// MARK: - 절대 캐시 모드 배치

extension HwpFootnoteLayout {
    /// 스택에 들어갈 항목 — 통째로(`lineRange == nil`) 또는 앞 몫만 (쪽 끝에서 나뉜 문단).
    struct StackEntry {
        let measured: MeasuredFootnote
        /// 이 쪽에 싣는 캐시 줄 범위 (남은 줄 기준) — nil이면 문단 전체
        let lineRange: Range<Int>?
        /// 각주(번호)의 마지막 항목인지 — 마지막 줄의 줄 간격을 세지 않는 자리
        let isNoteEnd: Bool
    }

    struct StackPlan {
        var entries: [StackEntry] = []
        /// 다음 쪽으로 넘기는 입력 — 입력 저장소의 슬라이스 (복사 없음, #165 리뷰). 앞 조각을
        /// 나눈 쪽만 그 조각의 이월 입력을 머리에 붙인 새 배열이다.
        var overflow: ArraySlice<Input> = []
        /// 항목 높이와 각주 사이 여백의 합 (구분선 여백 제외)
        var stackedHeight: CGFloat = 0
    }

    /// 들어맞음 판정의 허용 오차 (pt). 한글은 1 HWPUNIT(0.01pt) 여유에도 싣는다
    /// (헌법주석 실측 — 여유 0.01pt 5쪽 전부 실림). 부동소수 잡음만 흡수한다.
    static let fitTolerance: CGFloat = 0.001

    /// 본문 아래 자리에 맞춰 각주를 순서대로 쌓는 계획 — 한글의 이어짐 규칙 (#165).
    ///
    /// - available: 각주 줄이 들어갈 자리 (구분선 여백을 뺀 값)
    /// - fullPage: 빈 쪽의 같은 자리 — 진행 보장 하한
    /// - emptyPage: 본문이 없는 쪽 (이월 드레인) — 첫 각주는 크기와 무관하게 싣는다
    static func stackPlan(
        notes: MeasuredNotes,
        available: CGFloat,
        fullPage: CGFloat,
        betweenNotes: CGFloat,
        emptyPage: Bool
    ) -> StackPlan {
        var plan = StackPlan()
        var index = 0
        // 각주는 이 순서로만 재진다 (`MeasuredNotes`, #165 리뷰) — 처음 안 들어가는 각주에서
        // 멈추므로 뒤에 남은 각주는 재지 않고 이월된다.
        while index < notes.count {
            let group = noteGroup(in: notes, from: index)
            let gap = plan.entries.isEmpty ? 0 : betweenNotes
            let noteHeight = groupHeight(notes, group)
            if plan.stackedHeight + gap + noteHeight <= available + fitTolerance {
                appendWhole(group, of: notes, to: &plan, gap: gap, height: noteHeight)
                index = group.upperBound
                continue
            }
            // 통째로 안 들어간다 — 캐시에 분할 지점이 있으면 그 앞 몫을 재 본다.
            if let split = splitPoint(in: notes, group: group) {
                let head = headEntries(group, of: notes, gap: gap, split: split)
                // 앞 조각 **전체**가 들어가야 나눈다 (#165 리뷰). 첫 줄만 보고 나누면 분할
                // 지점까지의 줄이 전부 방출돼 스택이 자리를 넘고, 바닥 정렬이 그 스택을 본문
                // 위로 올린다 — 캐시가 저작된 자리보다 우리 본문 하한이 낮을 때 (stale 보정,
                // 그려지는 자손) 생긴다. 안 들어가면 통째로 다음 쪽이다. 진행 보장은 앞
                // 조각에도 같다: 이 쪽이 비었는데 빈 쪽에도 안 들어가는 (또는 빈 쪽 자체인)
                // 앞 조각은 그대로 싣는다.
                if plan.stackedHeight + head.height <= available + fitTolerance
                    || plan.entries.isEmpty && (emptyPage || head.height > fullPage)
                {
                    appendHead(head, of: notes, to: &plan, split: split)
                    return plan
                }
            } else if plan.entries.isEmpty, emptyPage || noteHeight > fullPage {
                // 진행 보장: 이 쪽에 아무것도 없는데 빈 쪽에도 안 들어가는 (또는 빈 쪽
                // 자체인) 각주는 그대로 싣는다 — 넘기면 영영 못 싣는다.
                appendWhole(group, of: notes, to: &plan, gap: gap, height: noteHeight)
                index = group.upperBound
                continue
            }
            plan.overflow = notes.inputs(from: group.lowerBound)
            return plan
        }
        return plan
    }

    /// 같은 각주의 이어지는 항목 범위 — 여러 문단짜리 각주 하나.
    ///
    /// 표시 번호가 아니라 **식별자**로 가른다 (#165 리뷰): 쪽마다 번호를 새로 시작하면
    /// (표 134 모드 2) 이월된 각주와 그 쪽의 새 각주가 같은 번호를 갖는데, 번호로 묶으면
    /// 둘이 한 각주가 돼 사이 여백이 사라지고 (앞 조각이 각주의 끝이 아니게 돼) 마지막 줄
    /// 간격이 높이에 남으며, 하나가 안 들어가면 다른 하나까지 다음 쪽으로 밀린다.
    private static func noteGroup(in notes: MeasuredNotes, from start: Int) -> Range<Int> {
        var end = start + 1
        while end < notes.count, notes.noteId(at: end) == notes.noteId(at: start) {
            end += 1
        }
        return start ..< end
    }

    private static func groupHeight(_ notes: MeasuredNotes, _ group: Range<Int>) -> CGFloat {
        group.reduce(0) { total, index in
            total + notes[index].measurement.stackingHeight(isNoteEnd: index == group.upperBound - 1)
        }
    }

    /// 각주 안 첫 쪽 분할 지점 — (항목 인덱스, 그 항목에서 이 쪽에 싣는 줄 수).
    /// 앞 문단의 마지막 줄보다 위치가 낮게 시작하는 뒤 문단은 통째로 다음 쪽이다 (줄 수 0).
    private static func splitPoint(
        in notes: MeasuredNotes, group: Range<Int>
    ) -> (index: Int, lineCount: Int)? {
        // 개체를 담은 각주는 나누지 않는다 (#165 리뷰, `NoteMeasurement.carriesObjects`) —
        // 통째로 다음 쪽에 옮긴다.
        guard !group.contains(where: { notes[$0].measurement.carriesObjects }) else {
            return nil
        }
        var previousBottom: Int?
        for index in group {
            // 캐시 없는 문단은 분할 근거가 없다 — 그 뒤 문단과의 위치 비교도 끊는다.
            let measurement = notes[index].measurement
            guard let lines = measurement.cacheLines else {
                previousBottom = nil
                continue
            }
            // 남은 줄은 인덱스로만 본다 (#165 리뷰) — 쪽마다 남은 줄을 배열로 뜨면 이월이
            // 길게 이어지는 문단에서 쪽 수 × 줄 수의 복사가 된다.
            let start = measurement.placedLineCount
            guard start < lines.count else { continue }
            if let previousBottom, index > group.lowerBound, lines[start].location < previousBottom {
                return (index, 0)
            }
            if let firstBreak = HwpFootnoteCacheLines.firstPageBreak(in: lines, after: start) {
                return (index, firstBreak - start)
            }
            previousBottom = lines[lines.count - 1].spacedBottom
        }
        return nil
    }

    private static func appendWhole(
        _ group: Range<Int>, of notes: MeasuredNotes,
        to plan: inout StackPlan, gap: CGFloat, height: CGFloat
    ) {
        for index in group {
            plan.entries.append(StackEntry(
                measured: notes[index], lineRange: nil, isNoteEnd: index == group.upperBound - 1
            ))
        }
        plan.stackedHeight += gap + height
    }

    /// 분할 지점 앞 몫 — 스택에 실릴 항목과 그 높이 (앞 각주와의 여백 포함). 싣기 전에
    /// 들어맞는지 재는 데 쓰므로 `appendHead`와 같은 값이어야 한다.
    private static func headEntries(
        _ group: Range<Int>, of notes: MeasuredNotes,
        gap: CGFloat, split: (index: Int, lineCount: Int)
    ) -> (entries: [StackEntry], height: CGFloat) {
        var entries: [StackEntry] = []
        var height = gap
        for index in group.lowerBound ..< split.index {
            entries.append(StackEntry(measured: notes[index], lineRange: nil, isNoteEnd: false))
            height += notes[index].measurement.stackingHeight(isNoteEnd: false)
        }
        let splitNote = notes[split.index]
        if split.lineCount > 0 {
            let range = 0 ..< split.lineCount
            entries.append(StackEntry(measured: splitNote, lineRange: range, isNoteEnd: true))
            height += splitNote.measurement.headHeight(lines: range)
        } else if let last = entries.indices.last {
            // 뒤 문단이 통째로 넘어가면 앞 문단이 이 쪽의 마지막 줄이다.
            let entry = entries[last]
            entries[last] = StackEntry(measured: entry.measured, lineRange: nil, isNoteEnd: true)
            height -= entry.measured.measurement.stackingHeight(isNoteEnd: false)
            height += entry.measured.measurement.stackingHeight(isNoteEnd: true)
        }
        return (entries, height)
    }

    /// 분할 지점 앞 몫을 싣고 나머지(분할 문단의 남은 줄 + 뒤 항목 전부)를 이월로 돌린다.
    private static func appendHead(
        _ head: (entries: [StackEntry], height: CGFloat), of notes: MeasuredNotes,
        to plan: inout StackPlan, split: (index: Int, lineCount: Int)
    ) {
        plan.entries += head.entries
        plan.stackedHeight += head.height
        let splitNote = notes[split.index]
        var overflow: [Input] = []
        let carried = splitNote.input
        // 나눈 문단의 이월 입력을 머리에 붙이므로 여기만 남은 입력을 배열로 뜬다 — 문단 하나의
        // 이어짐이라 뒤에 남은 각주 수와 무관하게 쪽마다 한 번이다.
        overflow.append(Input(
            paragraph: carried.paragraph,
            number: carried.number,
            sizeResolver: carried.sizeResolver,
            numbering: carried.numbering,
            placedLineCount: carried.placedLineCount + split.lineCount,
            // 다음 쪽 조각은 이 쪽이 **실제로 그린** 글자 다음부터다 (#165 리뷰) — 폭이
            // 달라지는 구역으로 넘어가도 경계가 흔들리지 않는다.
            placedLength: split.lineCount > 0
                ? splitNote.measurement.consumedLength(placing: 0 ..< split.lineCount)
                : carried.placedLength,
            noteId: carried.noteId,
            // 처음 잰 각주 모양(기본 모양으로 잰 확정 상태 포함)을 그대로 나른다 (#165
            // 리뷰) — 다음 쪽의 라벨 길이가 다르면 `placedLength`가 가리키는 자리가 어긋난다.
            measuredShape: carried.measuredShape,
            // 문단 전체의 조판도 나른다 (#165 리뷰) — 다음 쪽이 같은 폭이면 다시 조판하지
            // 않는다. 쪽마다 문단 전체를 CT로 다시 조판하면 쪽 수 × 줄 수의 일이다.
            sourceLayout: splitNote.measurement.carriedSourceLayout()
        ))
        overflow += notes.inputs(from: split.index + 1)
        plan.overflow = overflow[...]
    }
}

extension HwpFootnoteLayout.NoteMeasurement {
    /// 남은 줄 기준 `range`를 이 쪽에 그리면 소비되는 조판 문자열 길이 (#165 리뷰) —
    /// 다음 쪽 조각의 시작 문자 위치다. 방출(`footnoteBlock`)과 **같은 조각 계산**을
    /// 쓰므로 실제로 그려진 경계와 어긋나지 않는다.
    func consumedLength(placing range: Range<Int>) -> Int {
        guard let cacheLines else { return placedLength }
        return NSMaxRange(HwpFootnoteLayout.fragment(
            of: sourceAttributed,
            lines: sourceLines,
            cacheLineCount: cacheLines.count,
            cacheRange: absoluteLineRange(range),
            startingAt: placedLength
        ).sourceRange)
    }
}

// MARK: - 블록 방출

extension HwpFootnoteLayout {
    /// 본문 아래 자리에 맞춰 싣는 절대 캐시 모드 배치 (#165) — 계획(`stackPlan`)을 바닥
    /// 정렬로 쌓는다. 각주 영역 상단은 본문 상단 아래로 못 내려온다 (#95 클램프 유지).
    func placeBelowBody(
        notes: MeasuredNotes,
        bodyBottom: CGFloat?,
        onPage geometry: HwpPageGeometry,
        divider: DividerMetrics
    ) -> PendingPlacement {
        let contentFrame = geometry.contentFrame
        let overhead = divider.marginTop + divider.marginBottom
        // 영역 상단의 하한은 구분선 획까지 담은 자리다 (#165 리뷰) — 아래 클램프와 **같은**
        // 값을 자리에도 써야, 자리에 꼭 맞게 들어간 스택이 클램프에 밀려 본문 하단 밖으로
        // 나가지 않는다 (획 반 두께 − 위 여백 만큼). 본문이 있으면 본문 하한이 그보다 아래다.
        let areaFloor = contentFrame.minY + Self.separatorOverhang(divider)
        let plan = Self.stackPlan(
            notes: notes,
            available: contentFrame.maxY - max(bodyBottom ?? areaFloor, areaFloor) - overhead,
            fullPage: contentFrame.maxY - areaFloor - overhead,
            betweenNotes: divider.betweenNotes,
            emptyPage: bodyBottom == nil
        )
        guard !plan.entries.isEmpty else {
            return PendingPlacement(blocks: [], overflow: plan.overflow)
        }
        // 클램프는 구분선의 **획**까지 본문 상단 아래에 둔다 (#165 리뷰): 선은 위 여백 끝에
        // 가운데 맞춰 그어지므로 (`separatorLine`) 위 여백이 획 반 두께보다 좁으면 그만큼
        // 영역 위로 나간다 — 빈 쪽에도 안 들어가 진행 보장으로 실린 거대 각주에서 그 몫이
        // 머리말·위 여백으로 새지 않게 그만큼 내려 잡는다. 자리(`areaFloor`)가 같은 하한을
        // 썼으므로 들어맞은 스택엔 무동작이다.
        let areaTop = max(areaFloor, contentFrame.maxY - (plan.stackedHeight + overhead))
        let separatorLine = Self.separatorLine(
            areaTop: areaTop, divider: divider, contentFrame: contentFrame
        )
        var blocks: [HwpFootnoteBlock] = []
        var cursorY = areaTop + overhead
        var previousNoteId: Int?
        for entry in plan.entries {
            if let previousNoteId, previousNoteId != entry.measured.input.noteId {
                cursorY += divider.betweenNotes
            }
            let block = Self.footnoteBlock(
                for: entry, at: cursorY, in: contentFrame,
                separatorLine: separatorLine, divider: divider
            )
            blocks.append(block)
            cursorY = block.frame.maxY
            previousNoteId = entry.measured.input.noteId
        }
        return PendingPlacement(blocks: blocks, overflow: plan.overflow)
    }

    /// 각주 블록 하나 — 통째 항목과 쪽 끝에서 나뉜 앞 몫이 같은 산식으로 프레임·문단
    /// rect·개체를 싣는다. 흐름 배치(`stackBlocks`)도 이것을 쓴다.
    ///
    /// 블록 프레임은 스택 높이(각주 끝은 마지막 줄 상자까지)이고 문단 rect는 텍스트
    /// 높이(마지막 줄 전진량까지) 그대로다 — CT가 rect 안에 줄을 놓으므로 줄 간격 몫을
    /// 잘라 내면 대체 폰트의 마지막 줄이 프레임 밖으로 떨어진다. 그 여분은 각주 사이
    /// 여백보다 작아 다음 블록의 rect와 겹치지 않는다.
    static func footnoteBlock(
        for entry: StackEntry,
        at y: CGFloat,
        in frame: CGRect,
        separatorLine: CGRect,
        divider: DividerMetrics
    ) -> HwpFootnoteBlock {
        let note = entry.measured
        let measurement = note.measurement
        let attributed: NSAttributedString
        let paragraphFrame: HwpParagraphFrame
        let textHeight: CGFloat
        let blockHeight: CGFloat
        if let range = entry.lineRange, let cacheLines = measurement.cacheLines {
            // 경계는 **문단 전체 기준 절대 캐시 줄 인덱스**로 잰다 (#165 리뷰) — 이미 잘린
            // 조각을 남은 줄 기준으로 다시 환산하면 다음 쪽의 `measureNote`가 원본 기준으로
            // 계산한 경계와 반올림에서 갈려 가운데 줄이 사라지거나 겹친다.
            let fragment = Self.fragment(
                of: measurement.sourceAttributed,
                lines: measurement.sourceLines,
                cacheLineCount: cacheLines.count,
                cacheRange: measurement.absoluteLineRange(range),
                startingAt: measurement.placedLength
            )
            attributed = fragment.attributed
            textHeight = measurement.headTextHeight(lines: range)
            paragraphFrame = HwpParagraphFrame(totalHeight: textHeight, lines: fragment.lines)
            blockHeight = measurement.headHeight(lines: range)
        } else {
            attributed = measurement.attributed
            paragraphFrame = measurement.frame
            textHeight = measurement.textRectHeight
            blockHeight = measurement.stackingHeight(isNoteEnd: entry.isNoteEnd)
        }
        return HwpFootnoteBlock(
            frame: CGRect(x: frame.minX, y: y, width: frame.width, height: blockHeight),
            paragraphs: [HwpLaidOutParagraph(
                attributedString: attributed,
                frame: paragraphFrame,
                // 문단 rect는 **문단 자신의** 텍스트 높이다 — 떠 있는 개체가 블록을
                // 키운 몫까지 문단이 흡수하면 문단-레벨 링크 폴백
                // (`HwpHitTester.spanAwareHyperlinkURL`)이 개체 아래 빈 영역까지
                // 자기 URL로 claim한다 (R39 #2). 컨테이너가 개체를 담는 높이는 블록
                // frame (blockHeight) 몫이다.
                rect: CGRect(x: 0, y: 0, width: frame.width, height: textHeight),
                paragraphId: note.input.paragraph.paraHeader.paraId,
                hyperlinkURL: note.input.paragraph.hyperlinkURL
            )],
            number: note.input.number,
            separatorLine: separatorLine,
            separatorColor: divider.color,
            // 개체는 measure가 문단-로컬 (0, 0) 기준으로 수집했고, 문단 rect도
            // 블록-로컬 (0, 0)이라 그대로 블록-로컬 좌표다 (#94).
            images: measurement.objects.images,
            shapes: measurement.objects.shapes,
            textboxes: measurement.objects.textboxes,
            nestedTables: measurement.objects.nestedTables
        )
    }
}
