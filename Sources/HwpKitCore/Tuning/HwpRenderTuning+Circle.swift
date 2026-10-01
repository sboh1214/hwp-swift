import CoreGraphics

// MARK: - 원형 점선 (본체 파일 길이를 지키려 확장으로 둔다)

public extension HwpRenderTuning.LineShape {
    // 원형 점선(`circle`)의 원은 대시처럼 글자 크기·두께에 비례하지 않고 **600dpi 장치
    // 단위(`deviceUnit`, 0.12pt)의 정수**로 그린다 — 한글이 원의 크기와 간격을 장치 단위로
    // 반올림하기 때문이다. 비례로 두면 원마다 차가 쌓여 긴 run의 원 개수가 한글과 갈린다 (12pt
    // 간격 1.71pt vs 한글 1.80pt). 갈래는 둘이다. **점 무늬** — 한글 문서·MS 워드 호환 문서의
    // 글자선, 단 구분선, 셀 간격이 있는 표의 셀 테두리(#243)는 점선(1·1.5)의 점을 원으로 그린다:
    // 점 단위 q = 무늬 두께 × 22/15(대시 단위와 같다)를 장치 단위로 반올림하고, 간격 = max(q, 3u) +
    // max(1.5q 반올림, 2u), 원 경로 지름 = q를 짝수로 올린 값(최소 2u)이다. 무늬 두께는 대시와 같다 —
    // 글자선은 글자 크기(HWPUNIT) × 0.039를 반올림한 값, 단 구분선·셀 테두리는 표 26 굵기마다의 값
    // (`characterPatternThicknessPerMille`·`borderPatternHwpUnits` — `+DeviceUnit` 확장). **격자** —
    // 셀 간격이 없는 표의 셀 테두리는 무늬 두께를 장치 단위로 반올림한 r(최소 1u)이 단위라 간격 2r,
    // 경로 지름은 r을 짝수로 올린 값이다. 어느 갈래든 한글은 원 경로를 채우고 한 단위 윤곽을 둘러
    // 칠하므로 칠 지름 = 경로 지름 + 1u다 (한글 2007 호환 문서의 1.32pt = 1.20 + 0.12와 같은 구성). 첫 원의 중심은 선 시작이고 끝 규칙은
    // #235·#238 그대로다 — 한글 2007 호환 문서는 고정 pt(`hwp200XCircle*`)라 이 규칙 밖이다.
    // 실측: 한글 12.30.0 build 6446 (2026-09-27) PDF 내보내기의 벡터 좌표 — 한글 문서 취소선
    // 1~100pt 1,010개(1~12pt 0.1pt 간격, 전환점 둘레 0.01~0.02pt 간격)·밑줄 217개(줄 기본 크기)·상대
    // 크기·위 첨자·크기가 섞인 줄·MS 워드 호환 문서 취소선 5~80pt, 단 구분선과 표 셀 테두리의 표 26
    // 굵기 16단(0.1~5mm)이 아래 식과 전부 같다 (셀 간격이 있는 표의 셀 테두리 16단은 2026-09-28 —
    // 셀 간격 283·1HWPUNIT 모두 단 구분선 값과 같다, #243). 원 중심의 세로 자리는 선 중심 ±1u다.
    // 검증: `HwpLineShapeGeometryTests+Circles` + `FixtureLineShapeRenderTests+RunEnd` +
    // `FixtureTableBorderChainTests` + `FixtureTableCellSpacingTests`.

    /// 글자선·단 구분선 원형 점선의 빈칸 = 점 단위 × 이 배율을 장치 단위로 반올림 — 점선(`dotLine`)
    /// 무늬 1·1.5의 빈칸이다. 원 중심 간격 = 점(`circleMinimumDotDeviceUnits` 이상) + 빈칸
    /// (`circleMinimumGapDeviceUnits` 이상)이라 점 단위 3u 이상에서는 2.5q를 반올림한 값이다.
    /// 실측(간격, u): 7·10·12·16·20·40·80pt → 8·13·15·20·25·48·95; 단 구분선 0.4·1·2mm → 35·88·173.
    static let circleGapDotUnitRatio: CGFloat = 1.5

    /// 글자선·단 구분선 원형 점선 간격의 점 몫 하한 (장치 단위) — 점 단위 0·1·2u(약 5.25pt
    /// 이하 글자)에서도 간격은 5·5·6u다 (실측: 1.00~3.20pt 5u, 3.22~5.24pt 6u).
    static let circleMinimumDotDeviceUnits: CGFloat = 3

    /// 글자선·단 구분선 원형 점선 간격의 빈칸 몫 하한 (장치 단위) — `circleMinimumDotDeviceUnits`
    static let circleMinimumGapDeviceUnits: CGFloat = 2

    /// 글자선·단 구분선 원형 점선의 원 경로 지름 하한 (장치 단위) — 점 단위를 짝수로 올린 경로
    /// 지름이 5.24pt 이하 글자에서도 2u다 (실측: 1~5.24pt 경로 2u, 5.26pt부터 4u).
    static let circleMinimumPathDeviceUnits: CGFloat = 2

    /// 원형 점선 원의 윤곽 (장치 단위) — 한글은 원 경로를 채우고 이 굵기의 윤곽을 둘러 그린다
    /// (실측: 모든 크기·굵기에서 0.12pt). 칠 지름 = 경로 지름 + 이 값.
    static let circleOutlineDeviceUnits: CGFloat = 1

    /// 셀 간격이 없는 표의 셀 테두리 원형 점선의 원 중심 간격 = 두께(HWPUNIT으로 반올림)를 장치
    /// 단위로 반올림한
    /// r(최소 1u) × 이 배율,
    /// 원 경로 지름 = r을 짝수로 올린 값. 첫 원의 중심은 선 시작이다 (가로 변은 셀 모서리 − 이웃
    /// 세로 변 폭/2, 세로 변은 셀 모서리; 이웃 칸과 이은 셀 테두리는 사슬의 무늬 원점, #238).
    /// 두께는 HWPUNIT으로 반올림한 뒤 장치 단위로 반올림한다 (4mm = 1134HWPUNIT = 94.5u → 95u —
    /// 두께를 바로 반올림하면 94u다). 실측(간격/경로 지름, u): 0.1mm 4/2, 0.12mm 6/4, 0.15mm 8/4,
    /// 0.2mm 10/6, 0.25mm 12/6, 0.3mm 14/8, 0.4mm 18/10, 0.5mm 24/12, 0.6mm 28/14, 0.7mm 34/18,
    /// 1mm 48/24, 1.5mm 70/36, 2mm 94/48, 3mm 142/72, 4mm 190/96, 5mm 236/118. 끝은 글자선 규칙이다
    /// — 중심이 선(이은 셀 테두리는 사슬) 끝 앞인 원을 끝에 걸쳐도 그린다 (#235·#238 —
    /// `HwpLineShapeGeometry.circleCount(for:)`). 단 구분선과 셀 간격이 있는 표의 셀 테두리(#243)는
    /// 이 격자가 아니라 글자선과 같은 점 무늬다 (같은 두께에서 원이 더 크고 성기다 — 1mm 간격
    /// 88u·경로 지름 36u).
    static let cellBorderCirclePitchUnitRatio: CGFloat = 2
}
