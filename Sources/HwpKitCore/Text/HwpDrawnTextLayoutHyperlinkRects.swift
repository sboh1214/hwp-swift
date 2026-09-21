import CoreGraphics
import CoreText
import Foundation

// 링크 스팬 하나가 한 줄에서 차지하는 rect — `HwpDrawnTextLayout.hyperlinkRegions`의
// 줄 단위 알맹이 (#197 리뷰).

extension HwpDrawnTextLayout {
    /// 줄의 run 하나가 **진행 폭**으로 차지하는 가로 범위(줄 원점 기준)와 그 run의 문자열
    /// 범위 — **CTLine 인덱스**다 (`GlyphOffsetBand.ranges`와 같은 기준, 재조판된 부분
    /// 복사본이면 0-기준).
    ///
    /// 스팬 양끝의 `CTLineGetOffsetForStringIndex`로는 양방향 줄의 링크 자리를 낼 수 없다
    /// (#201): 논리 순서와 화면 순서가 달라 한 스팬이 화면에서 **떨어진 여러 구간**을
    /// 차지하고, 방향 경계 인덱스의 오프셋은 반대쪽 run의 가장자리를 가리킨다 (실측
    /// `abc אבג`, Helvetica 10pt: 인덱스 4 → 18.901, 7 → 18.901인데 א는 28.804…35.254에
    /// 있다 — 스팬 하나로 전체를 걸어도 히브리 글자 셋이 통째로 빠졌다). run은 화면 순서로
    /// 놓이고 자기 자리를 안다.
    ///
    /// 가로 범위는 run의 **기저 글리프 위치**에 run 텍스트 매트릭스를 건 값과
    /// `CTRunGetTypographicBounds` 폭으로 낸다 — positions는 매트릭스 **적용 전** 좌표라
    /// (장평 50% run이 줄 중간에서 두 배 자리에 선다, #200 리뷰) 렌더러(`drawRun`)처럼
    /// 매트릭스를 걸어야 줄 좌표가 되고, 폭과 advances는 적용 후 값이다. **기준 글리프는
    /// 방향에 따라 다르다** (PR 리뷰): run 안 글리프는 시각 순서인데 결합 부호는 LTR run에서
    /// 기저 **뒤**, RTL run에서 기저 **앞**에 온다. 그래서 LTR은 첫 글리프 위치가 왼쪽 끝이고,
    /// RTL은 첫 글리프가 논리 마지막 글자의 부호일 수 있어(니쿠드·샤다 — GPOS 오프셋만큼
    /// 기저와 다른 자리: GeezaPro `شَّ` 3.71pt·함초롬바탕 1.26pt·Times New Roman 홀람은
    /// 기저 **왼쪽** 1.59pt) 마지막 글리프(논리 첫 글자의 기저)의 위치 + advance를 오른쪽
    /// 끝으로 잡고 폭을 뺀다. 첫 글리프로 잡으면 링크 rect가 줄 상자 밖으로 나가거나 이웃
    /// 링크 글자를 덮는다. 인접 run의 끝과 다음 run의 시작은 CT가 같은 누적값을 주는
    /// 자리라 실측 글꼴(Helvetica·Lucida Grande 폴백·장평·기울임 근사)에서는 비트 단위로
    /// 같았다.
    ///
    /// 진행 폭은 **자간(`kCTKern`)을 품는다** — 줄 상자(`CTLineGetTypographicBounds`·
    /// `selectionRect`)와 같은 정의다. 종전의 양끝 캐럿(`CTLineGetOffsetForStringIndex`)은
    /// 글자 사이 kern을 반씩 나누고 줄 끝에서는 kern을 통째로 뺐으므로(실측 kern +2: 경계
    /// 14.123 vs run 끝 15.123, 줄 끝 27.685 vs 줄 폭 29.685; kern −1이면 줄 끝 캐럿이 줄 상자
    /// **밖** 18.685 vs 17.685), 자간이 있는 줄의 스팬 경계는 kern/2, 줄 끝은 kern만큼 종전과
    /// 다르다 — 링크 rect의 끝이 줄 상자 끝과 일치하는 쪽이 새 값이다.
    ///
    /// **진행 폭은 음수일 수 있다** (PR 리뷰): 좁은 글리프에 큰 음수 자간이 걸리면(Helvetica
    /// 10pt `í`(i + U+0301)에 kern −3 → run 폭 −0.222pt, HWP 자간 −30%로 닿는 입력) 끝이
    /// 시작보다 왼쪽이다(단일 글리프의 kern은 CT가 폭 0으로 클램프하므로 결합 부호가 붙은
    /// run에서 난다). 역전된 채 `ClosedRange`를 만들면 프로세스가 종료되므로 `minX ≤ maxX`로
    /// 정규화하되, 접힌 진행 폭 [시작 + 폭, 시작]만 담으면 원점 **오른쪽**에 그려지는 글리프
    /// (잉크 0.3…2.5)가 어느 링크도 아니게 된다(리뷰 2차 — 종전 캐럿 산식은 [0, 2.78]을
    /// 냈다). 그래서 진행 폭이 음수인 run만 **잉크 경계**(`CTRunGetImageBounds`, 밴드와 같은
    /// 줄 원점 기준·매트릭스 적용 후)까지 넓힌다 — 글리프 중심은 자기 링크를 열어야 한다는
    /// 규약 그대로다. 양수 폭 run은 잉크로 넓히지 않는다(기울임 오버행이 이웃 링크 상자에
    /// 들어가 단방향 줄이 종전과 달라진다).
    struct RunExtent {
        let range: CFRange
        let minX: CGFloat
        let maxX: CGFloat

        init(range: CFRange, minX: CGFloat, maxX: CGFloat) {
            self.range = range
            self.minX = min(minX, maxX)
            self.maxX = max(minX, maxX)
        }

        /// 이 run이 `span`의 것인가 — run의 **첫 글자**가 스팬 안에 있으면 그 스팬 것이다.
        ///
        /// 밴드(`GlyphOffsetBand.belongs(to:)`)처럼 **포함**으로 물으면 안 된다: CT는 속성
        /// 경계마다 run을 끊지만 **자소 묶음은 예외**다 — ZWJ 이모지 열·첫가끝 자모(U+1112
        /// U+1161 U+11AB)·아랍 lam-alef는 링크 경계가 묶음 안에 떨어져도 한 run으로 나오고
        /// (실측; 결합 부호 U+0301과 서로게이트 쌍은 갈린다) 그 run의 속성 사전은 첫 글자의
        /// 것이다. 포함이면 그 run이 양쪽 스팬에서 다 버려져 클릭 구멍이 나고, 렌더러는 그
        /// run을 첫 글자의 링크(글자 색·밑줄)로 그리므로 소속도 첫 글자를 따라야 방출 ≡ 칠이다.
        func belongs(to span: CFRange) -> Bool {
            range.location >= span.location
                && range.location < span.location + span.length
        }
    }

    /// 줄의 run별 진행 폭 범위 — 화면 순서(`CTLineGetGlyphRuns` 순서). 글리프가 없는 run은
    /// 자리가 없으니 뺀다.
    static func runExtents(of line: CTLine) -> [RunExtent] {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var extents: [RunExtent] = []
        extents.reserveCapacity(runs.count)
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }
            let matrix = CTRunGetTextMatrix(run)
            let width = CGFloat(
                CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
            )
            var position = CGPoint.zero
            let start: CGFloat
            if CTRunGetStatus(run).contains(.rightToLeft) {
                // 마지막 글리프 = 논리 첫 글자의 기저 (RTL run은 부호가 기저 앞이다).
                // advance는 run 끝까지의 델타라 위치 + advance가 run의 오른쪽 끝이다.
                CTRunGetPositions(run, CFRange(location: glyphCount - 1, length: 1), &position)
                var advance = CGSize.zero
                CTRunGetAdvances(run, CFRange(location: glyphCount - 1, length: 1), &advance)
                start = position.applying(matrix).x + advance.width - width
            } else {
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                start = position.applying(matrix).x
            }
            var minX = min(start, start + width)
            var maxX = max(start, start + width)
            if width < 0 {
                // 접힌 진행 폭만으로는 보이는 글리프가 빠진다 — 잉크까지 넓힌다 (위 주석).
                let ink = CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0))
                if !ink.isNull, ink.width > 0 {
                    minX = min(minX, ink.minX)
                    maxX = max(maxX, ink.maxX)
                }
            }
            extents.append(RunExtent(range: CTRunGetStringRange(run), minX: minX, maxX: maxX))
        }
        return extents
    }

    /// `span`에 속한 run들의 가로 범위를 **화면에서 잇닿은 구간별로** 합친다 (줄 원점 기준).
    ///
    /// 단방향 줄에서는 스팬의 run이 늘 잇닿아 구간 하나 = 종전의 스팬 양끝 상자다(자간이
    /// 없을 때 — `RunExtent` 주석). 양방향 줄에서는 사이에 다른 링크의 run이 끼어 구간이
    /// 여럿이다 — 그것을 외접 사각형 하나로 합치면 그 사이 글자를 다른 링크에서 뺏는다
    /// (#201). 폭 0 구간(폭 0 개체 마커·U+200B)은 차지한 자리가 없으니 버린다 (종전의
    /// `maxX > minX` 가드).
    /// 범위 생성은 `RunExtent`가 정규화한 `minX ≤ maxX`에 기댄다 — 음수 진행 폭 run(큰 음수
    /// 자간)이 역전된 범위로 들어오면 `ClosedRange`가 트랩한다.
    ///
    /// 한 번 훑는다 — `CTLineGetGlyphRuns`가 run을 화면 순서(왼쪽→오른쪽)로 주므로 (실측
    /// 양방향·아랍 shaping 모두) 정렬·필터 배열을 스팬 × 줄마다 만들지 않는다. 순서가 어긋난
    /// 입력이 오면 그때만 정렬해 다시 훑는다 — 잇닿음 판정이 순서에 기대므로 순서 없이
    /// 합치면 사이 글자를 건너 다리를 놓는다. 비용은 종전 양끝 오프셋 질의보다 작다 (릴리스
    /// 빌드 실측은 AGENTS.md "글자 위치" 절의 #201 항목).
    static func visualSegments(
        of extents: [RunExtent], in span: CFRange
    ) -> [ClosedRange<CGFloat>] {
        var segments: [ClosedRange<CGFloat>] = []
        var previousMinX = -CGFloat.infinity
        for extent in extents where extent.belongs(to: span) {
            guard extent.minX >= previousMinX else {
                return visualSegments(
                    of: extents.filter { $0.belongs(to: span) }.sorted { $0.minX < $1.minX },
                    in: span
                )
            }
            previousMinX = extent.minX
            if let last = segments.last,
               extent.minX <= last.upperBound + segmentJoinTolerance
            {
                segments[segments.count - 1] =
                    last.lowerBound ... max(last.upperBound, extent.maxX)
            } else {
                segments.append(extent.minX ... extent.maxX)
            }
        }
        segments.removeAll { $0.upperBound <= $0.lowerBound }
        return segments
    }

    /// 인접 run의 경계는 실측 글꼴에서는 비트 단위로 같지만 폴백 글꼴에 따라 누적 오차
    /// (1e-15 수준)가 날 수 있어, 눈에 안 보이는 틈으로 구간이 갈리지 않게 둔 여유.
    private static let segmentJoinTolerance: CGFloat = 0.001

    /// 줄 하나의 스팬 기하 캐시 — `hyperlinkRegions`가 줄마다 하나씩 두고 그 줄에 닿는
    /// 스팬들이 나눠 쓴다.
    struct SpanLineGeometry {
        /// 글자 위치로 옮겨진 run의 잉크 밴드 — 줄 캐시와 함께 미리 걷는다 (옮겨진 run이
        /// 없는 문단은 CTRun 순회 없이 빈 배열, `glyphOffsetBands(ofLines:in:)`).
        let bands: [GlyphOffsetBand]
        /// run별 진행 폭 범위 (#201) — 그 줄에 처음 닿는 스팬이 걷고, 스팬이 안 닿는 줄은
        /// 걷지 않는다 (링크 하나뿐인 긴 문단에서 모든 줄을 걷지 않는다).
        var runExtents: [RunExtent]?
    }

    /// 한 줄에서 링크 스팬이 차지하는 rect들을 `regions`에 바로 쌓는다 — 스팬의 run이
    /// 화면에서 잇닿은 **구간마다** 줄 상자 rect 하나와, 글자 위치로 옮겨진 run 중 **이
    /// 스팬에 속한 것마다** 밴드 rect.
    /// (배열로 돌려주면 줄마다 임시 할당이 생겨 캐시로 아낀 몫의 절반을 도로 쓴다 —
    /// 실측 median: 120스팬 ~40줄 2.93 → 3.55ms.)
    ///
    /// 스팬 전체 폭에 최대 오프셋을 걸면 안 옮겨진 run 위·아래의 빈 자리까지 이 링크가
    /// 가져가, 뒤에 있는 링크가 진다 (`paintedRects`와 같은 R54 정밀 커버리지 규약,
    /// #197 리뷰 3차).
    static func appendHyperlinkRects(
        of drawn: HwpDrawnLine,
        spanRange: NSRange,
        geometry: inout SpanLineGeometry,
        url: String,
        into regions: inout [(rect: CGRect, url: String)]
    ) {
        let lineRange = drawn.stringRange
        let lower = max(spanRange.location, lineRange.location)
        let upper = min(
            spanRange.location + spanRange.length, lineRange.location + lineRange.length
        )
        guard upper > lower else { return }
        // 재조판된 CTLine은 자체 범위가 0-기준 부분 복사본이라 단위 문자열 인덱스를
        // CTLine 인덱스로 옮긴다 — run 범위·밴드 범위 둘 다 그 기준이다.
        let ctRange = CTLineGetStringRange(drawn.line)
        let spanCTRange = CFRange(
            location: ctRange.location + (lower - lineRange.location), length: upper - lower
        )
        let extents = geometry.runExtents ?? Self.runExtents(of: drawn.line)
        geometry.runExtents = extents
        let top = drawn.baselineOrigin.y - drawn.ascent
        let height = drawn.ascent + drawn.descent
        for segment in visualSegments(of: extents, in: spanCTRange) {
            regions.append((
                rect: CGRect(
                    x: drawn.baselineOrigin.x + segment.lowerBound, y: top,
                    width: segment.upperBound - segment.lowerBound, height: height
                ),
                url: url
            ))
        }
        // **이 스팬에 속한 run의 밴드만** 가져간다 (#197 리뷰 4차). 밴드는 이 스팬 자신의
        // run 잉크라 구간 상자로 **자르지 않는다** — 잉크는 진행 폭 상자 밖으로 삐칠 수 있고
        // (기울임 근사의 오버행), 단방향 줄에서는 run이 늘 스팬 상자 안이라 자르나 마나 같다.
        // 양방향 줄에서 남의 잉크를 안 가져가는 것은 가로 클립이 아니라 `belongs(to:)`의
        // 몫이다 (실측 `abc אבג`에 `abc א`+`בג` 두 링크: 종전 스팬 상자 0…28.313이 뒤 스팬
        // 글자 18.903…28.313을 덮어, 뒤 링크만 10pt 올리면 올라간 잉크 위의 탭이 **앞** URL을
        // 열었다).
        for band in geometry.bands where band.belongs(to: spanCTRange) {
            let bandMinX = drawn.baselineOrigin.x + band.minX
            let bandMaxX = drawn.baselineOrigin.x + band.maxX
            guard bandMaxX > bandMinX else { continue }
            regions.append((
                rect: CGRect(
                    x: bandMinX, y: top - band.offset,
                    width: bandMaxX - bandMinX, height: height
                ),
                url: url
            ))
        }
    }
}
