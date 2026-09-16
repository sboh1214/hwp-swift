import CoreGraphics
import Foundation

/// 한글.app 실물 대조로 확정한 렌더 튜닝 상수의 단일 소스.
///
/// 규약: 각 상수는 ① 값 ② 실측 근거 (픽스처/실물) ③ 검증 방법을
/// doc-comment로 갖는다. 값 변경은 fidelity 전수 + 블록 스냅샷 + 실물
/// 대조가 필수이고, `HwpRenderTuningTests`의 값 핀도 함께 갱신해야 한다.
///
/// 여기 없는 실측 상수: `HwpChartPainter`의 차트 투영 기하 (상호 결합
/// 실측 모델이라 in-place 유지).
public enum HwpRenderTuning {
    /// 본문 텍스트 조판·장식
    public enum Text {
        /// 한글 줄 모델의 베이스라인 앵커 비율 — 텍스트든 개체든 베이스라인을
        /// **줄 상자 높이**의 0.85 지점에 둔다 (`HwpDrawnTextLayout.baselineAnchor`).
        /// 줄 상자 높이는 그 줄의 **상대크기 적용 전 기본 글자 크기** (키 큰 글자처럼
        /// 취급 개체가 있으면 그 개체 높이) 이고, 줄 간격 종류·값과 글꼴 지표는
        /// 여기에 관여하지 않는다.
        ///
        /// 실측: 한글은 이 값을 줄 캐시 (`PARA_LINE_SEG`)에 직접 적는다 —
        /// `baselineDistance ÷ lineHeight`. 한글.app 12.30.0 (2026-09-12, #178) 로
        /// 글자 크기 8종 (5·7·10·12·15·20·30·40pt) × 줄 간격 종류 4종 (비율 100~300%·
        /// 고정 5~30pt·여백만 0~10pt·최소 5~30pt) × 글꼴 3종 (함초롬바탕·함초롬돋움·
        /// Apple SD 산돌고딕 Neo) × 상대크기 2종 (50·170%) 을 실은 합성 문서를 저장시켜
        /// 얻은 34개 표본이 **전부 정확히 0.85**였고 (예: 10pt 비율 160% → `vertsize`
        /// 1000·`baseline` 850, 상대크기 170% 줄도 같다), 코퍼스의 실물 캐시도 같다
        /// (`noori` 1500/1275·6134/5214·300/255, 헌법주석 각주 900/765).
        /// 같은 문서를 한글이 내보낸 PDF의 벡터 텍스트 베이스라인이
        /// `lineLocation + baselineDistance`와 최대 0.10pt (한글 PDF의 0.12pt 장치
        /// 양자화) 차이였다 — **한글이 그리는 자리도 이 규칙이다**.
        ///
        /// 검증: `HwpBaselineAnchorTests` 비율 + `FixtureBaselineAnchorTests` 캐시 대조 +
        /// `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let baselineAnchorRatio: CGFloat = 0.85

        /// 키 큰 인라인 개체 (run delegate) 줄에서 밑줄이 되돌아갈 개체 ascent 비율
        /// (`HwpDrawnTextLayout.underlineReturnDrop`). `baselineAnchorRatio`와 상보
        /// 관계 (1 − 0.85) 이지만 독립 실측값으로 별도 고정한다.
        /// 실측: 공공누리 실물 (실물은 밑줄을 개체 하단 = 상자 바닥에 남긴다).
        /// 검증: fidelity 전수 + 실물 대조.
        public static let baselineLiftRatio: CGFloat = 0.15

        /// 개행 없는 한 줄 문단이 폭을 이 배율 (6%) 이내로 넘으면 줄바꿈
        /// 없이 한 줄로 배치한다.
        /// 실측: noori 제목 3행 후행 '-' 실물 — 행이 글상자 가장자리를
        /// 살짝 넘침. 검증: fidelity 전수 + 실물 대조.
        public static let slightOverflowWidthRatio: CGFloat = 1.06

        /// 볼드 페이스 없는 폰트의 합성 볼드 kCTStrokeWidth (음수 =
        /// 채움+윤곽).
        /// 실측: 실물 명조 볼드 획 비율 1.41x (noori 실측 — -2.2%는
        /// 1.26x). 검증: fidelity 전수 + 실물 대조.
        public static let syntheticBoldStrokeWidth: Double = -3.5

        /// 글자 그림자 오프셋 배율 — 한글 그림자는 선언 %의 약 1.5배
        /// 위치에 찍힌다.
        /// 실측: CharShapeProperty 실물 — 10% 선언 → ~15% 실측.
        /// 검증: fidelity 전수 + 실물 대조.
        public static let shadowOffsetScale: Double = 1.5

        /// 취소선(밑줄 종류 '글자 가운데' 포함) 중심의 베이스라인 위 높이 =
        /// 글자 크기 × 이 배율.
        /// 실측: 한글.app 12.30.0 (2026-09-08) `CharShape` 쌍을 PDF로 내보내
        /// 벡터 좌표를 읽었다 — 5·10·15·20·40·60·100pt에서 베이스라인 대비
        /// +1.80/3.60/5.28/7.08/14.04/21.00/35.04pt (0.350~0.360, 장치 좌표
        /// 0.12pt 양자화). 함초롬바탕·함초롬돋움·Apple SD 산돌고딕 Neo가 같은
        /// 값이라 폰트 지표가 아니라 글자 크기 비례다. **HWP와 HWPX가 같은
        /// 값**이다 (#136). 첨자 run에서는 **첨자로 옮겨진 베이스라인** 위
        /// 줄어든 크기 × 이 배율이다 (#179, 2026-09-15 실측: 10pt 위 첨자 6.36pt
        /// 글리프가 4.32pt 올라간 표본에서 선은 6.60pt 위 = 4.32 + 0.35 × 6.36, 장치
        /// 0.12pt 양자화) — 글자 위치(`hh:offset`)로 옮겨진 몫은 따라가지 않는다.
        /// 검증: `FixtureDecorationLineRenderTests`(+`+Script`) 픽셀 핀 + fidelity 전수.
        public static let strikethroughCenterRatio: CGFloat = 0.35

        /// 밑줄 '글자 위'(표 35 밑줄 종류 3) 중심의 베이스라인 위 높이 =
        /// 글자 크기 × 이 배율.
        /// 실측: 같은 세션의 `underline-above` 쌍 — 10/40/100pt에서
        /// +8.76/34.68/86.88pt (0.867~0.876). 함초롬돋움도 같은 값이다 (#136).
        /// 검증: `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let underlineAboveCenterRatio: CGFloat = 0.87

        /// 밑줄 '글자 아래'(표 35 밑줄 종류 1) 중심의 베이스라인 **아래** 깊이 =
        /// 글자 크기 × 이 배율.
        /// 실측: 한글.app 12.30.0 (2026-09-12, #176) `CharShape` HWPX 기반 합성
        /// 문서(`hp:linesegarray` 제거)를 PDF로 내보내 벡터 좌표를 읽었다 — 5·7·8·
        /// 10·12·13·15·20·25·30·40·60·100pt에서 베이스라인 대비 −0.84/1.08/1.32/
        /// 1.68/2.04/2.28/2.52/3.48/4.32/5.16/6.84/10.20/17.04pt (선언 크기 대비
        /// 0.154~0.175, 장치 좌표 0.12pt 양자화; 60pt 이상은 정확히 0.170). 함초롬바탕·함초롬돋움·
        /// Apple SD 산돌고딕 Neo·HY울릉도M 네 글꼴이 **모든 크기에서 같은 값**이라
        /// descent·post `underlinePosition` 같은 글꼴 지표가 아니라 글자 크기
        /// 비례다. 변경 추적 삽입 밑줄도 같은 자리·같은 두께다 (#187 실측: 13개 글꼴
        /// 전부 삽입 밑줄 = 일반 밑줄, 삭제선 = 일반 취소선). MS 워드 호환 문서에서는
        /// 이 비율 대신 글꼴 지표를 쓴다 — 아래 `msWord*` 상수.
        /// 첨자 run에서도 **원래 베이스라인** 아래 **축소 전 크기** × 이 배율이다
        /// (#179 실측: 10pt 위/아래 첨자 모두 1.68pt 아래) — 취소선과 달리 첨자
        /// 이동을 따라가지 않는다.
        /// 검증: `HwpDecorationLineGeometryTests`(+`+Script`) 비율 +
        /// `FixtureDecorationLineRenderTests`(+`+Script`) 픽셀 핀 + fidelity 전수.
        public static let underlineBelowCenterRatio: CGFloat = 0.17

        /// 장식선(글자 아래·글자 위 밑줄, 취소선, 글자 가운데 밑줄) 두께 = 글자
        /// 크기 × 이 배율.
        /// 실측: 같은 세션 — 한글 PDF의 선 폭은 5·7·8·10·12·13·15·20·25·30·40·60·
        /// 100pt에서 0.24/0.24/0.36/0.36/0.48/0.48/0.60/0.84/0.96/1.20/1.56/2.40/
        /// 3.96pt로, 13개 전부 `0.12pt × round(크기 / 3)` = 0.04em을 600dpi 장치
        /// 단위로 반올림한 값이다. 밑줄과 취소선이 같은 폭이고 네 글꼴이 같다.
        /// 하한은 두지 않는다 — 한글도 5pt를 0.24pt로 그린다. 종전 0.4pt 고정은
        /// 10pt에서만 맞았다. 첨자 run에서도 **축소 전 크기** 기준이다 (#179 실측:
        /// 10pt 첨자의 네 선 모두 0.36pt = 본문과 같음).
        /// 검증: `HwpDecorationLineGeometryTests`(+`+Script`) 두께 비율 + fidelity 전수.
        public static let decorationLineThicknessRatio: CGFloat = 0.04

        /// MS 워드 호환 문서(`HwpCompatibleDocumentTarget.msWord`)의 줄 상자 높이 =
        /// CJK 글꼴의 (winAscent + winDescent) × 이 배율 (`HwpMsWordLineBox`, #187·
        /// #194). 장식선은 두 글꼴 갈래 모두 줄 상자 ÷ 이 배율을 기준 상자로 쓴다.
        /// 실측: 한글 12.30.0 (2026-09-15) 이 MS 워드 호환 합성 문서를 다시 저장한
        /// 줄 캐시 `vertsize` — 함초롬돋움 80pt 13531 (1.6914em = 1.3 × 1.30), Apple SD
        /// 산돌고딕 Neo 12477 (1.5596 = 1.3 × 1.20), HY울릉도M 10406 (1.3008 = 1.3 × 1.00),
        /// 맑은 고딕 13836 (1.7295 = 1.3 × 1.3301); `track-changes` 실물 캐시 1692 = 1.3 ×
        /// 1.30 (10pt). 그 밖의 글꼴은 winAscent + winDescent + lineGap이다 (Helvetica
        /// 9407 = 1.1759 = 0.9502 + 0.2251, Times New Roman 9211 = 1.1514 = 0.8911 +
        /// 0.2163 + 0.0425).
        /// 검증: `HwpMsWordLineBoxTests` + `HwpRenderTuningTests` 값 핀.
        public static let msWordLineHeightCellRatio: CGFloat = 1.3

        /// MS 워드 호환 문서 CJK 글꼴의 줄 상자 상단 → 베이스라인 = winAscent +
        /// (winAscent + winDescent) × 이 배율 — 1.3배 상자의 여분 0.3을 위아래로 반씩
        /// 나눈 값. 실측: 같은 줄 캐시의 `baseline` — 함초롬돋움 10125 (1.2656em =
        /// 1.07 + 0.15 × 1.30), Apple SD 8641 (1.0801 = 0.90 + 0.15 × 1.20), HY울릉도M
        /// 8070 (1.0088 = 0.8584 + 0.15 × 1.00); `track-changes` 실물 1266 = 1.07 + 0.195.
        /// 그 밖의 글꼴은 winAscent + lineGap이다 (Helvetica 7602 = 0.9503, Times New
        /// Roman 7477 = 0.9346 = 0.8911 + 0.0425).
        /// 검증: `HwpMsWordLineBoxTests` + `HwpRenderTuningTests` 값 핀.
        public static let msWordBaselineMarginCellRatio: CGFloat = 0.15

        /// MS 워드 호환 문서의 밑줄('글자 아래'·'글자 위'·변경 추적 삽입 밑줄) 두께 =
        /// 기준 상자 높이(`HwpMsWordLineBox.cellHeight`) × 글자 크기 × 이 배율.
        /// 실측: 한글 12.30.0 (2026-09-15) PDF 내보내기, 글꼴 32종 × 10·40·80pt (변경
        /// 내용 추적 문서라 쪽이 0.8배 축소돼 80pt 글리프가 63.36pt로 찍힌다 — 비율은
        /// 그 관측 크기 기준) — 함초롬돋움 4.20pt (0.0663em = 0.051 × 1.30), Apple SD
        /// 산돌고딕 Neo 3.84pt (0.0606em = 0.0505 × 1.20), HY울릉도M 3.24pt (0.0511 =
        /// 0.0511 × 1.00), 맑은 고딕 4.32pt (0.0682 = 0.0513 × 1.33), Menlo 3.72pt
        /// (0.0587 = 0.0504 × 1.164), Helvetica 2.88pt (0.0455 = 0.0503 × 0.9045), Courier
        /// New 2.76pt (0.0436 = 0.050 × 0.8721) — 전부 0.050~0.052 (장치 0.12pt 양자화). 취소선은
        /// 호환 문서에서도 글자 크기 × `decorationLineThicknessRatio`다 (같은 실측:
        /// 모든 글꼴 0.0398em).
        /// 검증: `HwpDecorationLineGeometryTests+Compat` 두께 + `HwpRenderTuningTests`.
        public static let msWordUnderlineThicknessCellRatio: CGFloat = 0.05

        /// MS 워드 호환 문서의 밑줄 중심이 기준 상자 가장자리(글자 아래 밑줄은
        /// `descent`, 글자 위 밑줄은 `ascent`) 밖으로 나가는 거리 = 기준 상자 높이 ×
        /// 글자 크기 × 이 배율. 두께 0.05와 함께 선 안쪽 가장자리가 상자 안으로 0.004
        /// 들어온다.
        /// 실측: 같은 스윕 — 밑줄 중심 (`descent` 기준) 함초롬돋움 −0.2576em = −(0.23 +
        /// 0.0212 × 1.30), Apple SD −0.3258 = −(0.30 + 0.0215 × 1.20), HY울릉도M −0.1629
        /// = −(0.1416 + 0.0213 × 1.00), 맑은 고딕 −0.2689 = −(0.2417 + 0.0205 × 1.33),
        /// Menlo −0.2595 = −(0.2358 + 0.0204 × 1.164), Helvetica −0.1080 = −(0.0895 +
        /// 0.0205 × 0.9045); 글자 위 밑줄 (`ascent` 기준) 함초롬돋움 +1.0985 = 1.07 +
        /// 0.0219 × 1.30, Apple SD +0.9261 = 0.90 + 0.0218 × 1.20, Helvetica +0.8333 =
        /// 0.8146 + 0.0207 × 0.9045 — 전부 0.020~0.023. 이슈 #187의 근사 −(winDescent +
        /// 두께/2)는 0.025라 함초롬 40pt에서 0.2pt(0.004 × 1.30 × 40) 낮았다.
        /// 검증: `HwpDecorationLineGeometryTests+Compat` 위치 + `HwpRenderTuningTests`.
        public static let msWordUnderlineOffsetCellRatio: CGFloat = 0.021

        /// MS 워드 호환 문서의 취소선(글자 가운데 밑줄·변경 추적 삭제선 포함) 중심의
        /// 베이스라인 위 높이 = 기준 상자의 `ascent` × 글자 모양 기본 크기(슬롯 상대
        /// 크기 무관, 첨자는 축소 비율) × 이 배율.
        /// 실측: 같은 스윕 — 함초롬돋움 +0.2917em (÷ 1.07 = 0.2726), Apple SD 산돌고딕
        /// Neo +0.2481 (÷ 0.90 = 0.2757), HY울릉도M +0.2330 (÷ 0.8584 = 0.2714), 맑은 고딕
        /// +0.2973 (÷ 1.0884 = 0.2732), Menlo +0.2538 (÷ 0.9282 = 0.2734), Helvetica
        /// +0.2197 (÷ 0.8146 = 0.2697), Times New Roman +0.2159 (÷ 0.8009 = 0.2696),
        /// Courier New +0.1913 (÷ 0.7018 = 0.2726) — 0.267~0.278 (장치 양자화 ±0.003).
        /// `track-changes` 실물의 삭제선 +0.29em (#136·#176) 은 함초롬돋움의 이 값이다.
        /// 검증: `HwpDecorationLineGeometryTests+Compat` 위치 + `HwpRenderTuningTests`.
        public static let msWordStrikethroughAscentRatio: CGFloat = 0.273
    }

    /// 문단 번호·개요 번호 라벨 (#154)
    public enum Numbering {
        /// 번호 너비를 자릿수에 맞추지 않는(`useInstWidth` 해제) 정의의 번호
        /// 너비 = 라벨 글자 크기 × 이 배율 + 너비 보정값
        /// (`HwpTextRunBuilder.NumberingHeadingMetrics`).
        /// 실측: 한글.app 12.30 (2026-09-06) `outline-numbering` 1수준 `I.`
        /// (오른쪽 정렬·보정 2pt·거리 10pt) — 라벨이 문단 여백에서 10pt일 때
        /// 10.8pt, 20pt일 때 20.0pt 안쪽에 놓여 너비가 글자 크기에 비례하고
        /// 보정값은 그대로 더해진다. 검증: 같은 픽스처의 PrvImage fidelity +
        /// 실물 대조 (`FixtureNumberingLabelRenderTests`).
        public static let fixedWidthEmRatio: CGFloat = 1.5
    }

    /// 수식 (eqed) 근사 조판
    public enum Equation {
        /// 한글.app은 수식 글리프를 선언 크기의 ~88.5%로 조판한다.
        /// 실측: 라운드 11 — 본문 대비 13% 과대 → 축소 계수.
        /// 검증: fidelity 전수 + 실물 대조.
        public static let glyphScale: CGFloat = 0.885
    }

    /// 각주/미주 배치
    public enum Footnote {
        /// 구분선 위 여백 기본값 (pt) — FootnoteShape의 marginTop이
        /// 없거나 0일 때. 한글 기본 각주 모양 근사.
        /// 검증: 각주 포함 픽스처 fidelity + 실물 대조.
        public static let dividerDefaultMarginTop: CGFloat = 8.5

        /// 구분선 아래 여백 기본값 (pt) — FootnoteShape의 marginBottom이
        /// 없거나 0일 때. 한글 기본 각주 모양 근사.
        /// 검증: 각주 포함 픽스처 fidelity + 실물 대조.
        public static let dividerDefaultMarginBottom: CGFloat = 5.7

        /// 각주 사이 간격 기본값 (pt) — FootnoteShape의
        /// spacingBetweenNotes가 없거나 0일 때. 한글 기본 각주 모양 근사.
        /// 검증: 각주 포함 픽스처 fidelity + 실물 대조.
        public static let dividerDefaultSpacingBetweenNotes: CGFloat = 2.8
    }
}
