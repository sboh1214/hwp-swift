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
    /// 그 세그먼트의 전진량 (HWPUNIT, `signedAdvance`) — 같은 위치에서 시작하는 다음 문단이
    /// 새 쪽인지 가른다 (`isPageBreak`, #214).
    var lastAbsoluteCacheAdvance = 0
    /// 이 쪽에서 단 밴드가 쪽 중간에 새로 열렸는가 (#214 리뷰) — 쪽이 넘어갈 때까지 유지한다. 한글은
    /// 밴드마다 줄 위치를 밴드 상단부터 다시 세므로(`Column` 쌍: 밴드 첫 문단이 모두 0) 밴드가 열리면
    /// 위 두 기록을 지우고, 그 밴드의 캐시 문단은 위치에 더해 **자리**로도 쪽 넘김을 판정한다 — 첫
    /// run의 줄 상자가 남은 본문에 안 들어가면 한글은 그 문단을 다음 쪽에 놓았다.
    var bandRestartedMidPage = false
    /// 절대 캐시 모드에서 낡은 캐시 문단(캐시 줄 높이 < 선언 글자 크기, 또는 글자처럼 취급 표를 실은
    /// 줄 < 그 표 — #214 PR 리뷰)이 만든 보정 오프셋 (페이지 로컬). 한글.app도 이런 문단은 열 때
    /// 재조판해 CT 줄 범위만큼 다음 문단을 밀어낸다 (CharShape 실측·#214 PR 리뷰 실측). 밀려 쪽을
    /// 넘긴 문단을 새 쪽 머리에 놓을 때는 그 문단의 캐시 위치만큼 **음수**가 된다 (`pendingRebaseLocation`).
    var absoluteCacheStaleOffset: CGFloat = 0
    /// 낡은 캐시 보정으로 밀려 쪽을 넘긴 문단의 첫 줄 위치 (#214 PR 리뷰) — 다음 쪽에서 그 문단을 다시
    /// 처리할 때 보정 오프셋을 이 위치만큼 당겨 쪽 머리에 놓는다. 캐시 위치는 옛 쪽 기준이기 때문이다.
    var pendingRebaseLocation: Int32?

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

    /// 세그먼트를 run으로 나눈다 — 한글의 쪽 절단점(`isPageBreak`: lineLocation이 줄어들거나,
    /// 자리를 차지한 줄 뒤에 같은 위치에서 **새 줄**이 시작하는 지점)마다 가른다. 캐시가 없거나
    /// 음수 높이가 있으면 nil (CT 폴백).
    static func cacheRuns(
        for paragraph: CoreHwp.HwpParagraph
    ) -> [[CoreHwp.HwpParaLineSegInternal]]? {
        let segments = paragraph.paraLineSeg.paraLineSegInternalArray
        guard !segments.isEmpty else { return nil }
        var runs: [[CoreHwp.HwpParaLineSegInternal]] = []
        var current: [CoreHwp.HwpParaLineSegInternal] = []
        var previous = Int32.min
        var previousAdvance = 0
        for segment in segments {
            guard segment.lineHeight >= 0 else { return nil }
            if isPageBreak(
                at: segment.lineLocation, after: previous, previousAdvance: previousAdvance,
                startsLine: Self.startsLine(segment)
            ), !current.isEmpty {
                runs.append(current)
                current = []
            }
            current.append(segment)
            previous = segment.lineLocation
            previousAdvance = signedAdvance(of: segment)
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

    /// **캐시가 주장하는** 조각별 컨트롤 서수 범위 (#165) — run 첫 세그먼트의
    /// `textStartingIndex`(원본 WCHAR 위치)와 컨트롤 문자의 WCHAR 위치(글자 1·컨트롤 8)로
    /// 나눈다. 한글이 저장한 절단점이라 폰트 대체와 무관하게 한글의 귀속 그대로다.
    /// 서수 ↔ 컨트롤 배열이 어긋난 문단(extended 문자 수 ≠ 컨트롤 수)은 나누지 않는다.
    static func cachedControlOrdinalRanges(
        runs: [[CoreHwp.HwpParaLineSegInternal]],
        paragraph: CoreHwp.HwpParagraph,
        controlCount: Int
    ) -> [Range<Int>]? {
        guard runs.count > 1, controlCount > 0, let chars = paragraph.paraText?.charArray else {
            return nil
        }
        var offsets: [Int] = []
        var offset = 0
        for char in chars {
            if char.type == .extended {
                offsets.append(offset)
            }
            offset += char.type == .char ? 1 : 8
        }
        guard offsets.count == controlCount else { return nil }
        var ranges: [Range<Int>] = []
        var cursor = 0
        for runIndex in runs.indices {
            let end: Int
            if runIndex == runs.count - 1 {
                end = controlCount
            } else {
                guard let nextStart = runs[runIndex + 1].first.map({ Int($0.textStartingIndex) })
                else { return nil }
                // 탐색은 **이전 커서부터** 이어간다 (리뷰 지적): `offsets`는 증가 수열이라
                // 술어가 단조라 결과 집합이 접미사고, 아래 `max(cursor, end)`가 커서
                // 앞의 답을 어차피 접으므로 전수 탐색과 값이 같다. 처음부터 훑으면
                // O(run 수 × 컨트롤 수)라 조작 문서(각 10,000)가 첫 쪽 생성 전에 멈춘다.
                end = offsets[cursor...].firstIndex { $0 >= nextStart } ?? controlCount
            }
            ranges.append(cursor ..< max(cursor, end))
            cursor = max(cursor, end)
        }
        return ranges
    }

    /// 그려진 조각(`controlOrdinalRanges`)과 캐시(`cachedControlOrdinalRanges`) 가운데
    /// **앞쪽** 귀속 (#165). 각주는 참조가 놓인 쪽에 실리되, 폰트 대체로 CT 줄바꿈이
    /// 한글보다 늦어 마커가 다음 조각으로 밀린 문단은 캐시(한글의 절단점)를 따른다 —
    /// 늦게 귀속된 각주는 한글이 이미 다른 각주로 채운 다음 쪽을 넘치게 하고, 넘침이
    /// 이어짐으로 뒤 쪽에 연쇄해 한글에 없는 쪽을 만든다 (헌법주석 실측: 21건이 8쪽을
    /// 늘렸다). 반대 방향(캐시가 더 늦음)은 그려진 조각을 따른다 — 그 쪽엔 참조가 있다.
    /// 한쪽만 있으면 그것을, 둘 다 없으면 nil (문단 단위 귀속 폴백).
    static func earliestOrdinalRanges(
        _ drawn: [Range<Int>]?, _ cached: [Range<Int>]?
    ) -> [Range<Int>]? {
        guard let drawn, let cached, drawn.count == cached.count else { return drawn ?? cached }
        var ranges: [Range<Int>] = []
        var cursor = 0
        for index in drawn.indices {
            // 범위 끝은 "이 조각까지 귀속된 컨트롤 수"다 — 앞쪽 귀속은 그 수가 큰 쪽이다.
            let end = index == drawn.count - 1
                ? drawn[index].upperBound
                : max(drawn[index].upperBound, cached[index].upperBound)
            ranges.append(cursor ..< max(cursor, end))
            cursor = max(cursor, end)
        }
        return ranges
    }

    /// **두 조각 이상에 걸쳐 그려진** 마커 서수 (#95 리뷰).
    ///
    /// CT가 번호 문자열 중간에서 줄을 나누면 (좁은 단·긴 번호) 각 조각이 마커의
    /// **일부**만 갖는다. 조각별 번호 재기록이 그 일부를 완전한 번호로 바꾸면 다음
    /// 쪽에 남은 나머지와 합쳐 `10)` + `)`가 된다. 번호가 그대로여도 그렇다 —
    /// 부분 문자열은 완전한 번호와 다르므로 "안 바뀌면 그대로 둔다" 가드를
    /// 통과한다. 그래서 갈린 서수는 재기록에서 아예 뺀다 (최악이라도 번호가
    /// 옛값일 뿐 문자열이 깨지지 않는다).
    static func ordinalsSpanningSlices(_ slices: [NSAttributedString]) -> Set<Int> {
        var seen: Set<Int> = []
        var spanning: Set<Int> = []
        for slice in slices {
            var inSlice: Set<Int> = []
            slice.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: slice.length)
            ) { value, _, _ in
                guard let ordinal = (value as? NSNumber)?.intValue else { return }
                inSlice.insert(ordinal)
            }
            spanning.formUnion(inSlice.intersection(seen))
            seen.formUnion(inSlice)
        }
        return spanning
    }

    /// 조각에 그려진 마지막 컨트롤 서수 — 마커가 없으면 nil.
    /// 번호로 치환된 참조 run도 같은 속성을 달고 있다 (`appendControlMarker`). 흐름 분할 조각의
    /// 쪽 장식 등록(`HwpPaginator.registerPageChromeForCurrentFragment`)도 같은 서수를 본다.
    static func lastControlOrdinal(in slice: NSAttributedString) -> Int? {
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
    /// 줄 공간을 예약한 개체 마커의 글자 모양은 보지 않는다 — 한글은 그 크기를 줄 상자에 넣지
    /// 않아 신선한 캐시의 h가 그보다 작다 (#217: 10pt 글 + 40pt 마커의 8pt 그림 줄 `vertsize` 1000).
    static func cacheIsStale(
        run: [CoreHwp.HwpParaLineSegInternal],
        attributedString: NSAttributedString
    ) -> Bool {
        let maxCacheHeight = run.map { max(0, $0.lineHeight) }.max() ?? 0
        let cacheHeightPoints = HwpUnits.points(fromHwpUnit: maxCacheHeight)
        // 빈 문단 앵커(#145)는 stale 판정에서 뺀다 — 종전(길이 0)과 같은 배치를
        // 유지하기 위해서다. 앵커 글꼴 크기 대 캐시 높이는 실물 높이 근거가 아니다.
        guard cacheHeightPoints > 0, attributedString.length > 0,
              !HwpTextRunBuilder.isEmptyParagraphAnchor(attributedString)
        else { return false }
        var maxFontSize: CGFloat = 0
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length)
        ) { attributes, _, _ in
            maxFontSize = max(maxFontSize, Self.staleCheckFontSize(attributes))
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
    ///
    /// 조각의 줄 프레임도 함께 돌려준다 — 조각 문자열·조각 첫 줄 기준으로 되돌린
    /// 것(`HwpParagraphLayout.fragmentLineFrames`)이라 조각 블록의 줄 앵커 문맥이
    /// 된다 (#164). 종전엔 여러 run이면 빈 배열을 돌려 앞 조각의 글자처럼 취급
    /// 표가 앵커를 잃고 흐름 위치로 갔다.
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
        // 둘째 run부터는 이어지는 조각 — 첫 줄 들여쓰기를 둘째 줄에 맞춘다. 뒤에 줄이 남는
        // 조각(마지막 run 앞)은 이어짐 표식을 단다 (PR 리뷰: 다른 분할 경로와 같은 마커).
        let text = HwpParagraphLayout.continuationFragment(of: attributedString, range: range)
        return (
            end < lines.count ? HwpTableSplitter.markedAsContinuedFragment(text) : text,
            HwpParagraphLayout.fragmentLineFrames(slice, range: range)
        )
    }

    // MARK: 다단 캐시 단 경계

    /// run 경계의 textStartingIndex (원본 WCHAR 스트림 위치)를 attributed
    /// 인덱스로 비례 환산한 뒤 CT 라인 시작에 스냅한 단 경계 목록
    /// ([0, …, attributedLength]) — 컨트롤 문자 (스트림 8 WCHAR ↔ 마커 1자)의
    /// 오차는 라인 스냅이 흡수한다. 스냅 후 비단조면 nil (CT 폴백).
    ///
    /// `prefixLength`는 조판 문자열 앞에 전치된 생성 문자열(문단 번호·개요 번호
    /// 라벨 + 거리 빈칸, #154)의 길이다 — 원본 WCHAR 스트림에 대응 위치가 없으므로
    /// 비례 환산은 그 뒤의 본문 길이에만 걸고 결과에 접두 길이를 더한다. 전체 길이로
    /// 환산하면 경계가 `접두 길이 × (1 − 스트림 비율)`만큼 앞으로 당겨져 라인 스냅이
    /// 이웃 줄로 튈 수 있다.
    static func columnRunBoundaries(
        runs: [[CoreHwp.HwpParaLineSegInternal]],
        rawTotal: UInt32,
        attributedLength: Int,
        lines: [HwpLineFrame],
        prefixLength: Int = 0
    ) -> [Int]? {
        let prefix = max(0, min(prefixLength, attributedLength))
        var boundaries = [0]
        for run in runs.dropFirst() {
            guard let first = run.first else { return nil }
            let proportional = Double(prefix)
                + Double(first.textStartingIndex) / Double(rawTotal)
                * Double(attributedLength - prefix)
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

// MARK: - 쪽 절단점 (#214)

extension HwpAbsoluteCachePlacer {
    /// 줄 캐시에서 `location`에서 시작하는 세그먼트가 `previous` 세그먼트 뒤의 한글 쪽
    /// 절단점인가 — 위치가 줄거나, 앞 세그먼트가 자리를 차지했는데(전진량 > 0) **같은** 위치에서
    /// **새 줄**(`startsLine`)이 시작하면 새 쪽이다 (#214). 줄 위치만 보면 쪽 머리(0)에서 시작한
    /// 줄 뒤에 또 쪽 머리에서 시작하는 줄 — 쪽을 채우는 글자처럼 취급 표·그림을 품은 문단이 잇단
    /// 문서 — 을 같은 쪽에 겹쳐 놓는다 (`inline-table-actual-height`의 32행 표 셋이 한 쪽에
    /// 쌓였다). 같은 위치의 세그먼트가 한 쪽에 오는 경우는 둘이다: 앞 세그먼트의 전진량이 0
    /// 이하이거나, 한 줄이 여러 세그먼트로 나뉜 경우(어울림 개체 양옆으로 흐르는 줄 — 이어지는
    /// 세그먼트는 표 62 bit 17 '줄의 첫 세그먼트'가 꺼져 있다, `HwpFootnoteCacheLines.lines`와 같은
    /// 규칙). 문단의 첫 세그먼트는 늘 줄을 시작한다. 쪽 중간에 새로 열린 단 밴드의 첫 문단은 loc을
    /// 밴드 상단부터 다시 세므로 이 판정을 쓰지 않는다 (`bandRestartedMidPage`). 절대 캐시 모드
    /// 문서의 문단 사이·문단 안 전이 전수(헌법주석 캐시 문단 11,056개 포함)에서 새 규칙이 판정을
    /// 바꾸는 곳은 그 픽스처의 두 곳뿐이다.
    static func isPageBreak(
        at location: Int32,
        after previous: Int32,
        previousAdvance: Int,
        startsLine: Bool = true
    ) -> Bool {
        location < previous || (location == previous && previousAdvance > 0 && startsLine)
    }

    /// 세그먼트가 줄을 시작하는가 — 표 62 속성 bit 17 ('줄의 첫 세그먼트').
    static func startsLine(_ segment: CoreHwp.HwpParaLineSegInternal) -> Bool {
        segment.property & (1 << 17) != 0
    }

    /// 줄의 부호 있는 전진량 (HWPUNIT): lineHeight + lineSpacing — 고정 줄 간격이 줄 상자보다
    /// 작으면 줄 간격이 음수라 줄 상자보다 작다. Int로 넓혀 미신뢰 캐시의 덧셈 트랩을 막는다.
    static func signedAdvance(of segment: CoreHwp.HwpParaLineSegInternal) -> Int {
        Int(segment.lineHeight) + Int(segment.lineSpacing)
    }
}

private extension HwpAbsoluteCachePlacer {
    /// 낡음 판정(`cacheIsStale`)이 보는 run의 글꼴 크기 — 줄 공간을 예약한 개체 마커는 0 (#217).
    static func staleCheckFontSize(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard !HwpInlineObjectReservation.reservesLineSpace(attributes),
              let value = attributes[kCTFontAttributeName as NSAttributedString.Key],
              CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
        else { return 0 }
        return CTFontGetSize(unsafeBitCast(value as CFTypeRef, to: CTFont.self))
    }
}
