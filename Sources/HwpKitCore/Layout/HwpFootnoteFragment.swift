import CoreGraphics
import CoreHwp
import Foundation

// 각주 이어짐(#165)의 **조각** 산식 — 이월 입력이 나르는 원본 조판(`SourceLayout`)과 캐시 줄
// 범위에 해당하는 조각 문자열·줄 프레임(`fragment`). 스택 계획·블록 방출은
// `HwpFootnoteContinuation.swift` (그 파일이 SwiftLint file_length 상한 700줄에 닿았다).

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
    ///
    /// **줄 단위 대응이 조각을 비우거나 뒤 몫의 글까지 삼키면 그 경계만 글자 위치로 보간한다**
    /// (#165 리뷰): CT 줄이 캐시 줄보다 적으면 짧은 쪽 몫의 양 끝이 같은 CT 줄로 환산돼 빈
    /// 조각이 되고 — 앞 조각은 구분선과 빈 자리만 그리며 글은 뒤 쪽으로 밀린다 — 앞 조각의 끝이
    /// 마지막 CT 줄로 올림되면 한글이 다음 쪽에 이어 놓은 줄이 사라진다 (헌법주석 인쇄 442쪽
    /// 등 2곳). 그때만 캐시 경계 i를 CT 줄 `floor(i·m/N)` 안의 글자 위치(줄 길이 × 소수 몫)로
    /// 잡는다. 줄 단위 대응이 서는 경계는 종전 그대로다 (코퍼스 좌표·조각 글 불변).
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
        /// 캐시 경계 i의 글자 위치 — CT 줄 `floor(i·m/N)` 안에서 소수 몫만큼.
        func charOffset(_ cacheIndex: Int) -> Int {
            guard cacheIndex < cacheLineCount else { return attributed.length }
            let exact = Double(cacheIndex) * Double(lines.count) / Double(cacheLineCount)
            let line = lines[min(lines.count - 1, Int(exact))]
            let fraction = exact - Double(Int(exact))
            return line.attributedRange.location
                + Int((Double(line.attributedRange.length) * fraction).rounded())
        }
        let isContinuation = cacheRange.lowerBound > 0
        // 이어지는 조각은 경계 문자를 **담은** 줄부터 시작한다 (폭이 그대로면 그 줄이 곧
        // 비례 환산 결과다). 그 줄이 경계보다 앞에서 시작하면 앞부분은 이미 그려졌으므로
        // 문자 범위에서 잘라 낸다.
        let start = isContinuation && placedLength > 0
            ? firstLineIndex(in: lines, endingAfter: placedLength)
            : ctIndex(cacheRange.lowerBound)
        guard start < lines.count else { return empty }
        let end = max(ctIndex(cacheRange.lowerBound), ctIndex(cacheRange.upperBound))
        let startChar = isContinuation && placedLength > 0
            ? max(lines[start].attributedRange.location, min(placedLength, attributed.length))
            : lines[start].attributedRange.location
        let range: NSRange
        let slice: ArraySlice<HwpLineFrame>
        // 줄 단위 대응이 서는 경계: 조각이 비지 않고, 뒤에 캐시 줄이 남는데 마지막 CT 줄까지
        // 삼키지도 않는다.
        if start < end, cacheRange.upperBound >= cacheLineCount || end < lines.count {
            slice = lines[start ..< end]
            let lineRange = slice.dropFirst().reduce(slice[start].attributedRange) {
                NSUnionRange($0, $1.attributedRange)
            }
            range = NSRange(location: startChar, length: NSMaxRange(lineRange) - startChar)
        } else {
            // 끝 경계를 글자 위치로 — 최소 한 글자는 싣고 문단 끝을 넘지 않는다.
            let endChar = cacheRange.upperBound >= cacheLineCount
                ? attributed.length
                : min(attributed.length, max(charOffset(cacheRange.upperBound), startChar + 1))
            guard endChar > startChar else { return empty }
            range = NSRange(location: startChar, length: endChar - startChar)
            let lastLine = min(lines.count - 1, firstLineIndex(in: lines, endingAfter: endChar - 1))
            slice = lines[start ... max(start, lastLine)]
        }
        // 남은 글자가 없으면 빈 조각이다 — 캐시 줄이 남았어도 실을 글이 없다.
        guard range.length > 0 else { return empty }
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
            lines: fragmentLines(slice, range: range),
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

    /// 조각 줄 프레임 — 줄이 조각 범위 밖으로 삐져나오면 (폭이 바뀐 이월의 첫 줄, 글자 위치로
    /// 보간한 경계의 양 끝 줄) 그 몫을 잘라 문자 범위를 조각 기준으로 맞춘다. 잘린 줄의
    /// 기하와 앵커는 **원본 폭 기준**이라 근사다 — 개체를 담은 각주는 나누지 않으므로
    /// (`carriesObjects`) 앵커는 버린다.
    private static func fragmentLines(
        _ slice: ArraySlice<HwpLineFrame>, range: NSRange
    ) -> [HwpLineFrame] {
        guard let first = slice.first else { return [] }
        return slice.map { line in
            // 조각 기준 문자 범위 — `HwpParagraphLayout.fragmentLineFrames`와 같은 원점 이동에
            // 양 끝 절단을 더한 것.
            let relativeStart = line.attributedRange.location - range.location
            let relativeEnd = NSMaxRange(line.attributedRange) - range.location
            let clipped = relativeStart < 0 || relativeEnd > range.length
            let location = max(0, relativeStart)
            let end = min(range.length, relativeEnd)
            return HwpLineFrame(
                origin: CGPoint(x: line.origin.x, y: line.origin.y - first.origin.y),
                width: line.width,
                baseline: line.baseline,
                attributedRange: NSRange(location: location, length: max(0, end - location)),
                inlineAnchors: clipped ? [] : line.inlineAnchors
            )
        }
    }
}
