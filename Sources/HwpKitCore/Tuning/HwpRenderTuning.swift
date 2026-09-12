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
        /// 한글 줄 모델의 베이스라인 앵커 비율 — 텍스트든 개체든
        /// 베이스라인을 칸 높이의 ~0.85 지점에 둔다.
        /// 실측: 공공누리 실물 0.859. 검증: fidelity 전수 + 실물 대조.
        public static let baselineAnchorRatio: CGFloat = 0.85

        /// 키 큰 인라인 개체 (run delegate) 줄에서 베이스라인을 들어올리는
        /// 개체 ascent 비율. `baselineAnchorRatio`와 상보 관계 (1 − 0.85)
        /// 이지만 독립 실측값으로 별도 고정한다.
        /// 실측: 공공누리 실물 (밑줄 되돌림 양도 동일 비율).
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
        /// 값**이다 (#136).
        /// 검증: `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let strikethroughCenterRatio: CGFloat = 0.35

        /// 밑줄 '글자 위'(표 35 밑줄 종류 3) 중심의 베이스라인 위 높이 =
        /// 글자 크기 × 이 배율.
        /// 실측: 같은 세션의 `underline-above` 쌍 — 10/40/100pt에서
        /// +8.76/34.68/86.88pt (0.867~0.876). 함초롬돋움도 같은 값이다 (#136).
        /// 검증: `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let underlineAboveCenterRatio: CGFloat = 0.87

        /// 변경 추적 삭제선 중심의 베이스라인 위 높이 = 글자 크기 × 이 배율.
        /// 실측: 같은 세션의 `track-changes` 실물 — 10pt에서 +2.40pt, 40pt에서
        /// +9.24pt (0.303·0.292, 두 표본 잔차 ≤0.11pt; 한글은 변경 내용 추적 문서를
        /// PDF로 내보낼 때 쪽 전체를 약 0.8배로 줄이므로 글리프가 7.92·31.68pt로
        /// 찍히지만 em 비율은 그대로다).
        ///
        /// **이 값은 변경 추적 고유의 기하가 아니라 MS Word 호환 문서의 취소선
        /// 기하다** (2026-09-12 실측, #176). `track-changes` 픽스처는 호환 문서
        /// 대상 프로그램 2(`CT_MSWORD`)인데, 같은 본문을 네이티브(`HWP201X`)로
        /// 저장하면 한글은 삭제선을 일반 취소선과 같은 자리(+0.35em)에 그리고,
        /// 호환 문서에서는 일반 취소선도 이 자리(함초롬 +0.29em, Apple SD +0.25em,
        /// HY울릉도M +0.23em — 글꼴 지표 의존)에 그린다. 호환 모드 분기는 #187로
        /// 분리했고, 그때까지는 코퍼스의 유일한 변경 추적 실물에 맞춘 이 값을 쓴다.
        /// 검증: `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let trackChangeStrikethroughCenterRatio: CGFloat = 0.29

        /// 밑줄 '글자 아래'(표 35 밑줄 종류 1) 중심의 베이스라인 **아래** 깊이 =
        /// 글자 크기 × 이 배율.
        /// 실측: 한글.app 12.30.0 (2026-09-12, #176) `CharShape` HWPX 기반 합성
        /// 문서(`hp:linesegarray` 제거)를 PDF로 내보내 벡터 좌표를 읽었다 — 5·7·8·
        /// 10·12·13·15·20·25·30·40·60·100pt에서 베이스라인 대비 −0.84/1.08/1.32/
        /// 1.68/2.04/2.28/2.52/3.48/4.32/5.16/6.84/10.20/17.04pt (선언 크기 대비
        /// 0.154~0.175, 장치 좌표 0.12pt 양자화; 60pt 이상은 정확히 0.170). 함초롬바탕·함초롬돋움·
        /// Apple SD 산돌고딕 Neo·HY울릉도M 네 글꼴이 **모든 크기에서 같은 값**이라
        /// descent·post `underlinePosition` 같은 글꼴 지표가 아니라 글자 크기
        /// 비례다. 네이티브 문서의 변경 추적 삽입 밑줄도 이 자리다 (#187 참고).
        /// 검증: `HwpDecorationLineGeometryTests` 비율 +
        /// `FixtureDecorationLineRenderTests` 픽셀 핀 + fidelity 전수.
        public static let underlineBelowCenterRatio: CGFloat = 0.17

        /// 장식선(글자 아래·글자 위 밑줄, 취소선, 글자 가운데 밑줄) 두께 = 글자
        /// 크기 × 이 배율.
        /// 실측: 같은 세션 — 한글 PDF의 선 폭은 5·7·8·10·12·13·15·20·25·30·40·60·
        /// 100pt에서 0.24/0.24/0.36/0.36/0.48/0.48/0.60/0.84/0.96/1.20/1.56/2.40/
        /// 3.96pt로, 13개 전부 `0.12pt × round(크기 / 3)` = 0.04em을 600dpi 장치
        /// 단위로 반올림한 값이다. 밑줄과 취소선이 같은 폭이고 네 글꼴이 같다.
        /// 하한은 두지 않는다 — 한글도 5pt를 0.24pt로 그린다. 종전 0.4pt 고정은
        /// 10pt에서만 맞았다.
        /// 검증: `HwpDecorationLineGeometryTests` 두께 비율 + fidelity 전수.
        public static let decorationLineThicknessRatio: CGFloat = 0.04

        /// 변경 추적 삽입 밑줄 중심의 베이스라인 아래 깊이 = 글자 크기 × 이 배율.
        /// 실측: `track-changes` 실물 (2026-09-08·09-12) — 선언 10pt·40pt가 PDF
        /// 쪽 축소로 7.92·31.68pt 글리프로 찍히고 밑줄 중심은 그 아래 2.04·8.16pt
        /// (둘 다 −0.2576em). 종전
        /// 구현은 0.75pt 사각형의 **아래 모서리**를 −0.35em에 두어 중심이 크기에
        /// 비례하지 않았다 (10pt −0.31em·40pt −0.34em).
        /// `trackChangeStrikethroughCenterRatio`와 같은 사정으로 **MS Word 호환
        /// 문서의 밑줄 기하**다 — 네이티브 문서에서는 삽입 밑줄이 일반 밑줄
        /// (`underlineBelowCenterRatio`·`decorationLineThicknessRatio`)과 같은
        /// 자리·두께이고, 호환 문서에서는 일반 밑줄도 이 자리다 (함초롬 −0.258em·
        /// Apple SD −0.326em·HY울릉도M −0.167em, #187).
        /// 검증: `HwpDecorationLineGeometryTests` 비율 +
        /// `FixtureDecorationLineRenderTests` 픽셀 핀.
        public static let trackChangeInsertUnderlineCenterRatio: CGFloat = 0.26

        /// 변경 추적 삽입 밑줄 두께 = 글자 크기 × 이 배율.
        /// 실측: 같은 실물 — 글리프 7.92pt에서 0.48pt(0.0606em), 31.68pt에서
        /// 2.04pt(0.0644em); 0.064em은 두 값을 한글의 0.12pt 장치 단위로 반올림해
        /// 그대로 재현한다(4·17단위). 일반 선(0.04em)보다 굵다. 이것도 MS Word 호환
        /// 문서의 밑줄 두께다 (함초롬 0.064em·Apple SD 0.061em·HY울릉도M 0.049em ≈
        /// 0.05 × 글꼴 줄 높이, #187). 종전 0.75pt 고정은 선언 10pt(0.64pt)에서는
        /// 굵고 40pt(2.56pt)에서는 가늘었다.
        /// 검증: `HwpDecorationLineGeometryTests` 두께 비율.
        public static let trackChangeInsertUnderlineThicknessRatio: CGFloat = 0.064
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
