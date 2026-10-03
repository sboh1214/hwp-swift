import CoreGraphics

// MARK: - 빈칸 폭 (#249, 본체 파일 길이를 지키려 확장으로 둔다)

public extension HwpRenderTuning.Text {
    /// 고정 빈칸 폭의 비율 — '글꼴에 어울리는 빈칸'(표 35 bit 25)이 꺼진 보통 빈칸과
    /// 묶음 빈칸(제어 문자 30)의 폭은 **한글 슬롯** 글자 크기(기본 크기 × 한글 상대 크기)
    /// × 이 비율 × 한글 장평이다 (#249, `HwpSpaceWidthMetrics.fixedWidth`). 빈칸 자신의
    /// 슬롯(라틴)이 아니다 — 빈칸 앞뒤가 무엇이든, 빈칸을 그리는 글꼴이 무엇이든 같다.
    /// 실측: 한글 12.30.0 build 6523 (2026-10-03) `CharShape` HWPX 기반 합성 문서(20pt,
    /// `hp:linesegarray` 제거)를 PDF로 내보내 빈칸 원점 → 다음 글자 원점 거리를 읽었다 —
    /// 한글 50%·라틴 100%이면 5.04·4.92pt(라틴 슬롯의 절반 10pt가 아니다), 한글 100%·라틴
    /// 50%이면 9.96pt, 한글 장평 50%이면 5pt이고 라틴 장평·한자·기호·일어 슬롯 상대 크기는
    /// 무관하다. 한글 문서·한글 2007 호환 문서·MS 워드 호환 문서(라틴 부류 사이가 아닌
    /// 빈칸, `HwpSpaceWidthMetrics.usesFontWidth`)가 같은 값이다.
    /// 한글은 여기에 라틴 자간을 폭의 %로 더 붙이지만 조판은 고정 폭 빈칸에 자간을 넣지 않는다
    /// (종전과 같다 — 글자 자간과 한 모델로 바꿀 일이다, `HwpSpaceWidthMetrics`·#260).
    /// 검증: `HwpSpaceWidthTests` + `space-width`·`ms-word-space-width` 픽스처 쌍 +
    /// `HwpRenderTuningTests`.
    static let fixedSpaceEmRatio: CGFloat = 0.5

    /// 고정폭 빈칸(제어 문자 31)의 폭 비율 — 한글 슬롯 글자 크기 × 이 비율 × 한글 장평이다
    /// (#249). 이름과 달리 묶음 빈칸(0.5)의 절반이다.
    /// 실측: 한글 12.30.0 build 6523 (2026-10-03) — 20pt 함초롬바탕 4.96pt, 한글 50%·라틴
    /// 100%이면 2.52pt, 한글 100%·라틴 50%이면 5.04pt, 한글 장평 50%이면 2.52pt(라틴 장평·
    /// 한글 자간은 무관)이고 문서 갈래·'글꼴에 어울리는 빈칸'과 무관하다. 라틴 자간 20%이면
    /// 6.0pt라 보통 빈칸처럼 자간이 붙는데, 그 몫은 아직 조판하지 않는다 (`fixedSpaceEmRatio`·#260).
    /// 검증: `HwpSpaceWidthTests` + `HwpRenderTuningTests`.
    static let fixedWidthSpaceEmRatio: CGFloat = 0.25
}
