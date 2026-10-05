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
        /// + 두께 절반(0.15em + 장치 단위 획 / 2 ≈ 0.02em — 10pt −1.68pt, #252)이다. 한글 2007
        /// 호환 문서(`hwp200X`)도 같은 가장자리에 고정 0.36pt 선을 얹는다 (#210: 22개 크기의
        /// 중심이 −(0.15em + 0.18pt)에 장치 양자화
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
        /// 가장자리 + 두께 절반(0.85em + 장치 단위 획 / 2 — 10pt +8.68·40pt +34.78pt, #252)이고,
        /// 한글 2007 호환 문서의 0.85em + 0.18pt
        /// (#210: 100pt +85.08·40pt +34.20·20pt +17.16 — 종전 `hwp200XUnderlineAboveEdgeRatio`)도
        /// 같은 가장자리다.
        /// 검증: 아래 밑줄과 같다.
        public static let underlineAboveEdgeRatio: CGFloat = 0.85

        /// 장식선 두께의 종전 연속 근사 — 0.18.0까지 글자 아래·위 밑줄·취소선·글자 가운데 밑줄의 두께가
        /// 기준 크기 × 이 배율이었고 물결 꼭짓점 계단도 이 배율로 쟀다. 지금은 어느 것도 이 값을 쓰지
        /// 않는다 (#252): 한글은 실선·대시 획을 기준 크기 X(HWPUNIT)에서
        /// max(1, round(round(X × 39/1000) ÷ 12))u(u = 0.12pt)로 긋고
        /// (`HwpDecorationLineGeometry.strokeThickness(referenceSize:)` — 10pt 0.36·5pt 0.24·56pt
        /// 2.16·80pt 3.12pt, 1.41pt 이하도 0.12pt), 여러 줄·물결도 장치 단위 정수 기하다
        /// (`HwpRenderTuning.LineShape.characterDoubleBandPerMille`·`characterThickBandPerMille`).
        /// #176이 이 배율의 근거로 든 13개 크기(5~100pt의 `0.12pt × round(크기 / 3)`)는 장치 단위 규칙과
        /// 같은 값이라 두 식을 가를 수 없었고, 56·80pt(18·26u — `round(크기 / 3)`이면 19·27u)가 반증한다.
        @available(
            *, deprecated,
            message: "장식선 획은 HwpDecorationLineGeometry.strokeThickness(referenceSize:)다 (#252)"
        )
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

        /// MS 워드 호환 문서의 밑줄 중심이 기준 상자 가장자리(글자 아래 밑줄은
        /// `descent`, 글자 위 밑줄은 `ascent`) 밖으로 나가는 거리 = 기준 상자 높이 ×
        /// 글자 크기 × 이 배율. 두께(줄 글자 상자 높이의 획 두께 — 상자의 약 0.05배,
        /// `HwpDecorationLineGeometry.strokeThickness(referenceSize:)`)와 함께 선 안쪽 가장자리가 상자
        /// 안으로 약 0.004 들어온다. 획 두께가 장치 단위로 반올림돼도 중심은 이 자리에 둔다 (#252
        /// 실측: 글꼴 6종 × 23크기 밑줄 중심이 이 자리와 0.16pt 안 — 장치 0.12pt 양자화).
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
        /// 크기 무관, 첨자는 `msWordScriptStrikethroughScale`배) × 이 배율.
        /// 실측: 같은 스윕 — 함초롬돋움 +0.2917em (÷ 1.07 = 0.2726), Apple SD 산돌고딕
        /// Neo +0.2481 (÷ 0.90 = 0.2757), HY울릉도M +0.2330 (÷ 0.8584 = 0.2714), 맑은 고딕
        /// +0.2973 (÷ 1.0884 = 0.2732), Menlo +0.2538 (÷ 0.9282 = 0.2734), Helvetica
        /// +0.2197 (÷ 0.8146 = 0.2697), Times New Roman +0.2159 (÷ 0.8009 = 0.2696),
        /// Courier New +0.1913 (÷ 0.7018 = 0.2726) — 0.267~0.278 (장치 양자화 ±0.003).
        /// `track-changes` 실물의 삭제선 +0.29em (#136·#176) 은 함초롬돋움의 이 값이다.
        /// 검증: `HwpDecorationLineGeometryTests+Compat` 위치 + `HwpRenderTuningTests`.
        public static let msWordStrikethroughAscentRatio: CGFloat = 0.273

        /// MS 워드 호환 문서에서 위·아래 첨자 run의 취소선(글자 가운데 밑줄 포함)이 첨자로
        /// 옮겨진 베이스라인 위로 오르는 높이 ÷ 같은 글꼴·기본 크기의 보통 글자 취소선이 베이스라인
        /// 위로 오르는 높이 (#248). 한글 문서 갈래는 이 비율로 첨자 글리프 축소 비율(0.64,
        /// `HwpTextRunBuilder.superscriptScale`)을 쓰고(#179 — 한글 실측은 0.636으로 그에 가깝다, #258)
        /// MS 워드 호환 문서는 확연히 크다 — 0.64로 그리면 함초롬바탕 40pt 위·아래 첨자 취소선이
        /// 한글보다 0.7pt 낮았다.
        /// 실측: 한글 12.30.0 build 6523 (2026-10-02) PDF 벡터 좌표 — `targetProgram="MS_WORD"`
        /// 합성 문서에서 글꼴 10종(함초롬바탕·Apple SD 산돌고딕 Neo·HY울릉도M·Menlo·Baskerville·
        /// Times New Roman·Helvetica·Courier New·Georgia·Arial) × 8~100pt 18단 × 위·아래 첨자의
        /// 실선 취소선 360표본. 글꼴별로 크기 20~100pt에서 맞춘 비율이 0.694~0.699이고(글꼴의
        /// 상자 모양과 무관 — 기준 상자 `descent`/`ascent`가 0.10인 Times New Roman과 0.36인
        /// Baskerville이 0.696·0.697), 360표본 전체에서 평균 잔차가 0이 되는 값이 0.696이다
        /// (최대 0.16pt, 장치 단위 0.12pt를 넘는 표본 15개 — 첨자 선·첨자 글리프 베이스라인·보통
        /// 선 세 좌표가 저마다 장치 좌표로 반올림된 합성 오차 범위다; 0.7이면 평균 0.03pt 높고
        /// 최대 0.22pt, 0.12pt를 넘는 표본이 28개다). 글리프 자체(0.64배·위 0.44em·아래 0.12em, #204)와 선 두께(축소 전
        /// 기본 크기의 장치 단위 획, #252)는 한글 문서와 같고, 상대 크기(50·70·150·200%)·글자 위치(±30%)·선
        /// 모양(원형 점선·긴 점선·점선·긴 파선·물결·2중선·가는+굵은 선·2중 물결)·글자 가운데 밑줄도
        /// 같은 비율을 따른다.
        /// 검증: `HwpDecorationLineGeometryTests+MsWordScript` + `ms-word-script-strikethrough`
        /// 픽스처 쌍 + `HwpRenderTuningTests`.
        public static let msWordScriptStrikethroughScale: CGFloat = 0.696

        /// 한글 2007 호환 문서(`HwpCompatibleDocumentTarget.hwp200X`)의 장식선 두께
        /// (pt) — 글자 아래·위 밑줄, 취소선(글자 가운데 밑줄), 변경 추적 삽입/삭제선이
        /// 모두 글자 크기와 **무관한 고정 pt**다.
        /// 실측: 한글 12.30.0 build 6446 (2026-09-22, #210) `CharShape` HWPX 기반 합성
        /// 문서(`targetProgram="HWP200X"`, `hp:linesegarray` 제거)를 PDF로 내보내 벡터
        /// 좌표를 읽었다 — 5·6·7·8·9·10·11·12·14·16·18·20·24·28·32·40·48·56·64·72·80·
        /// 100pt **22개 크기 전부 0.36pt**(600dpi 장치 단위 3개)이고 함초롬돋움·함초롬
        /// 바탕·Apple SD 산돌고딕 Neo·Helvetica·Times New Roman·Menlo·Courier New·
        /// Baskerville·궁서 9개 글꼴이 같다. 한글 문서의 장치 단위 획(40pt 13u = 1.56pt, #252 —
        /// `HwpDecorationLineGeometry.strokeThickness(referenceSize:)`)과 달리 크기를 따라가지
        /// 않는다. 쪽을 0.8배로 줄여 내보낸 변경 추적 표본의 0.24pt는 0.36 × 0.8 = 0.288이
        /// 장치 단위 2개로 떨어진 값이라 이 두께는 **쪽 좌표계의 길이**다.
        /// 검증: `HwpDecorationLineGeometryTests+Hwp2007` 두께 + `HwpRenderTuningTests`.
        public static let hwp200XDecorationLineThickness: CGFloat = 0.36
    }

    /// 선 모양 (표 25 `HwpBorderType`) — 밑줄·취소선·표 셀 테두리·단 구분선의 점선·파선·
    /// 원형 점선·여러 줄·물결 기하 (#191). 값은 전부 한글.app 12.30.0 (2026-09-17) PDF
    /// 내보내기의 벡터 좌표(600dpi = 0.12pt 정수 단위)에서 읽었다 — 글자선은 13종 ×
    /// 5·10·20·40·80pt × 밑줄/취소선/글자 위 밑줄, 테두리는 13종 × 표 26 굵기 16단(0.1~5mm,
    /// 위·왼쪽 변만 켠 셀), 단 구분선은 13종 × 0.1/0.4/1/3mm 합성 문서 (#252의 글자선 장치 단위
    /// 기하는 build 6523, 2026-10-03; 테두리·단 구분선의 여러 줄·물결은 build 6523, 2026-10-04). 한글은
    /// 고정 pt인 한글 2007 호환 문서의 글자선(#210·#227)을 빼면 모든 선 모양을 600dpi 장치 단위(0.12pt)의
    /// 정수로 그린다 — 대시(긴 점선·점선·쇄선·긴 파선)와 원형 점선의 선·공백 길이와 원의 지름·간격
    /// (#239·#245 — `HwpRenderTuning+DeviceUnit.swift`; 단 구분선과 셀 간격이 있는 표의 셀 테두리는 셀
    /// 간격이 없는 표의 셀 테두리가 아니라 글자선과 같은 점 무늬다, #243), 실선·대시 획 두께(#245·#252),
    /// 그리고 2중선·가는+굵은 선·3중선·물결·2중 물결의 부속선과 물결(`HwpLineShapeGeometry+DeviceBands.swift`).
    /// 여러 줄·물결의 장치 띠는 글자선이 기준 크기의 0.113·0.198em을 HWPUNIT·장치 단위로 차례로 반올림한
    /// 값이고 (#252), 표 셀 테두리·단 구분선이 같은 굵기 실선의 획이다 (#253). `HwpLineShapeGeometry`가 이
    /// 상수로 경로를
    /// 만든다. 3D 넷(`thick3D`·`thick3DReverse`·`single3D`·
    /// `single3DReverse`)은 한글 macOS가 글자선·테두리 모두 **아무것도 그리지 않는다**
    /// (같은 실측: PDF 벡터 0건, 한글이 만든 PrvImage에도 없음) — 여기서는 실선으로 대체한다.
    /// 검증: `HwpLineShapeGeometryTests` + `FixtureLineShapeRenderTests` 픽셀 핀 + fidelity 전수.
    public enum LineShape {
        /// 한글 2007 호환 문서 글자선 물결의 꼭짓점 사이 평탄 구간 (pt) — 한글은 600dpi 정수 좌표로
        /// 꼭짓점을 잡아 대각선 사이에 1단위(0.12pt) 평탄이 생기고 반주기가 진폭보다 그만큼 길다 (#227 실측:
        /// 2.88pt 진폭의 반주기 3.0pt, 1.44pt 진폭의 반주기 1.56pt). 장치 단위 물결(글자선·표 셀 테두리·단
        /// 구분선 — #252·#253)은 같은 1u 평탄을 `deviceUnit`으로 둔다.
        public static let waveVertexFlat: CGFloat = 0.12

        // MARK: 한글 2007 호환 문서의 글자선 (#227)

        // 한글 2007 호환 문서(`HwpCompatibleDocumentTarget.hwp200X`)의 밑줄·취소선 모양은
        // 한글 문서와 모양 표(대시 배수·띠 안 구성의 차례·물결의 45° 지그재그)는 같지만
        // **글자 크기와 무관한 고정 pt**로 그린다 — 선 두께가 고정 0.36pt인 것
        // (`Text.hwp200XDecorationLineThickness`, #210)과 같은 갈래다. 실측: 한글 12.30.0
        // build 6446 (2026-09-26) `CharShape` HWPX 사본에 `targetProgram="HWP200X"`를 적고
        // `hp:linesegarray`를 뺀 합성 문서를 PDF로 내보내 벡터 좌표(600dpi = 0.12pt 정수
        // 단위)를 읽었다 — 함초롬바탕 5·7·10·14·20·28·40·56·80·100pt × 16개 모양 × 글자
        // 아래 밑줄, 5·10·20·40·80pt × 글자 위·가운데 밑줄·취소선, 그리고 크기가 섞인 줄·상대
        // 크기 50%·200%·위 첨자·글꼴 넷(함초롬돋움·Apple SD 산돌고딕 Neo·Menlo·Times New
        // Roman)·한글 글자 표본 493개(3D 셋 포함 — 글자선의 4비트 모양 값에는 넷째 3D가 없다)가
        // **전부** 아래 상수에서 0.13pt(장치 한 단위) 안이다.
        // 같은 표본을 한글 문서(`HWP201X`)로 내보낸 대조군은 종전의 em 비례 모델 그대로다.
        // 무늬는 한글 문서처럼 글자 모양 run마다 다시 시작하고 한 글자 모양 안의 슬롯 전환은
        // 이어진다. 3D 넷은 이 갈래에서도 아무것도 그리지 않는다.
        // 검증: `HwpLineShapeGeometryTests+Hwp2007` +
        // `FixtureDecorationLineRenderTests+Hwp2007Shapes`.

        /// 한글 2007 호환 문서의 대시 패턴 단위 길이 (pt) — 배수는 한글 문서와 같다: 긴 점선
        /// 5·3, 점선 1·1.5, 일점쇄선 10·3·1·3, 이점쇄선 10·3·1·3·1·3, 긴 파선 10·3. 실측: 모든
        /// 크기에서 긴 점선 2.40/1.44pt, 점선 0.48/0.72pt, 일점쇄선 4.80/1.44/0.48/1.44pt, 긴 파선
        /// 4.80/1.44pt (한글 문서 40pt의 긴 점선은 11.40/6.96pt). 고정 두께 0.36pt의 4/3배다 —
        /// 한글 문서의 장치 단위 식(#245, `HwpLineShapeGeometry+Dashes.swift`)에 단위 4u를 넣은
        /// 값과 같다.
        public static let hwp200XDashUnit: CGFloat = 0.48

        /// 한글 2007 호환 문서의 원형 점선 — 원 지름 (pt). 한글은 지름 1.20pt 원을 채우고 0.12pt
        /// 윤곽을 둘러 그리므로 칠해지는 지름은 1.32pt다. 원 중심 간격은
        /// `hwp200XCirclePitch`, 첫 원의 중심은 run 시작 x이고 run 끝은 한글 문서와 같다 (#235).
        public static let hwp200XCircleDiameter: CGFloat = 1.32

        /// 한글 2007 호환 문서의 원형 점선 — 원 중심 간격 (pt). 실측: 모든 크기·종류에서 3.0pt.
        public static let hwp200XCirclePitch: CGFloat = 3.0

        /// 한글 2007 호환 문서의 원형 점선 — 원 중심이 단선 중심에서 **띠가 자라는 쪽**으로
        /// 옮겨진 거리 (pt): 글자 아래 밑줄은 아래로, 글자 위 밑줄은 위로, 취소선·글자 가운데
        /// 밑줄은 0. 실측(단선 참값 중심 대비): 아래 밑줄 0.18~0.30pt 아래(10개 크기 평균 0.24),
        /// 위 밑줄 0.13~0.26pt 위(5개 크기 평균 0.21), 취소선·가운데 밑줄 ±0.07pt.
        public static let hwp200XCircleCenterShift: CGFloat = 0.24

        /// 한글 2007 호환 문서의 2중선(`doubleLine`) 띠 높이 (pt) — 띠 안 구성은 한글 문서와
        /// 같은 [1/4 선, 1/2 공백, 1/4 선]이라 0.36pt 선 둘의 중심이 1.08pt 떨어진다. 띠의 자리는
        /// 한글 문서와 같은 `Placement` 규칙이다 (아래 밑줄은 단선 위 가장자리에서 아래로 —
        /// 첫 선이 단선 자리 그대로다). 실측: 모든 크기에서 두께 0.36/0.36, 중심 간격 1.08pt
        /// (한글 문서 40pt는 1.20/1.20·3.60).
        public static let hwp200XDoubleLineBand: CGFloat = 1.44

        /// 한글 2007 호환 문서의 가는+굵은·굵은+가는·가는+굵은+가는 띠 높이 (pt). 띠 안 구성은
        /// 한글 문서와 다르다 — 가는+굵은 [0.96 선, 0.96 공백, 2.28 선](8/35·8/35·19/35),
        /// 굵은+가는은 그 거울, 3중선 [0.6, 0.6, 1.8, 0.6, 0.6](1/7·1/7·3/7·1/7·1/7). 실측: 모든
        /// 크기에서 가는+굵은 0.96·0.90·2.28(4.14), 굵은+가는 2.28·1.02·0.96(4.26) — 둘의
        /// 0.06pt 비대칭은 한글의 장치 단위 반올림이다 — 3중선 0.60·0.60·1.80·0.60·0.60(4.20).
        public static let hwp200XThickLineBand: CGFloat = 4.2

        /// 한글 2007 호환 문서의 물결(`wave`) 진폭 (pt) — 45° 지그재그라 반주기는 여기에
        /// `waveVertexFlat`을 더한 3.0pt다. 실측: 모든 크기에서 꼭짓점 세로·가로 2.88pt.
        public static let hwp200XWaveAmplitude: CGFloat = 2.88

        /// 한글 2007 호환 문서의 물결 획 두께 (pt) — 실측 0.72pt (고정 두께의 2배).
        public static let hwp200XWaveStroke: CGFloat = 0.72

        /// 한글 2007 호환 문서의 물결 위쪽 꼭짓점 = 단선 중심에서 `hwp200XWaveTopBase` + 이 값 ×
        /// 밑줄 종류(글자 아래 1·취소선과 글자 가운데 2·글자 위 3)만큼 위 — 종전 한글 문서 모델의
        /// 계단(단선 위 가장자리 + 두께 × 종류)과 같은 꼴에 기점·계단 폭만 고정이다 (한글 문서는 #252부터
        /// 띠 가운데에서 푼 장치 단위 기하다). 실측(모델 참값 단선 중심
        /// 대비, 크기별 평균): 아래 밑줄 1.32pt·취소선 2.49pt·위 밑줄 3.71pt 위 — 모델 1.32·2.52·
        /// 3.72 (같은 크기 실측 실선 대비로는 5개 크기 모두 취소선 2.52·위 밑줄 대개 3.72).
        public static let hwp200XWaveTopStep: CGFloat = 1.2

        /// 한글 2007 호환 문서의 물결 꼭짓점 계단이 시작하는 자리 (단선 중심 위, pt) —
        /// `hwp200XWaveTopStep` 참조. 단선 위 가장자리(0.18pt)보다 0.06pt 낮다 — 기점을 가장자리로
        /// 두면 세 종류 모두 한글보다 0.06~0.09pt 높다 (#227 리뷰).
        public static let hwp200XWaveTopBase: CGFloat = 0.12

        /// 한글 2007 호환 문서의 2중 물결(`doubleWave`) 진폭 (pt) — 단일 물결의 절반이고 반주기는
        /// 1.56pt다. 둘째 파는 `hwp200XDoubleWaveOffset`만큼 아래, 같은 x 위상이다.
        public static let hwp200XDoubleWaveAmplitude: CGFloat = 1.44

        /// 한글 2007 호환 문서의 2중 물결 획 두께 (pt) — 실측 0.36pt (고정 두께와 같다).
        public static let hwp200XDoubleWaveStroke: CGFloat = 0.36

        /// 한글 2007 호환 문서의 2중 물결 둘째 파의 아래 이동 (pt) — 실측 1.08pt (진폭의 3/4;
        /// 한글 문서는 획의 3배, #252).
        public static let hwp200XDoubleWaveOffset: CGFloat = 1.08

        /// 한글 2007 호환 문서의 2중 물결 위쪽 꼭짓점 = 단선 중심에서 `hwp200XDoubleWaveTopBase`
        /// + 이 값 × 밑줄 종류만큼 위 (`hwp200XWaveTopStep`과 같은 꼴, 기점·계단 폭만 다르다) —
        /// 단일 물결과 같은 꼭짓점을 쓰는 한글 문서와 다르다. 실측(같은 크기 실측 실선 대비):
        /// 0.72pt(아래 밑줄)·1.32pt(취소선)·1.80pt(위 밑줄), 참값 중심 대비 크기별 평균 0.77·1.29·
        /// 1.79pt — 꼭짓점 띠(2.52pt)가 아래 밑줄에서는 단선 중심 위 0.72pt부터 내려오고 위
        /// 밑줄에서는 그 거울, 취소선에서는 가운데다.
        public static let hwp200XDoubleWaveTopStep: CGFloat = 0.54

        /// 한글 2007 호환 문서의 2중 물결 꼭짓점 계단이 시작하는 자리 (단선 중심 위, pt) — 단선
        /// 위 가장자리(두께 절반)와 같은 값이다. `hwp200XDoubleWaveTopStep` 참조.
        public static let hwp200XDoubleWaveTopBase: CGFloat = 0.18
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
