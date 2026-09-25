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
        /// **글자처럼 취급 개체의 바깥 상자**(개체 + 바깥 여백)도 같은 비율로 놓인다 (#195,
        /// `HwpObjectAnchorGeometry.inlineAnchorOrigin`): 바깥 상자 상단에서 높이 × 0.85
        /// 내려간 자리가 줄 베이스라인이다 — 개체가 상자를 정한 줄에서는 상자 상단 = 개체
        /// 상단이고, 상자보다 작은 개체는 베이스라인 위로 0.85 × 높이만 올라간다. 한글.app
        /// 12.30.0 (2026-09-21) 실측: 함초롬바탕 40pt 줄의 4·8·20·30·36·40·50pt 그림 상단이
        /// 베이스라인 − 0.85 × 높이(3.49·6.85·16.93·25.57·30.62·33.98·42.62pt, 장치 양자화
        /// 0.12pt 안)였고 바깥 여백·상대 크기·줄 간격 종류·글꼴·표·도형·글상자·셀 안·쪽에
        /// 걸친 문단에서도 같았다.
        ///
        /// MS 워드 호환 문서(`HwpCompatibleDocumentTarget.msWord`, #194)에는 이 비율이
        /// 쓰이지 않는다 — 줄 상자와 베이스라인이 글꼴 줄 상자(`HwpMsWordLineBox`)이고
        /// (`HwpDrawnTextLayout.LineMetrics.baselineAnchor`) 개체 바깥 상자는 바닥이
        /// 베이스라인이다 (같은 실측, 함초롬돋움 40pt 줄의 같은 그림들이 베이스라인 − 높이;
        /// `LineMetrics.inlineObjectBaselineRatio` = 1).
        ///
        /// 검증: `HwpBaselineAnchorTests` 비율 + `FixtureBaselineAnchorTests` 캐시 대조 +
        /// `FixtureDecorationLineRenderTests` 픽셀 핀 + `HwpInlineObjectBaselineTests`(개체) +
        /// fidelity 전수.
        public static let baselineAnchorRatio: CGFloat = 0.85

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
        /// 한글 2007 호환 문서(`hwp200X`)도 중심은 이 배율 그대로이고 두께만 고정
        /// 0.36pt다 (#210 실측: 22개 크기에서 0.349~0.357).
        /// 곱하는 크기는 run 글꼴 크기가 아니라 **글자 모양 기본 크기**(슬롯 상대 크기
        /// 전)에 첨자 축소 비율만 곱한 값이다 (#226, 한글 12.30 실측 2026-09-22·25: 기본 40pt·
        /// 상대 크기 50% run의 취소선 +14.04pt(09-22 합성 표본)·+13.92pt(09-25
        /// `mixed-size-decorations` M8) = 40pt 자리, 기본 10pt·200%는 +3.48pt = 10pt 자리,
        /// 기본 20pt·상대 크기 50% 위 첨자는 옮겨진 베이스라인 위 4.44pt = 0.35 × 12.8(= 20 ×
        /// 0.64) — 상대 크기를 곱한 6.4pt 기준이면 2.24pt). 취소선은 밑줄과 달리 **run
        /// 단위**다 — 40pt 글자와 한 줄에 있는 10pt 취소선은 +3.48pt에 남는다 (09-22).
        /// 검증: `FixtureDecorationLineRenderTests`(+`+Script`) 픽셀 핀 + fidelity 전수.
        public static let strikethroughCenterRatio: CGFloat = 0.35

        /// 밑줄 '글자 아래'(표 35 밑줄 종류 1)·변경 추적 삽입 밑줄의 **위 가장자리**가
        /// 놓이는 베이스라인 아래 깊이 = **줄 상자 높이** × 이 배율 — 곧 줄 상자의 바닥이다
        /// (`baselineAnchorRatio`와 상보: 1 − 0.85). 선은 그 가장자리에서 아래로 두께만큼
        /// 그려지므로 중심은 두께의 절반만큼 더 아래다 (`HwpDecorationLineGeometry.underlineBelow`).
        ///
        /// **밑줄은 줄 단위다** (#226, 한글 12.30.0 build 6446 실측 2026-09-22·25, `CharShape`
        /// HWPX 기반 합성 문서에서 `hp:linesegarray`를 지워 한글이 다시 조판한 PDF): 한 줄의
        /// 모든 밑줄이 그 줄 상자(한글 줄 캐시의 `vertsize`) 바닥에 붙는다. 10pt 밑줄 run이
        /// 40pt 무장식 글자·40pt 문단 끝 글자(CR)·40pt 한 줄 끝(코드 10)·40pt 글자 모양의
        /// 책갈피·높이 40pt인 글자처럼 취급 그림과 표 가운데 무엇과 같은 줄에 있든 위
        /// 가장자리가 베이스라인 아래 6.00pt(= 0.15 × 40)이고, 바깥 여백 위 7·아래 3pt를 준
        /// 20pt 그림 줄(상자 30pt)은 4.50pt, 40pt 글자 모양 마커의 8pt 그림과 20pt 글자가 있는
        /// 줄(상자 20pt — 마커는 #217로 빠지고 20pt 글자가 상자를 정한다)은 3.00pt다. 여러
        /// 줄로 접힌 문단은 줄마다 따로다. 한 크기만 있는 줄에서는
        /// 종전의 중심 −0.17em(#176: 5~100pt 13개 크기·네 글꼴에서 같은 값)이 곧 이 가장자리
        /// + 두께 절반(0.15 + 0.04 / 2)이다. 한글 2007 호환 문서(`hwp200X`)도 같은 가장자리에
        /// 고정 0.36pt 선을 얹는다 (#210: 22개 크기의 중심이 −(0.15em + 0.18pt)에 장치 양자화
        /// 0.12pt 안으로 들어맞는다 — 100pt −15.12·40pt −6.12·20pt −3.12·10pt −1.56; 고정 비율
        /// −0.1545em은 10개, −0.17em은 13개 크기에서 한 단위를 넘겨 어긋난다 — 종전
        /// `hwp200XUnderlineBelowEdgeRatio`). 두 갈래는 **가장자리가 같고 두께만 다르다**. 이 가장자리는
        /// 종전의 '키 큰 인라인 개체 줄의 밑줄 되돌림'(`underlineReturnDrop` — 공공누리
        /// 실물에서 밑줄이 개체 하단에 남는 현상)을 포함한다: 개체가 상자를 정한 줄의 상자
        /// 바닥이 곧 개체 **바깥 상자**(개체 + 바깥 여백)의 아랫변이다 (바깥 여백이 없으면 개체
        /// 하단). MS 워드 호환 문서는 글꼴 지표를 쓴다 — 아래 `msWord*` 상수.
        /// 첨자 run도 **원래 베이스라인** 기준이다 (#179 실측: 10pt 위/아래 첨자 모두 1.68pt
        /// 아래) — 취소선과 달리 첨자 이동을 따라가지 않는다.
        /// 검증: `HwpDecorationLineGeometryModelTests`·`HwpUnderlineReferenceTests` 모델 +
        /// `HwpDecorationLineGeometryTests`(+`+Script`·`+Hwp2007`·`+LineWide`) 래스터 +
        /// `FixtureDecorationLineRenderTests`(+`+LineWide`) 픽셀 핀 + fidelity 전수.
        public static let underlineBelowEdgeRatio: CGFloat = 0.15

        /// 밑줄 '글자 위'(표 35 밑줄 종류 3)의 **아래 가장자리**가 놓이는 베이스라인 위
        /// 높이 = **줄 상자 높이** × 이 배율 — 곧 줄 상자의 상단이다. 중심은 두께의 절반만큼
        /// 더 위다 (`HwpDecorationLineGeometry.underlineAbove`).
        /// 실측: 아래 밑줄과 같은 줄 단위 규칙이다 (#226: 10pt 위 밑줄이 40pt 무장식 글자·
        /// 40pt 문단 끝 글자·40pt 한 줄 끝·40pt 책갈피·40pt 그림과 표와 같은 줄이면 가장자리
        /// 34.00pt = 0.85 × 40, 상자 30pt 그림 줄은 25.50pt). 한 크기만 있는 줄의 종전 중심
        /// 0.87em(#136: `underline-above` 쌍 10/40/100pt에서 +8.76/34.68/86.88pt)이 곧 이
        /// 가장자리 + 두께 절반(0.85 + 0.04 / 2)이고, 한글 2007 호환 문서의 0.85em + 0.18pt
        /// (#210: 100pt +85.08·40pt +34.20·20pt +17.16 — 종전 `hwp200XUnderlineAboveEdgeRatio`)도
        /// 같은 가장자리다.
        /// 검증: 아래 밑줄과 같다.
        public static let underlineAboveEdgeRatio: CGFloat = 0.85

        /// 장식선(글자 아래·글자 위 밑줄, 취소선, 글자 가운데 밑줄) 두께 = 기준 크기 ×
        /// 이 배율 — 선 모양(점선·여러 줄·물결)의 축척도 같은 기준 크기다 (#191).
        /// 실측: 같은 세션 — 한글 PDF의 선 폭은 5·7·8·10·12·13·15·20·25·30·40·60·
        /// 100pt에서 0.24/0.24/0.36/0.36/0.48/0.48/0.60/0.84/0.96/1.20/1.56/2.40/
        /// 3.96pt로, 13개 전부 `0.12pt × round(크기 / 3)` = 0.04em을 600dpi 장치
        /// 단위로 반올림한 값이다. 밑줄과 취소선이 같은 폭이고 네 글꼴이 같다.
        /// 하한은 두지 않는다 — 한글도 5pt를 0.24pt로 그린다. 종전 0.4pt 고정은
        /// 10pt에서만 맞았다. 첨자 run에서도 **축소 전 크기** 기준이다 (#179 실측:
        /// 10pt 첨자의 네 선 모두 0.36pt = 본문과 같음).
        ///
        /// **기준 크기는 선마다 다르다** (#226 실측): 취소선은 그 run의 글자 모양 기본 크기
        /// (슬롯 상대 크기 전 — 기본 40pt·상대 크기 50%도 1.56pt), 밑줄 세 종은 **줄의 글자**
        /// 기본 크기 최댓값이다 — 10pt 밑줄이 40pt 무장식 글자·40pt 공백과 한 줄이면 1.56pt,
        /// 20pt 무장식 글자와 40pt 문단 끝 글자 줄이면 0.84pt(20pt)다. 문단 끝 글자·한 줄
        /// 끝·책갈피·개체 마커의 글자 모양과 개체 높이는 줄 상자(밑줄 자리)에는 들어도 이
        /// 크기에는 들지 않는다 (40pt인 그것들과 한 줄인 10pt 밑줄은 0.36pt). 기본 40pt 위
        /// 첨자 무장식 run이 든 줄은 1.56pt — 첨자 축소 전 기본 크기다. 점선 한 토막도 같은
        /// 기준이다 (40pt 무장식 글자 줄의 10pt 긴 점선이 11.40/6.96pt = 5q/3q, q = 0.057 ×
        /// 40; 40pt 문단 끝 글자 줄은 2.88/1.68pt = 10pt 몫).
        /// 검증: `HwpDecorationLineGeometryTests`(+`+Script`·`+LineWide`) 두께 비율 + fidelity 전수.
        public static let decorationLineThicknessRatio: CGFloat = 0.04

        /// MS 워드 호환 문서(`HwpCompatibleDocumentTarget.msWord`)의 줄 상자 높이 =
        /// CJK 글꼴의 (winAscent + winDescent) × 이 배율 (`HwpMsWordLineBox`, #187·
        /// #194). 장식선은 두 글꼴 갈래 모두 줄 상자 ÷ 이 배율을 기준 상자로 쓰고, 세로
        /// 배치(#194)는 줄 상자 자체를 줄 캐시의 `vertsize`로 쓴다.
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

        /// 한글 2007 호환 문서(`HwpCompatibleDocumentTarget.hwp200X`)의 장식선 두께
        /// (pt) — 글자 아래·위 밑줄, 취소선(글자 가운데 밑줄), 변경 추적 삽입/삭제선이
        /// 모두 글자 크기와 **무관한 고정 pt**다.
        /// 실측: 한글 12.30.0 build 6446 (2026-09-22, #210) `CharShape` HWPX 기반 합성
        /// 문서(`targetProgram="HWP200X"`, `hp:linesegarray` 제거)를 PDF로 내보내 벡터
        /// 좌표를 읽었다 — 5·6·7·8·9·10·11·12·14·16·18·20·24·28·32·40·48·56·64·72·80·
        /// 100pt **22개 크기 전부 0.36pt**(600dpi 장치 단위 3개)이고 함초롬돋움·함초롬
        /// 바탕·Apple SD 산돌고딕 Neo·Helvetica·Times New Roman·Menlo·Courier New·
        /// Baskerville·궁서 9개 글꼴이 같다. 한글 문서의 `decorationLineThicknessRatio`
        /// (0.04em — 40pt에서 1.56pt)와 달리 크기를 따라가지 않는다. 쪽을 0.8배로 줄여
        /// 내보낸 변경 추적 표본의 0.24pt는 0.36 × 0.8 = 0.288이 장치 단위 2개로 떨어진
        /// 값이라 이 두께는 **쪽 좌표계의 길이**다.
        /// 검증: `HwpDecorationLineGeometryTests+Hwp2007` 두께 + `HwpRenderTuningTests`.
        public static let hwp200XDecorationLineThickness: CGFloat = 0.36
    }

    /// 선 모양 (표 25 `HwpBorderType`) — 밑줄·취소선·표 셀 테두리·단 구분선의 점선·파선·
    /// 원형 점선·여러 줄·물결 기하 (#191). 값은 전부 한글.app 12.30.0 (2026-09-17) PDF
    /// 내보내기의 벡터 좌표(600dpi = 0.12pt 정수 단위)에서 읽었다 — 글자선은 13종 ×
    /// 5·10·20·40·80pt × 밑줄/취소선/글자 위 밑줄, 테두리는 13종 × 표 26 굵기 16단(0.1~5mm,
    /// 위·왼쪽 변만 켠 셀), 단 구분선은 13종 × 0.1/0.4/1/3mm 합성 문서. 글자선과
    /// 테두리·구분선은 **같은 모양 표를 다른 축척**으로 그린다 — 글자선은 글자 크기(em)에,
    /// 테두리·구분선은 명목 두께(t, 표 26 mm)에 비례한다. `HwpLineShapeGeometry`가 이
    /// 상수로 경로를 만든다. 3D 넷(`thick3D`·`thick3DReverse`·`single3D`·
    /// `single3DReverse`)은 한글 macOS가 글자선·테두리 모두 **아무것도 그리지 않는다**
    /// (같은 실측: PDF 벡터 0건, 한글이 만든 PrvImage에도 없음) — 여기서는 실선으로 대체한다.
    /// 검증: `HwpLineShapeGeometryTests` + `FixtureLineShapeRenderTests` 픽셀 핀 + fidelity 전수.
    public enum LineShape {
        /// 글자선(밑줄·취소선) 대시 패턴의 단위 길이 = 글자 크기 × 이 배율 (0.057em =
        /// 0.04em 두께의 1.425배). 패턴은 단위의 배수다: 긴 점선(`longDotLine`) 5·공백 3,
        /// 점선(`dotLine`) 1·공백 1.5, 일점쇄선 10·3·1·3, 이점쇄선 10·3·1·3·1·3, 긴 파선 10·3.
        /// 실측: 80pt 긴 점선 22.8/13.68pt(190u/114u) = 5·3 × 38u, 40pt 점선 2.28/3.48pt
        /// (19u/29u) = 1·1.5 × 19u, 20pt 긴 파선 11.4/3.36pt = 10·3 × 9.5u; 5·10pt는 정수화로
        /// ±1u. 밑줄·취소선·글자 위 밑줄이 같은 값이다. 패턴은 run 시작에서 선으로
        /// 시작하고 글자 모양 run마다 다시 시작한다.
        public static let characterDashUnitEmRatio: CGFloat = 0.057

        /// 테두리·단 구분선 대시 패턴의 단위 길이 = 명목 두께 × 이 배율 (22/15). 패턴 배수는
        /// 글자선과 같다. 실측: 5mm(118.11u) 점선 선 173u·공백 259u, 긴 점선 866u·519u,
        /// 긴 파선 1732u·519u = 1·1.5·5·3·10·3 × 173.2u; 1mm 35u·52u; 0.12mm 4u·6u.
        /// 글자선의 1.425와 3% 다르다 — 두 축이 다른 그리기 루틴이다.
        public static let borderDashUnitThicknessRatio: CGFloat = 22.0 / 15.0

        /// 글자선 원형 점선(`circle`)의 원 지름 = 대시 단위(`characterDashUnitEmRatio`),
        /// 원 중심 간격 = 지름 × 이 배율. 채운 원이고 첫 원의 중심이 run 시작 x다.
        /// 실측: 80pt 지름 4.56pt(38u)·피치 11.4pt(95u), 40pt 2.4/5.76pt, 20pt 1.2/3.0pt.
        public static let characterCirclePitchDiameterRatio: CGFloat = 2.5

        /// 테두리·단 구분선 원형 점선의 원 지름 = 명목 두께, 원 중심 간격 = 두께 × 이 배율.
        /// 첫 원의 중심은 선 시작(셀 모서리 − 두께/2)이다. 실측: 5mm 지름 118u·피치 236u,
        /// 1mm 24u·48u, 0.12mm 4u·6u(정수화).
        public static let borderCirclePitchThicknessRatio: CGFloat = 2

        /// 글자선 2중선(`doubleLine`)의 띠 높이 = 글자 크기 × 이 배율 (= 두께 0.04em의 3배).
        /// 띠 안 구성은 [1/4 선, 1/2 공백, 1/4 선]. 실측: 40pt 선 1.2pt 둘의 중심 간격 3.6pt
        /// (띠 4.8pt = 0.12em), 20pt 0.6pt·1.8pt, 10pt 0.24pt·0.72pt.
        public static let characterDoubleLineBandEmRatio: CGFloat = 0.12

        /// 글자선 가는+굵은(`thinThickDoubleLine`)·굵은+가는·가는+굵은+가는(`thinThickThinTripleLine`)
        /// 의 띠 높이 = 글자 크기 × 이 배율 (= 두께의 5배). 띠 안 구성은 테두리와 같은
        /// [1/4, 1/4 공백, 1/2]·[1/2, 1/4 공백, 1/4]·[1/6, 1/6, 1/3, 1/6, 1/6]. 실측: 40pt
        /// 가는+굵은 1.92pt + 공백 1.88 + 4.08pt = 7.9pt(0.197em), 3중선 1.32·1.38·2.64·1.26·
        /// 1.32pt = 7.9pt; 20pt 0.96+0.9+2.04 = 3.9pt.
        public static let characterThickBandEmRatio: CGFloat = 0.2

        /// 글자선 물결(`wave`·`doubleWave`)의 진폭(꼭짓점 사이 세로 거리) = 글자 크기 × 이
        /// 배율 (= 두께의 2.8배). 파는 45° 지그재그라 반주기도 같은 값이다. 실측: 80pt
        /// 꼭짓점 세로 9.0pt·가로 9.0pt(75u), 40pt 4.56/4.56pt, 20pt 2.28pt, 10pt 1.08pt.
        public static let characterWaveAmplitudeEmRatio: CGFloat = 0.112

        /// 글자선 물결의 획 두께 = 글자 크기 × 이 배율 (= 두께의 3/4, 2중선의 가는 선과 같다).
        /// 실측: 80pt 2.28pt(19u), 40pt 1.2pt, 20pt 0.6pt, 10pt 0.24pt.
        public static let characterWaveStrokeEmRatio: CGFloat = 0.03

        /// 글자선 2중 물결의 둘째 파 = 첫째 파를 진폭 × 이 배율만큼 아래로 옮긴 것 (x 위상은
        /// 같다). 실측: 40pt 3.6pt/4.56pt = 0.79, 20pt 1.8/2.28 = 0.79, 10pt 0.72/0.96 = 0.75.
        public static let characterDoubleWaveOffsetAmplitudeRatio: CGFloat = 0.8

        /// 글자선 물결 꼭짓점 띠의 **위쪽** 꼭짓점 = 단선 띠의 위 가장자리에서 두께 × (이 값 ×
        /// 밑줄 종류) 만큼 위 — 종류는 글자 아래 밑줄 1, 취소선(글자 가운데) 2, 글자 위 밑줄
        /// 3이고 띠는 거기서 진폭만큼 아래로 내려온다. 실측(20pt, 베이스라인 기준 위 양수):
        /// 아래 밑줄 꼭짓점 −0.108~−0.216em(단선 위 가장자리 −0.15em + 0.042), 취소선
        /// 0.342~0.45em(0.37 + 0.08), 위 밑줄 0.90~1.008em(0.89 + 0.118) — 세 종류가 0.04em씩
        /// 계단으로 올라간다 (10·40·80pt 같음). 2중 물결도 같은 위쪽 꼭짓점을 쓴다.
        public static let characterWaveTopShiftThicknessRatio: CGFloat = 1

        /// 테두리·단 구분선 물결의 진폭 = 명목 두께 (45° 지그재그, 반주기도 두께), 획 두께 =
        /// 두께 × 이 배율 (2중선의 가는 선과 같다). 실측: 5mm 꼭짓점 세로 118u·가로 118u·
        /// 획 30u, 1mm 24u·6u, 0.12mm 3u·1u.
        public static let borderWaveStrokeThicknessRatio: CGFloat = 0.25

        /// 테두리·단 구분선 물결의 꼭짓점 띠 중심이 선 중심(셀 모서리·간격 중앙)에서 **−x/−y**
        /// 쪽으로 옮겨진 거리 = 두께 × 이 배율 (3/8). 위·아래·왼·오른 테두리와 단 구분선이
        /// 모두 같은 방향이다 (바깥쪽이 아니다). 실측: 4mm 위 테두리 꼭짓점 71~167u(모서리
        /// 83u 기준 −0.38t), 왼 테두리 −84~+11u, 3mm 단 구분선 중심 −27u(−0.38t), 0.12mm
        /// 표 행의 위·아래·왼·오른 테두리 −1~−2u.
        public static let borderWaveShiftThicknessRatio: CGFloat = 0.375

        /// 테두리·단 구분선 2중 물결의 둘째 파 = 첫째 파를 가로지르는 축으로 두께 × 이 배율
        /// 옮긴 것 — 첫째 파와 합쳐 선 중심에 대칭인 [−7/8, +7/8] 띠가 된다. 선 방향으로는
        /// 테두리가 같은 배율(둘째 파의 첫 꼭짓점이 첫 파 시작 + 3t/4 — 내려가는 획이 첫 파의
        /// 내려가는 획과 한 직선을 이루는 마름모 격자), 단 구분선은 0(같은 x 위상)이다. 실측:
        /// 4mm 위 변 둘째 파 꼭짓점 0~95u(첫째 72~167u, 72u = 0.76t), 첫 꼭짓점 x = 모서리
        /// − t/2 + 71u(t/2 연장 뒤 3t/4 = 71u); 3mm 구분선은 두 파가 같은 y에서 시작.
        public static let borderDoubleWaveOffsetThicknessRatio: CGFloat = 0.75

        /// 물결 꼭짓점 사이의 평탄 구간 (pt) — 한글은 600dpi 정수 좌표로 꼭짓점을 잡아
        /// 대각선 사이에 1단위(0.12pt) 평탄이 생기고 반주기가 진폭보다 그만큼 길다 (실측:
        /// 모든 크기·굵기에서 대각선 시작 간격 = 진폭 + 1u). 주기를 맞추려고 그대로 둔다.
        public static let waveVertexFlat: CGFloat = 0.12
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
