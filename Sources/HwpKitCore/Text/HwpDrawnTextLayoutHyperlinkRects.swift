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
    /// 규약 그대로다. **폭 0 run도 같다** (리뷰 3차): 단일 글리프 `i`·`.`에 kern −3이면 CT가
    /// 폭을 0으로 클램프하지만 잉크(0.65…1.54)는 그대로 그려지므로 버리면 그 글리프가 어느
    /// 링크도 아니다(종전 캐럿 산식은 [0, 2.22]). 잉크가 없는 폭 0 run(공백·U+200B·폭 0 개체
    /// 마커·프레임 안 개행 run — 실측 전부 잉크 empty)은 그대로 버려지고, 렌더러가 글리프를
    /// 안 그리는 run(개체 마커 run delegate·한 줄 끝 표식 `hwp.lineBreak`)은 잉크가 보고돼도
    /// 넓히지 않는다. 양수 폭 run은 잉크로 넓히지 않는다(기울임 오버행이 이웃 링크 상자에
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
        /// 첫 형태처럼 run 전체가 스팬에 드는 **포함**으로 물으면 안 된다: CT는 속성 경계마다
        /// run을 끊지만 **자소 묶음과 글리프 없는 문자는 예외**다 — ZWJ 이모지 열·첫가끝 자모
        /// (U+1112 U+1161 U+11AB)·아랍 lam-alef는 링크 경계가 묶음 안에 떨어져도 한 run으로
        /// 나오고, U+200B·RLM·결합 부호는 속성이 달라도 앞 run에 흡수되며(실측; 서로게이트 쌍은
        /// 갈린다) 그 run의 속성 사전은 첫 글자의 것이다. 포함이면 그 run이 양쪽 스팬에서 다
        /// 버려져 클릭 구멍이 나고, 렌더러는 그 run을 첫 글자의 링크(글자 색·밑줄)로 그리므로
        /// 소속도 첫 글자를 따라야 방출 ≡ 칠이다. 글자 위치 밴드(`GlyphOffsetBand.belongs(to:)`)
        /// 도 같은 규칙이다.
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
            if width <= 0 {
                // 접힌·클램프된 진행 폭만으로는 보이는 글리프가 빠진다 — 잉크까지 넓힌다 (위 주석).
                // 잉크가 있는 폭 0 run은 드물어 속성 브리징은 그때만 치른다.
                let ink = CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0))
                if !ink.isNull, ink.width > 0, drawsGlyphs(run) {
                    minX = min(minX, ink.minX)
                    maxX = max(maxX, ink.maxX)
                }
            }
            extents.append(RunExtent(range: CTRunGetStringRange(run), minX: minX, maxX: maxX))
        }
        return extents
    }

    /// 렌더러(`drawRun`)가 이 run의 글리프를 그리는가 — 개체 마커(run delegate)는 개체 명령이
    /// 따로 그리고, 한 줄 끝 표식(`hwp.lineBreak`)은 글리프를 건너뛴다 (#146). `glyphOffsetBands`
    /// 와 같은 술어다.
    private static func drawsGlyphs(_ run: CTRun) -> Bool {
        let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
        return attributes?[kCTRunDelegateAttributeName as NSAttributedString.Key] == nil
            && attributes?[HwpAttributedStringKey.lineBreak] == nil
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
        /// 이 줄 뒤에 무엇이 오는가 (`ClickBand`) — 문자열의 마지막 줄만 호출자가 준 값이고
        /// 앞 줄들은 같은 문자열의 다음 줄이 뒤따르므로 `.followed`다.
        let listEnd: ListEnd
    }

    /// 문자열의 마지막 줄 뒤에 무엇이 오는가 — 그 줄 클릭 띠의 하단을 정한다 (#233, `ClickBand`).
    /// 문자열 안의 앞 줄들은 언제나 `.followed`다 (같은 문자열의 다음 줄이 뒤따른다).
    enum ListEnd: Sendable {
        /// 같은 문단 목록의 다음 문단이 바로 뒤따른다 (셀·글상자의 가운데 문단, 같은 각주의
        /// 뒤 문단이 이어지는 블록) — 띠는 줄 전진량까지(= 다음 줄 상자 상단)다. 전진량이 줄
        /// 상자보다 작으면(고정 < 상자, 비율 < 100%) 상자 아래 몫은 다음 문단 것이다.
        case followed
        /// 문단 목록의 마지막 줄 (셀·글상자·각주 배열의 끝) — 띠는 줄 상자까지다.
        case end
        /// 뒤에 무엇이 오는지 모른다 — 본문 문단 블록(다음 블록이 이을 수도, 쪽·단의 끝일
        /// 수도 있다)과 공개 `hyperlinkRegions(attributedString:origin:lineWidth:)`. 띠는 둘 중
        /// 넓은 쪽(줄 전진량과 줄 상자 가운데 큰 값)이다: 전진량이 작으면 상자까지 — 안 그러면
        /// 쪽 끝 줄의 베이스라인·밑줄이 띠 밖이다(#233 리뷰: 80% 한 줄 문단의 베이스라인
        /// 탭이 `.text`로 떨어졌다). 다음 블록이 이으면 그 블록이 먼저 히트되므로 겹친 몫은
        /// 그대로 다음 줄 것이다.
        case unknown
    }

    /// 줄 하나에서 링크가 열리는 **세로 범위** (#233) — top-down 페이지 좌표.
    ///
    /// 한글 편집 화면의 규칙을 따른다: 줄 상자 상단(베이스라인 − 앵커)부터 **그 줄의 줄 간격
    /// 몫까지**, 곧 다음 줄 상자 상단까지다 — 문단 사이 간격(문단 위·아래 간격)은 어느 줄의
    /// 것도 아니고, **목록의 마지막 줄**(표 셀·글상자·각주 문단 배열의 마지막 줄)은 줄 상자에서
    /// 끝난다. 한글 12.30.0(6446) macOS 실측 (2026-09-26, 155%, 함초롬바탕 10pt 밑줄 링크를 한
    /// 줄씩 번갈아 왼쪽·오른쪽 칸에 둔 합성 HWPX — 칸마다 위→아래로 눌러 연결 실패 대화상자의
    /// URL로 어느 링크가 열렸는지 읽었다, 경계 ±0.25pt):
    /// - 줄과 줄의 경계 = **다음 줄 상자 상단**. 160% 10pt 줄은 상자 바닥 + 6.0(실측 +5.8…+6.1),
    ///   40pt 문단 끝 글자·40pt 책갈피·40pt 글자 줄은 + 24.0(40pt 몫 여분, 실측 +23.9…+24.1),
    ///   높이 40pt 글자처럼 취급 그림 줄은 + 6.0(여분은 글자 상자 기준 — `HwpLineSpacingRule`,
    ///   실측 +6.3). 같은 문단의 한 줄 끝(LF) 앞뒤도 같다. 다음 줄 글자가 제 상자 위로 솟아도
    ///   (상대 크기 200%·150%) 경계는 그대로다 — 한글은 다음 줄 잉크를 보지 않는다.
    /// - 문단 아래 간격·위 간격 24pt 띠에서는 위·아래 어느 링크도 안 열린다.
    /// - 100%면 경계 = 상자 바닥이라 밑줄(상자 바닥 아래)은 **다음 줄 몫**이고, 고정 8pt(상자
    ///   10pt)면 경계 = 다음 줄 상단이라 상자 바닥 2pt도 다음 줄 몫이다 — 띠는 상자가 아니라
    ///   줄 전진량을 따른다.
    /// - 셀·글상자·각주의 마지막 줄은 줄 상자 바닥에서 끝난다(밑줄도 안 열린다 — 셀 높이
    ///   100pt로 아래가 비어 있어도). 쪽·문서의 마지막 줄도 같다.
    ///
    /// 종전의 CT 줄 지표(`ascent`·`descent`)는 이 규칙과 무관하다 — 10pt 링크와 한 줄인 40pt
    /// 문단 끝 글자·40pt 책갈피는 CT 줄을 키우지 않아 줄 상자 바닥에 붙는 밑줄(#226)과 그
    /// 사이 빈칸이 영역 밖이었고, 40pt 그림 줄은 위로만 커졌다. **합집합으로 두지 않는다**:
    /// 함초롬바탕 10pt의 CT ascent 10.7이 상자 상단(8.5)보다 높아 앞 줄의 줄 간격 띠(한글은
    /// 앞 줄 몫)를 이 링크가 가져간다 — 앞 블록이면 뒤 블록이 먼저 히트되므로 앞 링크가 진다.
    /// 같은 몫을 뒤 블록의 **링크 아닌 글자** claim이 가져가는 길은 히트가 막는다
    /// (`HwpHitTester.textClaim` — 프레임 위 글자 claim은 아래 블록 링크에 양보한다).
    ///
    /// **본문 블록의 마지막 줄은 줄 간격 몫까지 둔다** (`ListEnd.unknown`) — 한글은 쪽·단·
    /// 문서의 마지막 줄에서 그 몫을 빼지만 문단 블록은 자기가 단의 끝인지 모른다. 그 몫은 블록
    /// 프레임 안(문단 높이 = 줄 전진량 합 + 아래 간격)이라 다른 블록을 가리지 않는다. 컨테이너
    /// 문단은 반대로 목록 끝을 알고(배열의 마지막), 몫을 두면 셀 높이(마지막 줄 간격 제외, #160)
    /// 밖 다음 행 셀까지 넘쳐 그 칸의 빈자리를 누르면 윗 셀 링크가 열리므로 한글대로 뺀다.
    ///
    /// 글꼴 속성이 없는 문자열도 CT가 run에 기본 글꼴(Helvetica 12)을 달아 주므로 그 크기의
    /// 상자다. 잴 run이 없어 상자가 0인 줄만 CT 줄 지표로 폴백한다 (방어 — 높이 0 rect를 내지
    /// 않는다). 글자 위치로 옮겨진 run의 밴드(`GlyphOffsetBand`)는 이 띠가 아니라 **CT 줄
    /// 상자를 옮긴 잉크 범위**다 — 칠 커버리지(`paintedRects`)와 같은 정의로 남는다.
    struct ClickBand: Equatable {
        let top: CGFloat
        let height: CGFloat
    }

    /// `drawn`의 링크 클릭 띠 (`ClickBand`) — `lines`가 이 줄을 놓은 기하 그대로다: 상단은 줄
    /// 상자 상단(`HwpDrawnLine.boxTop`), 높이는 뒤에 오는 것(`ListEnd`)에 따라 줄 자신의 전진량
    /// (`lineAdvance` — 측정·렌더가 쌓는 `HwpLineAdvance`의 줄 몫, 문단 사이 간격 제외), 줄
    /// 상자(`boxHeight`), 또는 둘 중 큰 값이다. 다시 재지 않으므로 문단 안 줄의 띠 하단이 다음
    /// 줄 상자 상단과 비트 단위로 같고, 양쪽 정렬 재조판본(0-기준 부분 복사본)에서 문단 끝을
    /// 잘못 짚을 일도 없다.
    static func clickBand(of drawn: HwpDrawnLine, listEnd: ListEnd) -> ClickBand {
        guard drawn.boxHeight > 0 else {
            return ClickBand(
                top: drawn.baselineOrigin.y - drawn.ascent, height: drawn.ascent + drawn.descent
            )
        }
        let height = switch listEnd {
        case .followed: drawn.lineAdvance
        case .end: drawn.boxHeight
        case .unknown: max(drawn.lineAdvance, drawn.boxHeight)
        }
        return ClickBand(top: drawn.boxTop, height: height)
    }

    /// 한 줄에서 링크 스팬이 차지하는 rect들을 `regions`에 바로 쌓는다 — 스팬의 run이
    /// 화면에서 잇닿은 **구간마다** 클릭 띠(`ClickBand`) rect 하나와, 글자 위치로 옮겨진 run
    /// 중 **이 스팬에 속한 것마다** 밴드 rect.
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
        let band = clickBand(of: drawn, listEnd: geometry.listEnd)
        for segment in visualSegments(of: extents, in: spanCTRange) {
            regions.append((
                rect: CGRect(
                    x: drawn.baselineOrigin.x + segment.lowerBound, y: band.top,
                    width: segment.upperBound - segment.lowerBound, height: band.height
                ),
                url: url
            ))
        }
        // 옮겨진 run의 밴드는 클릭 띠가 아니라 **CT 줄 상자를 옮긴 잉크 범위**다 — 칠
        // 커버리지(`paintedRects`)와 같은 정의라 옮겨진 글자 위의 탭이 자기 링크를 연다.
        let top = drawn.baselineOrigin.y - drawn.ascent
        let height = drawn.ascent + drawn.descent
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
