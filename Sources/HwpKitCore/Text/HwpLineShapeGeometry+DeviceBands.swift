import CoreGraphics
import CoreHwp
import Foundation

// MARK: - 여러 줄·물결 — 장치 단위 정수 기하 (같은 타입의 확장 — 본체 파일 길이를 지킨다)

/// 2중선·가는+굵은 선·굵은+가는 선·3중선과 물결·2중 물결 — 한글은 이 선들을 600dpi 장치 단위(u = 0.12pt)의
/// 정수로 그린다. 먼저 장치 띠(정수 u)를 정하고, 그 띠를 같은 정수 규칙으로 부속선 두께·간격과 물결의
/// 대각선·반주기·획으로 나눈다. 띠를 정하는 입력은 축척마다 다르다:
///
/// - **글자선**(한글 문서·MS 워드 호환 문서의 `Scale.characterLine`, #252) — 기준 크기 X(HWPUNIT 정수,
///   `characterLine`의 `fontSize`)에서 띠 높이를 HWPUNIT으로 먼저 반올림하고, 그 값을 장치 단위로
///   반올림한다. 2중선·물결·2중 물결은 띠 P = round(X × 113/1000)HWPUNIT에서 r = round(P ÷ 12)u, 굵은 선이
///   섞인 여러 줄은 띠 H = round(X × 198/1000)HWPUNIT에서 E = round(H ÷ 12)u다.
/// - **표 셀 테두리·단 구분선**(`Scale.border`, #253) — 여섯 모양 모두 같은 굵기 실선의 획과 같은 띠
///   B = max(1, round(t ÷ 12))u다 (t = 표 26 굵기의 무늬 두께, `borderPatternHwpUnits(thickness:)` —
///   1mm 24u, 2mm 47u). r = E = B로 아래 규칙을 그대로 쓴다.
///
/// 띠 r(또는 E)을 나누는 규칙:
///
/// - **2중선·물결·2중 물결** — 획 w = round(r ÷ 4)u. 2중선은 두께 w 두 줄이 중심 사이 3w(공백 2w)이고,
///   물결은 대각선의 가로·세로가 r, 반주기가 r + 1(대각선 뒤 1u 평탄), 두 평탄 높이 사이가 2⌊r/2⌋, 획이
///   max(1, w)다. 2중 물결은 같은 물결을 3w 아래에 한 번 더 긋는다 — 한 물결은 2중선의 위 줄 자리, 2중
///   물결은 두 줄 자리다.
/// - **가는+굵은 선·굵은+가는 선·3중선** — 가는+굵은 선은 가는 선·공백이 ⌊E/4⌋(최소 1u), 굵은 선이
///   E − 2⌊E/4⌋(최소 3u — E ≤ 2u면 max(E, 1) 한 줄)이고, 3중선은 가는 선·공백이 max(1, ⌊E/6⌋), 굵은 선이
///   E − 4 × 그 값(E ≤ 5u면 min(E − 2, 2)u, 0이면 공백 둘만 남는다 — E ≤ 1u면 1u 한 줄)이다.
///
/// 띠의 가운데 M — 글자선은 단선과 같은 규칙에 두께 대신 띠 P·H를 넣은 자리다: 글자 아래 밑줄은 줄 상자
/// 바닥에서 ⌊띠/2⌋HWPUNIT 아래, 글자 위 밑줄은 줄 상자 상단에서 그만큼 위, 취소선(글자 가운데 밑줄)은
/// 단선 취소선의 중심이다. MS 워드 호환 문서의 밑줄은 취소선처럼 단선 중심이다 (#244 — 렌더러의
/// `underlineShapePlacement`). 테두리·단 구분선은 선 중심(셀 모서리·단 사이 간격의 가운데)이다. 장치 단위
/// 행은 그 M에서 센다: 부속선 띠는 M − ⌊전체/2⌋u에서 시작하고 (행 [a, a + w)의 획 중심은 a + ⌊w/2⌋ —
/// 홀수 폭이면 획이 행보다 반 칸 위로 치우친다), 물결의 위 평탄은 M − ⌊r/2⌋ − ⌈3w/2⌉u다. 한글은 이 행을
/// 쪽 절대 좌표의 600dpi 격자에서 세므로 글자선은 베이스라인 기준 자리가 줄마다 ±1u 흔들리고 표 테두리는
/// 셀 모서리가 격자로 반올림된다 — 우리는 쪽 격자를 흉내 내지 않고 M을 연속값으로 둔다 (그 1u 안에서
/// 한글과 갈린다).
///
/// 실측: 한컴오피스 한글 12.30.0 build 6523 PDF.
/// - 글자선 (2026-10-03, `probes/252`) — 6모양 × 아래 밑줄 1~100pt 1pt 간격 600표본, 취소선·위 밑줄
///   3~99pt 4pt 간격 300표본을 부속선 두께·간격·자리까지 이 식이 모두 재현하고 (자리는 각 줄의 쪽 절대
///   베이스라인을 줄 캐시에서 복원했을 때), build 6446의 #227 표본(글자 가운데 밑줄 포함) 100표본도 같다.
///   작은 크기·반올림 갈림 447표본(1~4pt 0.1pt 간격 등), 0.2~1pt 취소선 54표본과 MS 워드 호환 문서 글꼴
///   4종 288표본도 부속선 두께·물결 모양이 모두 같다. 우리 렌더를 한글 PDF와 대면 한글 문서 900표본의
///   부속선·물결 자리가 모두 1u 안이다 (종전 모델은 부속선 두께가 600표본 중 15개, 물결 모양이 300표본 중
///   0개만 맞았다). 종전 비례 모델(2중선 띠 0.12em, 그 밖 0.2em, 물결 진폭 0.112em·획 0.03em)은 이중선·물결
///   획이 56·80·100pt에서 1u 굵고 3중선 가운데 선이 10pt에서 0.41pt 가늘었다.
/// - 테두리·단 구분선 (2026-10-04, `probes/253`) — 1×1 표 6모양 × 표 26 굵기 16단 × 셀 간격 0·283HWPUNIT의
///   네 변 768개와 단 구분선 96개의 선분이 이 식과 하나하나 같고 (모서리 끝은 `HwpBorderSet`), 다칸 표
///   104개(1×2·2×1·2×2·3×3)도 쪽마다 같다. 종전 비례 모델(띠 = 명목 두께, 물결 진폭 = 두께·획 1/4)은 1mm
///   2중선 띠가 2.83pt(한글 2.88pt), 2mm 3중선 가운데 선이 15.75u(한글 19u), 1mm 물결 반주기가 24.62u(한글
///   25u)였다. 2중선 획 w는 round(t ÷ 48)이 아니라 round(B ÷ 4)다 — 0.25mm(t 70, B 6)에서 둘이 갈리고
///   한글은 2u다.
///
/// 한글 2007 호환 문서의 글자선(고정 pt, #227)은 이 모델 밖이다.
extension HwpLineShapeGeometry {
    /// 여러 줄의 부속선 하나 (로컬 y, pt) — 획 중심·두께와 정수 행 구간
    struct Stripe: Equatable {
        let center: CGFloat
        let thickness: CGFloat
        /// 부속선의 정수 행 [a, a + w) (로컬 y, pt) — 획은 a + ⌊w/2⌋에 중심을 둬 홀수 폭이면 이 구간보다 반
        /// 칸 위로 치우친다. 표 셀 테두리의 맞물린 모서리는 획이 아니라 이 구간으로 끝 자리를 정한다
        /// (`HwpBorderSet.nestedStripeOffset` — #253 실측: 2mm 3중선의 바깥 부속선 행 [−23, −16)u는 획이
        /// −23.5까지 칠하지만 맞물린 이웃 변은 −23에서 시작한다).
        let slot: ClosedRange<CGFloat>
    }

    /// 물결 하나의 기하 (로컬, pt). 대각선 k는 x = k × `halfPeriod`에서 시작해 가로 `run`만큼 간다 —
    /// 짝수 k는 `top`에서 `top + run`으로 내려가고, 홀수 k는 `top + levelGap`에서 `run`만큼 올라간다.
    /// 대각선 뒤 `flat` 길이의 평탄이 다음 대각선이 시작하는 높이에 놓인다 (짝수 k 뒤는
    /// `top + levelGap`, 홀수 k 뒤는 `top`). `straight`이면 물결 없이 `top`에 가로 선 하나다.
    struct Wave: Equatable {
        let run: CGFloat
        let levelGap: CGFloat
        let halfPeriod: CGFloat
        let flat: CGFloat
        let stroke: CGFloat
        let top: CGFloat
        /// 2중 물결의 둘째 파가 첫째 파보다 가로지르는 축으로 옮겨진 거리 (아래 +). 선 방향 자리는 파마다
        /// `Line.waveSpans`가 정한다.
        let secondOffset: CGFloat
        let straight: Bool

        /// 대각선 획 중심이 지나는 세로 범위 — 홀수 r이면 대각선이 평탄 높이를 1u 넘는다
        var centerRange: ClosedRange<CGFloat> {
            let low = min(top, top + levelGap - run)
            let high = max(top + run, top + levelGap)
            return straight ? top ... top : low ... high
        }
    }

    /// 장치 단위 띠 — 띠 높이(장치 단위 수 `rows`), 단위 길이(pt), 띠 가운데 M(로컬 y, pt), 정수로
    /// 반올림하는가. 무늬 두께가 장치 단위 반올림 상한(`deviceRoundingLimit`) 밖이면 반올림 없이 같은 비율을
    /// pt로 쓴다 (`rows`가 pt, 단위 1).
    struct DeviceBand {
        let rows: CGFloat
        let unit: CGFloat
        let center: CGFloat
        let rounds: Bool

        func round(_ value: CGFloat) -> CGFloat {
            rounds ? HwpLineShapeGeometry.roundHalfUp(value) : value
        }

        func floor(_ value: CGFloat) -> CGFloat {
            rounds ? value.rounded(.down) : value
        }

        func ceil(_ value: CGFloat) -> CGFloat {
            rounds ? value.rounded(.up) : value
        }
    }

    /// 여러 줄·물결의 장치 단위 띠 — 글자선(`characterBand(for:)`)과 테두리·단 구분선
    /// (`borderBand(for:)`). 한글 2007 호환 문서의 글자선(고정 pt)과 크기·두께가 양수가 아닌 입력은 nil.
    static func deviceBand(for line: Line) -> DeviceBand? {
        switch line.scale {
        case .characterLine:
            characterBand(for: line)
        case .border:
            borderBand(for: line)
        case .hwp200XCharacterLine:
            nil
        }
    }

    /// 글자선 띠 (`Scale.characterLine`이 아니거나 기준 크기가 양수가 아니면 nil). 2중선·물결·2중 물결은
    /// 띠 비율 113‰, 굵은 선이 섞인 여러 줄은 198‰다 (`HwpRenderTuning.LineShape.characterDoubleBandPerMille`·
    /// `characterThickBandPerMille`).
    static func characterBand(for line: Line) -> DeviceBand? {
        guard case let .characterLine(fontSize) = line.scale, fontSize > 0 else { return nil }
        typealias Shape = HwpRenderTuning.LineShape
        let perMille: CGFloat = switch line.shape {
        case .thinThickDoubleLine, .thickThinDoubleLine, .thinThickThinTripleLine:
            Shape.characterThickBandPerMille
        default:
            Shape.characterDoubleBandPerMille
        }
        guard patternThickness(for: line) < deviceRoundingLimit else {
            // 나눗셈 먼저 — 글자 크기가 유한 최댓값 근처여도 넘치지 않게
            let band = fontSize / 1000 * perMille
            return DeviceBand(
                rows: band, unit: 1, center: characterBandCenter(for: line, halfBand: band / 2),
                rounds: false
            )
        }
        let hwpUnits = roundHalfUp((fontSize * 100).rounded() * perMille / 1000)
        return DeviceBand(
            rows: roundHalfUp(hwpUnits / hwpUnitsPerDeviceUnit), unit: Shape.deviceUnit,
            center: characterBandCenter(for: line, halfBand: (hwpUnits / 2).rounded(.down) / 100),
            rounds: true
        )
    }

    /// 표 셀 테두리·단 구분선 띠 (`Scale.border`가 아니거나 두께가 양수가 아니면 nil) — 같은 굵기 실선의
    /// 획과 같은 B = max(1, round(t ÷ 12))u(`borderStrokeUnits(_:)`), 가운데는 선 중심 0이다 (#253). 두께가
    /// 장치 단위 반올림 상한 밖이면 두께를 그대로 비례 띠로 쓴다.
    static func borderBand(for line: Line) -> DeviceBand? {
        guard line.scale == .border, line.thickness > 0 else { return nil }
        guard line.thickness < deviceRoundingLimit else {
            return DeviceBand(rows: line.thickness, unit: 1, center: 0, rounds: false)
        }
        return DeviceBand(
            rows: borderStrokeUnits(line.thickness), unit: HwpRenderTuning.LineShape.deviceUnit,
            center: 0, rounds: true
        )
    }

    /// 띠의 가운데 M (로컬 y, pt) — 단선 중심이 0이고 아래가 +다. 글자 아래 밑줄은 줄 상자 바닥(단선의
    /// 위 가장자리 −두께/2)에서 띠 절반(`halfBand` — ⌊띠 HWPUNIT/2⌋ pt) 아래, 글자 위 밑줄은 줄 상자
    /// 상단(+두께/2)에서 그만큼 위, 나머지(취소선·MS 워드 호환 밑줄)는 단선 중심이다.
    static func characterBandCenter(for line: Line, halfBand: CGFloat) -> CGFloat {
        switch line.placement {
        case .underlineBelow:
            -line.thickness / 2 + halfBand
        case .underlineAbove:
            line.thickness / 2 - halfBand
        case .strikethrough, .border, .divider:
            0
        }
    }

    /// 여러 줄의 부속선 (위에서 아래로) — 장치 단위 띠가 없으면(한글 2007 호환 문서의 글자선) nil (호출자가
    /// 비율 띠 `hwp200XStripeFractions(for:)`로 떨어진다).
    static func deviceStripes(for line: Line) -> [Stripe]? {
        guard let band = deviceBand(for: line) else { return nil }
        let rows = deviceStripeRows(shape: line.shape, band: band)
        guard let total = rows.last.map({ $0.start + $0.width }) else { return [] }
        let top = -band.floor(total / 2)
        return rows.map { row in
            let start = top + row.start
            let lower = band.center + start * band.unit
            return Stripe(
                center: band.center + (start + band.floor(row.width / 2)) * band.unit,
                thickness: row.width * band.unit, slot: lower ... (lower + row.width * band.unit)
            )
        }
    }

    /// 부속선의 행 [start, start + width) (단위 `band.unit`) — 띠 위 끝이 0이다.
    static func deviceStripeRows(
        shape: HwpBorderType, band: DeviceBand
    ) -> [(start: CGFloat, width: CGFloat)] {
        let rows = band.rows
        let minimum: CGFloat = band.rounds ? 1 : 0
        switch shape {
        case .doubleLine:
            let stroke = band.round(rows / 4)
            guard stroke > 0 else { return [(0, max(minimum, rows))] }
            return [(0, stroke), (3 * stroke, stroke)]
        case .thinThickDoubleLine, .thickThinDoubleLine:
            // 띠 2u 이하는 굵은 선 하나, 그 위는 가는 선·공백 ⌊E/4⌋(최소 1u)에 굵은 선이 최소 3u다
            // (한글 12.30 실측: 글자선 E = 3·4u인 1.49~2.70pt가 1/1/3u, 테두리 0.12~0.2mm(B 3~5u)도 1/1/3u)
            guard !band.rounds || rows > 2 else { return [(0, max(rows, 1))] }
            let quarter = band.floor(rows / 4)
            let thin = max(minimum, quarter)
            let thick = band.rounds ? max(rows - 2 * quarter, 3) : rows - 2 * quarter
            return shape == .thinThickDoubleLine
                ? [(0, thin), (2 * thin, thick)]
                : [(0, thick), (thick + thin, thin)]
        case .thinThickThinTripleLine:
            // 띠 1u 이하는 1u 한 줄, 그 위는 가는 선·공백 max(1, ⌊E/6⌋)에 가운데 굵은 선 E − 4 × 가는
            // 선 — 띠 5u 이하는 굵은 선이 min(E − 2, 2)u다 (한글 12.30 실측: E = 0·1u인 0.2~0.8pt가 1u
            // 한 줄, E = 2·3·4·5u가 굵은 선 0·1·2·2u, 0이면 가는 선 둘만 긋는다 — 테두리 0.1~0.25mm도 같다)
            guard !band.rounds || rows > 1 else { return [(0, 1)] }
            let thin = max(minimum, band.floor(rows / 6))
            let thick = band.rounds ? max(rows - 4 * thin, min(rows - 2, 2)) : rows - 4 * thin
            // 굵은 선이 0이어도 그 자리의 공백 둘은 남는다 (한글 0.9~1.4pt: 가는 선 둘이 3u 간격)
            return [(0, thin), (2 * thin, thick), (3 * thin + thick, thin)].filter { $0.width > 0 }
        default:
            return []
        }
    }

    /// 장치 단위 물결 — 장치 단위 띠가 없으면 nil (호출자가 한글 2007 호환 문서의 고정 물결로 떨어진다).
    static func deviceWave(for line: Line) -> Wave? {
        guard let band = deviceBand(for: line) else { return nil }
        let run = band.rows
        let stroke = band.round(run / 4)
        let half = band.floor(run / 2)
        let lift = band.ceil(3 * stroke / 2)
        return Wave(
            run: run * band.unit,
            levelGap: 2 * half * band.unit,
            halfPeriod: (run + 1) * band.unit,
            flat: band.unit,
            stroke: max(band.rounds ? 1 : 0, stroke) * band.unit,
            top: band.center - (half + lift) * band.unit,
            secondOffset: 3 * stroke * band.unit,
            straight: band.rounds && half == 0
        )
    }

    /// 물결 파마다 맞물린 모서리 끝 자리의 기준 — 2중선의 두 부속선 행 [−2w, −w)·[w, 2w) (로컬 y, pt;
    /// w = 물결의 획 몫 round(r ÷ 4)). 한글은 표 셀 테두리의 물결을 2중선의 위·아래 줄 자리로 보고 맞물린
    /// 모서리에서 부속선처럼 따로 물린다 (#253 — `HwpBorderSet`이 파마다 `nestedStripeOffset`으로 쓴다).
    /// 장치 단위 띠가 없으면 빈 배열.
    static func waveSlots(for line: Line) -> [ClosedRange<CGFloat>] {
        guard let band = deviceBand(for: line) else { return [] }
        let stroke = band.round(band.rows / 4)
        guard stroke > 0 else { return [] }
        let unit = band.unit
        return [
            (band.center - 2 * stroke * unit) ... (band.center - stroke * unit),
            (band.center + stroke * unit) ... (band.center + 2 * stroke * unit),
        ]
    }
}
