import CoreGraphics
import Foundation

/// 한글.app 실물 대조로 확정한 렌더 튜닝 상수의 단일 소스.
///
/// 규약: 각 상수는 ① 값 ② 실측 근거 (픽스처/실물) ③ 검증 방법을
/// doc-comment로 갖는다. 값 변경은 fidelity 전수 + 블록 스냅샷 + 실물
/// 대조가 필수이고, `HwpRenderTuningTests`의 값 핀도 함께 갱신해야 한다.
///
/// 여기 없는 실측 상수: `HwpChartPainter`의 차트 투영 기하 (상호 결합
/// 실측 모델이라 in-place 유지), `HwpPaginator`의 각주 예약 근사 (산식
/// 교체 예정).
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
