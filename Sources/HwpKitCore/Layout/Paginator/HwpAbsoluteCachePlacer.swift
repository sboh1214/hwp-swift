import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 절대 라인 캐시 배치 — 저장본 라인 캐시 (paraLineSeg)의 run 분해·절대 y
/// 블록 높이·페이지 분할 텍스트 슬라이스·stale 판정 같은 순수 계산과 절대
/// 캐시 전용 상태 (모드·마지막 loc·stale 보정 오프셋)를 소유한다.
/// HwpPaginator에서 추출 (동작 불변). 페이지 확정·블록 방출·커서
/// (contentHeightUsed) 이동 같은 부수효과는 paginator 루프가 담당한다.
struct HwpAbsoluteCachePlacer {
    /// 절대 캐시 모드: lineLocation이 페이지 내 절대 y인 저장본 (한/글 2007 계열).
    /// 켜지면 문단을 캐시가 준 y에 그대로 배치하고, loc 리셋을 한글의 페이지
    /// 절단점으로 사용한다 — 페이지 수/배치가 한글과 일치한다.
    let absoluteCacheMode: Bool
    /// 현재 페이지에 배치한 마지막 세그먼트의 lineLocation (절대 캐시 모드 전용)
    var lastAbsoluteCacheLoc = Int32.min
    /// 절대 캐시 모드에서 stale 캐시 문단 (캐시 줄 높이 < 선언 글자 크기)이
    /// 만든 아래 방향 보정 오프셋 (페이지 로컬). 한글.app도 이런 문단은 열 때
    /// 재조판해 CT 자연 높이만큼 다음 문단을 밀어낸다 (CharShape 실측).
    var absoluteCacheStaleOffset: CGFloat = 0

    init(sections: [CoreHwp.HwpSection]) {
        absoluteCacheMode = Self.detectAbsoluteCacheMode(sections: sections)
    }

    // MARK: 모드 감지 · run 분해

    /// 절대 캐시 모드 감지: 유효한 라인 캐시의 첫 lineLocation이 0보다 큰 문단이
    /// 다수면 (한/글 2007 계열 저장본) 절대 y 좌표계로 판단한다.
    static func detectAbsoluteCacheMode(sections: [CoreHwp.HwpSection]) -> Bool {
        var absolute = 0
        var zero = 0
        for section in sections {
            for paragraph in section.paragraph {
                guard let first = paragraph.paraLineSeg.paraLineSegInternalArray.first
                else { continue }
                if first.lineLocation > 0 {
                    absolute += 1
                } else {
                    zero += 1
                }
            }
        }
        return absolute > zero
    }

    /// 세그먼트를 단조 (비감소) run으로 나눈다. lineLocation이 줄어드는 지점이
    /// 한글의 페이지 절단점이다. 캐시가 없거나 음수 높이가 있으면 nil (CT 폴백).
    static func cacheRuns(
        for paragraph: CoreHwp.HwpParagraph
    ) -> [[CoreHwp.HwpParaLineSegInternal]]? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !segments.isEmpty else { return nil }
        var runs: [[CoreHwp.HwpParaLineSegInternal]] = []
        var current: [CoreHwp.HwpParaLineSegInternal] = []
        var previous = Int32.min
        for segment in segments {
            guard segment.lineHeight >= 0 else { return nil }
            if segment.lineLocation < previous, !current.isEmpty {
                runs.append(current)
                current = []
            }
            current.append(segment)
            previous = segment.lineLocation
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    /// 라인 캐시의 실제 줄 전진량 (HWPUNIT): lineHeight + lineSpacing.
    /// 줄 간격 종류/비율이 이미 반영된 per-line 값이라 저장 세대와 무관하다.
    /// 절대·다단 캐시 배치와 문단 높이 (height(for:)) 공용.
    static func lineAdvance(of segment: CoreHwp.HwpParaLineSegInternal) -> Int {
        // 미신뢰 캐시의 큰 Int32 두 필드를 그대로 더하면 트랩하므로 Int로 넓힌다
        // (Int는 64-bit라 Int32 두 개 합은 절대 넘치지 않는다).
        Int(max(0, segment.lineHeight)) + Int(max(0, segment.lineSpacing))
    }

    /// 라인 하단의 절대 위치 (lineLocation + 전진량)를 Int로 넓혀 계산한다 —
    /// Int32 덧셈 트랩 방지 (미신뢰 라인 캐시). 정상 캐시는 값 불변.
    static func lineBottom(of segment: CoreHwp.HwpParaLineSegInternal) -> Int {
        Int(segment.lineLocation) + lineAdvance(of: segment)
    }

    // MARK: run별 컨트롤 서수 (조각 단위 각주 귀속)

    /// 조각(run)마다 그 조각에 **실제로 그려진** top-level 컨트롤 서수 범위.
    ///
    /// 각주는 참조가 놓인 **조각의 페이지**에 실려야 한다 (한글.app 실측 —
    /// 헌법주석 인쇄 709·710·711쪽이 같은 문단의 각주를 나눠 싣는다).
    ///
    /// 경계의 근거는 `runAttributedSlice`가 낸 **그 조각의 텍스트**다 — 마커 run에
    /// 붙은 `controlIndex`를 그대로 읽는다. 원본 WCHAR 위치 (`textStartingIndex`)
    /// 로 나누면 배치는 CT 라인 비례로 자르는데 귀속만 캐시 좌표로 잘라, 폰트
    /// 대체·stale 캐시로 두 분할이 갈릴 때 각주가 참조와 **다른 페이지**에 실린다
    /// (참조보다 앞 페이지면 그 쪽엔 참조 없는 각주가 뜬다). 자르는 곳이 하나면
    /// 그 불일치가 원천적으로 없다.
    ///
    /// 반환값은 `[0, ctrlCount)`를 조각 순서로 빈틈없이 분할한다 — 어느 조각에도
    /// 안 그려진 컨트롤 (마커 없는 컨트롤·CT가 잘라낸 라인)은 뒤 조각이 흡수하고
    /// 마지막 조각이 나머지를 전부 가져가므로 누락이 없다.
    static func controlOrdinalRanges(
        slices: [NSAttributedString],
        controlCount: Int
    ) -> [Range<Int>]? {
        guard slices.count > 1, controlCount > 0 else { return nil }
        let lastOrdinals = slices.map(lastControlOrdinal(in:))
        // 서수 ↔ 컨트롤 배열이 어긋난 문단 (파스 폴백 등)은 나누지 않는다.
        guard lastOrdinals.compactMap({ $0 }).allSatisfy({ $0 < controlCount }) else {
            return nil
        }

        var ranges: [Range<Int>] = []
        var cursor = 0
        for index in slices.indices {
            // 마지막 조각은 나머지 전부, 그 앞은 자기가 그린 마지막 서수까지.
            let end = index == slices.count - 1
                ? controlCount
                : lastOrdinals[index].map { $0 + 1 } ?? cursor
            ranges.append(cursor ..< max(cursor, end))
            cursor = max(cursor, end)
        }
        return ranges
    }

    /// 조각에 그려진 마지막 컨트롤 서수 — 마커가 없으면 nil.
    /// 번호로 치환된 참조 run도 같은 속성을 달고 있다 (`appendControlMarker`).
    private static func lastControlOrdinal(in slice: NSAttributedString) -> Int? {
        var last: Int?
        slice.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: slice.length)
        ) { value, _, _ in
            guard let ordinal = (value as? NSNumber)?.intValue else { return }
            last = max(last ?? ordinal, ordinal)
        }
        return last
    }

    // MARK: CT 측정 생략 게이트

    /// 절대 캐시 모드에서 CT 측정을 통째로 생략할 수 있는 문단인지 —
    /// 배치가 CT 산출물 (lines/totalHeight)을 전혀 소비하지 않는 경우만:
    /// 1) 단일 run (다중 run의 페이지 분할 텍스트 배분은 lines 필요),
    /// 2) 컨트롤 마커 없음 (인라인 앵커 좌표가 lines의 inlineAnchors 필요),
    /// 3) 신선한 캐시 (stale 보정이 totalHeight 필요 — 판정 자체는 CT 불요).
    /// 다단 재배치의 bandTextBlocks lines 소비는 columnCount > 1 전용이라
    /// 게이트 (≤ 1)로 배제된다. 의심스러우면 CT 폴백 — 절단 결과 불변.
    func canSkipMeasurement(
        for paragraph: CoreHwp.HwpParagraph,
        attributedString: NSAttributedString,
        columnCount: Int
    ) -> Bool {
        guard absoluteCacheMode, columnCount <= 1,
              let runs = Self.cacheRuns(for: paragraph),
              runs.count == 1
        else { return false }
        guard !Self.hasControlIndexMarker(attributedString) else { return false }
        return !Self.cacheIsStale(run: runs[0], attributedString: attributedString)
    }

    /// U+FFFC 개체 앵커 (hwp.controlIndex) 존재 여부 — O(속성 run 수)
    private static func hasControlIndexMarker(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: stale 판정 · 블록 높이

    /// 캐시가 stale한지 — 캐시 줄 높이 (h)보다 큰 글자 크기가 선언되어 있으면
    /// 캐시가 현재 내용과 안 맞는 저장본이다 (신선한 캐시는 h ≥ 글자 크기).
    /// 폰트 대체와 무관하다: CT 폰트 포인트 크기는 요청 크기를 유지한다.
    static func cacheIsStale(
        run: [CoreHwp.HwpParaLineSegInternal],
        attributedString: NSAttributedString
    ) -> Bool {
        let maxCacheHeight = run.map { max(0, $0.lineHeight) }.max() ?? 0
        let cacheHeightPoints = HwpUnits.points(fromHwpUnit: maxCacheHeight)
        guard cacheHeightPoints > 0, attributedString.length > 0 else { return false }
        var maxFontSize: CGFloat = 0
        attributedString.enumerateAttribute(
            kCTFontAttributeName as NSAttributedString.Key,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let value, CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return }
            let font = value as! CTFont // swiftlint:disable:this force_cast
            maxFontSize = max(maxFontSize, CTFontGetSize(font))
        }
        return maxFontSize > cacheHeightPoints + 0.5
    }

    /// 절대 캐시 run의 블록 높이. 기본은 줄 전진량 (h + sp) 합이지만, 한글은
    /// 마지막 줄의 '줄 간격' 몫이 본문 하단 경계를 넘는 것을 허용한다 (noori
    /// p8 실측: ink는 경계 안, advance는 7pt 초과). 블록 프레임이 꼬리말
    /// 밴드와 겹치지 않게 간격 몫만 하단에서 자른다 (ink가 이미 경계를 넘으면
    /// 그대로 둔다 — 실제 넘침). columnTop은 현재 단 상단 (currentColumnFrame
    /// .minY), contentBottom은 본문 하단 경계 (contentFrame.maxY).
    static func absoluteRunBlockHeight(
        run: [CoreHwp.HwpParaLineSegInternal],
        firstLocation: Int32,
        columnTop: CGFloat,
        contentBottom: CGFloat
    ) -> CGFloat {
        var runBottom = Int(firstLocation)
        var runInkBottom = Int(firstLocation)
        for segment in run {
            runBottom = max(runBottom, Self.lineBottom(of: segment))
            runInkBottom = max(
                runInkBottom,
                Int(segment.lineLocation) + Int(max(0, segment.lineHeight))
            )
        }
        var height = max(
            1, HwpUnits.points(fromHwpUnit: Int32(clamping: runBottom - Int(firstLocation)))
        )
        let blockTop = columnTop
            + max(0, HwpUnits.points(fromHwpUnit: firstLocation))
        if blockTop + height > contentBottom {
            let inkHeight = max(
                1,
                HwpUnits.points(fromHwpUnit: Int32(clamping: runInkBottom - Int(firstLocation)))
            )
            height = max(inkHeight, contentBottom - blockTop)
        }
        return height
    }

    // MARK: 페이지 분할 텍스트 슬라이스

    /// run의 라인 배분 비율 (여러 페이지에 걸친 문단의 텍스트 분할용)
    struct RunShare {
        let segments: Int
        let total: Int
        let runCount: Int
    }

    /// 여러 run으로 나뉜 (여러 페이지에 걸친) 문단의 run별 텍스트 조각.
    /// CT 라인을 세그먼트 수에 비례해 배분한다 (같은 폭이라 대개 1:1).
    static func runAttributedSlice(
        runIndex: Int,
        runShare: RunShare,
        attributedString: NSAttributedString,
        lines: [HwpLineFrame],
        lineCursor: inout Int
    ) -> (text: NSAttributedString, lines: [HwpLineFrame]) {
        guard runShare.runCount > 1 else { return (attributedString, lines) }
        let take = runIndex == runShare.runCount - 1
            ? max(0, lines.count - lineCursor)
            : Int((
                Double(runShare.segments) / Double(runShare.total) * Double(lines.count)
            ).rounded())
        let start = min(lineCursor, lines.count)
        let end = min(start + max(0, take), lines.count)
        lineCursor = end
        let slice = lines[start ..< end]
        guard let first = slice.first else {
            return (NSAttributedString(string: ""), [])
        }
        let range = slice.dropFirst().reduce(first.attributedRange) {
            NSUnionRange($0, $1.attributedRange)
        }
        return (attributedString.attributedSubstring(from: range), [])
    }

    // MARK: 다단 캐시 단 경계

    /// run 경계의 textStartingIndex (원본 WCHAR 스트림 위치)를 attributed
    /// 인덱스로 비례 환산한 뒤 CT 라인 시작에 스냅한 단 경계 목록
    /// ([0, …, attributedLength]) — 컨트롤 문자 (스트림 8 WCHAR ↔ 마커 1자)의
    /// 오차는 라인 스냅이 흡수한다. 스냅 후 비단조면 nil (CT 폴백).
    static func columnRunBoundaries(
        runs: [[CoreHwp.HwpParaLineSegInternal]],
        rawTotal: UInt32,
        attributedLength: Int,
        lines: [HwpLineFrame]
    ) -> [Int]? {
        var boundaries = [0]
        for run in runs.dropFirst() {
            guard let first = run.first else { return nil }
            let proportional = Double(first.textStartingIndex) / Double(rawTotal)
                * Double(attributedLength)
            boundaries.append(snapToLineStart(
                Int(proportional.rounded()),
                lines: lines
            ))
        }
        boundaries.append(attributedLength)
        guard boundaries == boundaries.sorted() else { return nil }
        return boundaries
    }

    /// 인덱스를 가장 가까운 CT 라인 시작 위치로 스냅한다.
    private static func snapToLineStart(_ index: Int, lines: [HwpLineFrame]) -> Int {
        guard !lines.isEmpty else { return index }
        var best = index
        var bestDistance = Int.max
        for line in lines {
            let start = line.attributedRange.location
            let distance = abs(start - index)
            if distance < bestDistance {
                bestDistance = distance
                best = start
            }
        }
        return best
    }
}
