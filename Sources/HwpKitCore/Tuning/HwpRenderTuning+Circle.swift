import CoreGraphics

// MARK: - 원형 점선 (본체 파일 길이를 지키려 확장으로 둔다)

public extension HwpRenderTuning.LineShape {
    // 원형 점선(`circle`)의 원은 다른 무늬처럼 글자 크기·두께에 비례하지 않고 **600dpi 장치
    // 단위(`deviceUnit`, 0.12pt)의 정수**로 그린다 — 한글이 원의 크기와 간격을 장치 단위로
    // 반올림하기 때문이다. 비례로 두면 원마다 차가 쌓여 긴 run의 원 개수가 한글과 갈린다 (12pt
    // 간격 1.71pt vs 한글 1.80pt). 갈래는 둘이다. **점 무늬** — 한글 문서·MS 워드 호환 문서의
    // 글자선, 단 구분선, 셀 간격이 있는 표의 셀 테두리(#243)는 점선(1·1.5)의 점을 원으로 그린다:
    // 점 단위 q = 두께 × 22/15(대시 단위와
    // 같은 비)를 장치 단위로 반올림하고, 간격 = max(q, 3u) + max(1.5q 반올림, 2u), 원 경로 지름 =
    // q를 짝수로 올린 값(최소 2u)이다. 글자선의 두께는 글자 크기(HWPUNIT) × 0.039를 HWPUNIT으로
    // 반올림한 값, 단 구분선·셀 테두리는 명목 두께다. **격자** — 셀 간격이 없는 표의 셀 테두리는
    // 두께를 HWPUNIT으로 반올림한
    // 뒤 장치 단위로 반올림한 r(최소 1u)이 단위라 간격 2r, 경로 지름은 r을 짝수로 올린 값이다. 어느 갈래든 한글은 원
    // 경로를 채우고 한 단위 윤곽을 둘러 칠하므로 칠 지름 = 경로 지름 + 1u다 (한글 2007 호환
    // 문서의 1.32pt = 1.20 + 0.12와 같은 구성). 첫 원의 중심은 선 시작이고 끝 규칙은
    // #235·#238 그대로다 — 한글 2007 호환 문서는 고정 pt(`hwp200XCircle*`)라 이 규칙 밖이다.
    // 실측: 한글 12.30.0 build 6446 (2026-09-27) PDF 내보내기의 벡터 좌표 — 한글 문서 취소선
    // 1~100pt 1,010개(1~12pt 0.1pt 간격, 전환점 둘레 0.01~0.02pt 간격)·밑줄 217개(줄 기본 크기)·상대
    // 크기·위 첨자·크기가 섞인 줄·MS 워드 호환 문서 취소선 5~80pt, 단 구분선과 표 셀 테두리의 표 26
    // 굵기 16단(0.1~5mm)이 아래 식과 전부 같다 (셀 간격이 있는 표의 셀 테두리 16단은 2026-09-28 —
    // 셀 간격 283·1HWPUNIT 모두 단 구분선 값과 같다, #243). 원 중심의 세로 자리는 선 중심 ±1u다.
    // 검증: `HwpLineShapeGeometryTests+Circles` + `FixtureLineShapeRenderTests+RunEnd` +
    // `FixtureTableBorderChainTests` + `FixtureTableCellSpacingTests`.

    /// 한글이 원형 점선을 그리는 장치 단위 (pt) — 600dpi 한 칸(72/600). 원의 지름·간격은 이
    /// 단위의 정수다.
    static let deviceUnit: CGFloat = 0.12

    /// 글자선 원형 점선의 두께 (HWPUNIT) = 글자 크기(HWPUNIT) × 이 값 ÷ 1000을 반올림
    /// (0.039em). 점 단위는 이 두께 × 22/15(`circleDotUnitThicknessNumerator`/
    /// `…Denominator`)를 장치 단위로 반올림한 값이다 — 대시 단위 0.057em(≈ 0.039 × 22/15)과 같은
    /// 비지만, 두께를 먼저 HWPUNIT으로 반올림해야 한글의 전환점이 설명된다. 실측(점 단위가 바뀌는
    /// 크기, HWPUNIT): 730→731(3→4u)·935→936(4→5)·1141→1142(5→6)·1371→1372(6→7)·
    /// 1576→1577(7→8)·2192→2193(10→11)·2423→2424(11→12)·4730→4732(22→23)·
    /// 6602→6604(31→32)·8704→8706(41→42) — 한 번 반올림한 비례식으로는 9.36pt(5u)와 47pt(22u)를
    /// 함께 설명할 수 없다. 밑줄은 줄 글자 기본 크기, 취소선은 run의 글자 모양 기본 크기가
    /// 입력이다 (#226 — 상대 크기·위 첨자 전; MS 워드 호환 문서는 첨자 축소 전 run 크기 — 그 갈래의
    /// 취소선은 실측과 같고, 밑줄은 한글 기준 크기가 글자 크기의 약 1.7배라 남은 격차다 — #244).
    static let characterCircleThicknessPerMille: CGFloat = 39

    /// 원형 점선 점 단위의 두께 배율 22/15의 분자 — 글자선·단 구분선의 점 단위 = 두께 × 22/15를
    /// 장치 단위로 반올림. 대시 단위(`borderDashUnitThicknessRatio`)와 같은 비이지만 반올림
    /// 경계(0.5u)를 정확히 가르도록 정수 분수로 둔다 — 22/15를 이진 소수로 곱하면 두께 315HWPUNIT의
    /// 38.5u가 38.4999…로 내려가 80.65pt에서 간격 95u가 된다 (한글 실측 98u; 149.88pt(두께 585)도
    /// 한글 180u vs 178u — 두께 0~200만HWPUNIT 중 6,809곳이 이런 동점이다).
    static let circleDotUnitThicknessNumerator: CGFloat = 22

    /// 원형 점선 점 단위의 두께 배율 22/15의 분모 (`circleDotUnitThicknessNumerator`)
    static let circleDotUnitThicknessDenominator: CGFloat = 15

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
